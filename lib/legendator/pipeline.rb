module Legendator
  class Pipeline
    Result = Struct.new(
      :srt_content, :coverage, :token_usage, :chunks_info, :provider, :model,
      keyword_init: true
    )

    def initialize(
      provider: Config.provider,
      model: Config.model,
      target_language: Config.target_language,
      context: nil,
      max_tokens_per_chunk: Config.max_tokens_per_chunk,
      api_key: nil,
      logger: nil
    )
      @provider = provider.to_sym
      @model = model
      @target_language = target_language
      @context = context
      @max_tokens = max_tokens_per_chunk
      @api_key = api_key
      @logger = logger

      @token_counter = TokenCounter.new(model: @model)
      @file_breaker = FileBreaker.new(
        token_counter: @token_counter,
        max_tokens_per_chunk: @max_tokens
      )
    end

    # Run the full pipeline on an SRT file
    def run(srt_content)
      log "[1/5] Parsing SRT file..."
      parser = SrtParser.new(srt_content)
      texts = parser.extract_texts
      timestamps = parser.extract_timestamps

      if texts.empty?
        raise "No subtitles found in the file"
      end

      log "     Found #{texts.size} subtitles"
      log "     Token counting method: #{@token_counter.method_used}"

      log "[2/5] Breaking into chunks..."
      chunks = @file_breaker.break_into_chunks(texts)
      chunks_info = @file_breaker.summary(chunks)
      log "     #{chunks_info[:total_chunks]} chunks, ~#{chunks_info[:total_tokens]} tokens total"

      log "[3/5] Translating with #{@provider}/#{@model}..."
      client = AiClient.new(provider: @provider, model: @model, api_key: @api_key)

      all_translations = {}
      total_input_tokens = 0
      total_output_tokens = 0

      chunks.each_with_index do |chunk, i|
        chunk_text = @file_breaker.format_chunk(chunk)
        log "     Chunk #{i + 1}/#{chunks.size} (#{chunk.entries.size} subtitles, ~#{chunk.token_count} tokens)..."

        result = client.translate(
          chunk_text,
          target_language: @target_language,
          context: @context
        )

        all_translations.merge!(result[:translations])
        total_input_tokens += result[:response].input_tokens
        total_output_tokens += result[:response].output_tokens

        # Rate limit: small delay between chunks
        sleep(0.5) if i < chunks.size - 1
      end

      log "[4/5] Reconstructing SRT..."
      reconstructor = SrtReconstructor.new(all_translations, timestamps, texts)
      srt_output = reconstructor.build
      coverage = reconstructor.coverage_report
      log "     Coverage: #{coverage[:coverage_percent]}% (#{coverage[:translated]}/#{coverage[:total_subtitles]})"

      if coverage[:missing_ids].any?
        log "     Missing IDs: #{coverage[:missing_ids].join(', ')}"
      end

      log "[5/5] Done!"

      Result.new(
        srt_content: srt_output,
        coverage: coverage,
        token_usage: {
          input_tokens: total_input_tokens,
          output_tokens: total_output_tokens,
          total_tokens: total_input_tokens + total_output_tokens
        },
        chunks_info: chunks_info,
        provider: @provider,
        model: @model
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

    def log(message)
      @logger&.call(message)
    end
  end
end
