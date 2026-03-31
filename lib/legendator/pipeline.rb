module Legendator
  class Pipeline
    Result = Struct.new(
      :srt_content, :coverage, :token_usage, :chunks_info, :provider, :model, :cost, :consistency,
      keyword_init: true
    )

    def initialize(
      provider: Config.provider,
      model: Config.model,
      target_language: Config.target_language,
      context: nil,
      max_tokens_per_chunk: Config.max_tokens_per_chunk,
      api_key: nil,
      logger: nil,
      fallback_providers: nil
    )
      @provider = provider.to_sym
      @model = model
      @target_language = target_language
      @context = context
      @max_tokens = max_tokens_per_chunk
      @api_key = api_key
      @logger = logger
      @fallback_providers = fallback_providers || Legendator.configuration.fallback_providers || []

      @token_counter = TokenCounter.new(model: @model)
      @file_breaker = FileBreaker.new(
        token_counter: @token_counter,
        max_tokens_per_chunk: @max_tokens
      )
    end

    MAX_REPAIR_ATTEMPTS = 2

    # Run the full pipeline on an SRT file
    def run(srt_content)
      log "[1/7] Parsing SRT file..."
      parser = SrtParser.new(srt_content)
      texts = parser.extract_texts
      timestamps = parser.extract_timestamps

      if texts.empty?
        raise "No subtitles found in the file"
      end

      log "     Found #{texts.size} subtitles"
      log "     Token counting method: #{@token_counter.method_used}"

      log "[2/7] Breaking into chunks..."
      chunks = @file_breaker.break_into_chunks(texts)
      chunks_info = @file_breaker.summary(chunks)
      log "     #{chunks_info[:total_chunks]} chunks, ~#{chunks_info[:total_tokens]} tokens total"

      # Build provider chain: primary first, then fallbacks (excluding duplicates of the primary)
      primary = { provider: @provider, model: @model, api_key: @api_key }
      filtered_fallbacks = @fallback_providers.reject do |fb|
        fb[:provider].to_sym == @provider && fb[:model] == @model
      end
      provider_chain = [primary] + filtered_fallbacks
      active_provider = nil
      active_model = nil
      client = nil

      all_translations = {}
      total_input_tokens = 0
      total_output_tokens = 0
      total_cost = 0.0

      log "[3/7] Translating with #{@provider}/#{@model}..."

      chunks.each_with_index do |chunk, i|
        chunk_text = @file_breaker.format_chunk(chunk)
        log "     Chunk #{i + 1}/#{chunks.size} (#{chunk.entries.size} subtitles, ~#{chunk.token_count} tokens)..."

        result = translate_chunk_with_fallback(chunk_text, provider_chain)
        active_provider = result[:active_provider]
        active_model = result[:active_model]
        client = result[:client]

        all_translations.merge!(result[:translations])
        total_input_tokens += result[:response].input_tokens
        total_output_tokens += result[:response].output_tokens

        if result[:response].cost
          total_cost += result[:response].cost
        else
          log "     Warning: no cost data returned for chunk #{i + 1}"
        end

        # Rate limit: small delay between chunks
        sleep(0.5) if i < chunks.size - 1
      end

      # Use the last successful client for repairs
      client ||= AiClient.new(provider: @provider, model: @model, api_key: @api_key)

      log "[4/7] Repairing missing subtitles..."
      repair_result = repair_missing(client, texts, all_translations)
      total_input_tokens += repair_result[:input_tokens]
      total_output_tokens += repair_result[:output_tokens]
      total_cost += repair_result[:cost]

      # Remove extra IDs not in original
      extra_ids = all_translations.keys - texts.keys
      if extra_ids.any?
        log "     Removing #{extra_ids.size} extra IDs: #{extra_ids.sort.join(', ')}"
        extra_ids.each { |id| all_translations.delete(id) }
      end

      log "[5/7] Reconstructing SRT..."
      reconstructor = SrtReconstructor.new(all_translations, timestamps, texts)
      srt_output = reconstructor.build
      coverage = reconstructor.coverage_report
      log "     Coverage: #{coverage[:coverage_percent]}% (#{coverage[:translated]}/#{coverage[:total_subtitles]})"

      if coverage[:missing_ids].any?
        log "     Missing IDs after repair: #{coverage[:missing_ids].join(', ')}"
      end

      log "[6/7] Checking consistency..."
      consistency_checker = ConsistencyChecker.new(
        original_srt: srt_content,
        translated_srt: srt_output,
        target_language: @target_language,
        provider: @provider,
        model: @model,
        api_key: @api_key
      )
      consistency = consistency_checker.run

      if consistency.pass?
        log "     Consistency check passed"
      else
        log "     Consistency check FAILED: #{consistency.errors.join('; ')}"
      end

      log "[7/7] Done!"

      Result.new(
        srt_content: srt_output,
        coverage: coverage,
        token_usage: {
          input_tokens: total_input_tokens,
          output_tokens: total_output_tokens,
          total_tokens: total_input_tokens + total_output_tokens
        },
        chunks_info: chunks_info,
        provider: active_provider || @provider,
        model: active_model || @model,
        cost: total_cost,
        consistency: consistency
      )
    end

    # Dry run: parse + chunk but don't call AI
    def dry_run(srt_content)
      parser = SrtParser.new(srt_content)
      texts = parser.extract_texts

      chunks = @file_breaker.break_into_chunks(texts)
      chunks_info = @file_breaker.summary(chunks)

      request_estimate = @token_counter.estimate_request(
        texts.values.join("\n"),
        prompt_overhead: 200 * chunks.size
      )

      {
        subtitles: texts.size,
        chunks: chunks_info,
        estimated_tokens: request_estimate,
        provider: @provider,
        model: @model,
        target_language: @target_language
      }
    end

    private

    # Try translating a chunk with the primary provider, falling back to alternatives on failure.
    # Each provider in the chain gets full retry attempts (configured in AiClient) before
    # moving to the next. Raises if ALL providers in the chain fail.
    def translate_chunk_with_fallback(chunk_text, provider_chain)
      errors_by_provider = []

      provider_chain.each_with_index do |provider_config, idx|
        prov = provider_config[:provider].to_sym
        mod = provider_config[:model] || @model
        key = provider_config[:api_key]

        begin
          client = AiClient.new(provider: prov, model: mod, api_key: key)
          result = client.translate(
            chunk_text,
            target_language: @target_language,
            context: @context
          )

          if idx > 0
            log "     Fallback successful: using #{prov}/#{mod}"
          end

          return {
            translations: result[:translations],
            response: result[:response],
            client: client,
            active_provider: prov,
            active_model: mod
          }
        rescue AiClient::RetriesExhaustedError => e
          # All retries exhausted for this provider — cascade to next
          errors_by_provider << { provider: prov, model: mod, error: sanitize_error(e) }
          log_fallback(prov, mod, e, provider_chain, idx)
        rescue Legendator::ConfigurationError => e
          # Bad config (unknown provider, missing key) — cascade to next
          errors_by_provider << { provider: prov, model: mod, error: sanitize_error(e) }
          log_fallback(prov, mod, e, provider_chain, idx)
        rescue Legendator::Error => e
          # Known translation/parse errors — cascade to next
          errors_by_provider << { provider: prov, model: mod, error: sanitize_error(e) }
          log_fallback(prov, mod, e, provider_chain, idx)
        end
        # Note: unexpected errors (NoMethodError, etc.) propagate immediately
      end

      # All providers exhausted — use sanitized error summaries
      error_details = errors_by_provider.map { |e| "#{e[:provider]}/#{e[:model]}: #{e[:error]}" }.join("; ")
      raise Legendator::TranslationError,
        "All providers failed. Tried #{provider_chain.size} provider(s): #{error_details}"
    end

    def log_fallback(prov, mod, error, provider_chain, idx)
      return unless idx < provider_chain.size - 1
      next_prov = provider_chain[idx + 1]
      log "     FALLBACK: #{prov}/#{mod} failed (#{sanitize_error(error)}). Trying #{next_prov[:provider]}/#{next_prov[:model] || @model}..."
    end

    # Strip potentially sensitive details (API response bodies, keys) from error messages
    def sanitize_error(error)
      case error
      when AiClient::ApiError
        "HTTP #{error.status_code}"
      when AiClient::RetriesExhaustedError
        msg = error.message
        msg = "HTTP #{error.status_code} (retries exhausted)" if error.status_code
        msg
      else
        # Truncate to avoid leaking full API responses
        msg = error.message.to_s
        msg.length > 120 ? "#{msg[0, 120]}..." : msg
      end
    end

    # Re-translate subtitles that the AI dropped from chunk responses.
    # Tries up to MAX_REPAIR_ATTEMPTS times, sending only the missing IDs.
    def repair_missing(client, original_texts, all_translations)
      total_input = 0
      total_output = 0
      total_cost = 0.0

      MAX_REPAIR_ATTEMPTS.times do |attempt|
        missing_ids = original_texts.keys - all_translations.keys
        break if missing_ids.empty?

        log "     Attempt #{attempt + 1}/#{MAX_REPAIR_ATTEMPTS}: repairing #{missing_ids.size} missing subtitle(s) (IDs: #{missing_ids.sort.join(', ')})"

        # Build a mini-chunk with just the missing subtitles
        missing_texts = missing_ids.sort.each_with_object({}) { |id, h| h[id] = original_texts[id] }
        chunk = FileBreaker::Chunk.new(entries: missing_texts, token_count: 0)
        chunk_text = @file_breaker.format_chunk(chunk)

        result = client.translate(
          chunk_text,
          target_language: @target_language,
          context: @context
        )

        all_translations.merge!(result[:translations])
        total_input += result[:response].input_tokens
        total_output += result[:response].output_tokens
        total_cost += result[:response].cost.to_f

        still_missing = original_texts.keys - all_translations.keys
        if still_missing.empty?
          log "     All missing subtitles repaired"
          break
        end
      end

      remaining = original_texts.keys - all_translations.keys
      if remaining.any?
        log "     WARNING: #{remaining.size} subtitle(s) still missing after #{MAX_REPAIR_ATTEMPTS} repair attempts (IDs: #{remaining.sort.join(', ')})"
      end

      { input_tokens: total_input, output_tokens: total_output, cost: total_cost }
    end

    def log(message)
      @logger&.call(message)
    end
  end
end
