require "net/http"
require "uri"
require "json"

module Legendator
  class AiClient
    PROVIDERS = {
      openai: {
        base_url: "https://api.openai.com/v1/responses",
        env_key: "OPENAI_API_KEY"
      },
      openrouter: {
        base_url: "https://openrouter.ai/api/v1/chat/completions",
        env_key: "OPENROUTER_API_KEY"
      }
    }.freeze

    # HTTP status codes that are safe to retry
    RETRYABLE_STATUS_CODES = [429, 500, 502, 503, 504].freeze

    # Maximum backoff delay in seconds to prevent unbounded sleep
    MAX_BACKOFF_DELAY = 30

    # Errors that indicate transient network issues (retry-safe)
    RETRYABLE_NETWORK_ERRORS = [
      Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET,
      Errno::ECONNREFUSED, Errno::ETIMEDOUT,
      SocketError, EOFError
    ].freeze

    Response = Struct.new(:content, :input_tokens, :output_tokens, :model, :raw, :cost, keyword_init: true)

    # Structured error for HTTP API failures (carries status code directly)
    class ApiError < Legendator::TranslationError
      attr_reader :status_code, :response_body

      def initialize(status_code, response_body)
        @status_code = status_code
        @response_body = response_body
        super("API Error (#{status_code})")
      end
    end

    # Raised after all retries for a provider are exhausted (signals Pipeline to try fallback)
    class RetriesExhaustedError < Legendator::TranslationError
      attr_reader :status_code, :provider

      def initialize(message, status_code: nil, provider: nil)
        @status_code = status_code
        @provider = provider
        super(message)
      end
    end

    def initialize(provider: Config.provider, model: Config.model, api_key: nil)
      @provider = provider.to_sym
      @model = model
      @api_key = api_key || Legendator.configuration.api_key_for(@provider)
      @base_url = PROVIDERS.dig(@provider, :base_url)
      @max_retries = Legendator.configuration.max_retries
      @retry_base_delay = Legendator.configuration.retry_base_delay

      raise Legendator::ConfigurationError, "Unknown provider: #{@provider}" unless PROVIDERS.key?(@provider)
      raise Legendator::ConfigurationError, "API key not set for #{@provider}. Set #{PROVIDERS.dig(@provider, :env_key)}" if @api_key.nil? || @api_key.empty?
    end

    # Send a translation request for a chunk of subtitles
    # chunk_text: formatted as "ID|text\nID|text\n..."
    # context: additional context like "This is from Lord of the Rings"
    # target_language: e.g. "pt-BR"
    def translate(chunk_text, target_language:, context: nil)
      system_prompt = build_system_prompt(target_language, context)
      user_prompt = build_user_prompt(chunk_text)

      response = chat(system_prompt: system_prompt, user_prompt: user_prompt)

      # Parse structured response
      translations = parse_translation_response(response.content)

      { translations: translations, response: response }
    end

    # Raw chat completion with automatic retry and exponential backoff.
    # Makes up to max_retries + 1 total attempts (1 initial + max_retries retries).
    def chat(system_prompt:, user_prompt:, temperature: Config.temperature)
      last_error = nil

      (1..@max_retries + 1).each do |attempt|
        begin
          return execute_chat_request(
            system_prompt: system_prompt,
            user_prompt: user_prompt,
            temperature: temperature
          )
        rescue *RETRYABLE_NETWORK_ERRORS => e
          raise e if ssl_certificate_error?(e)
          last_error = e
          if attempt <= @max_retries
            sleep(backoff_delay(attempt))
          else
            raise RetriesExhaustedError.new(
              "#{@provider} network error after #{@max_retries} retries: #{e.class}",
              provider: @provider
            )
          end
        rescue ApiError => e
          last_error = e
          if RETRYABLE_STATUS_CODES.include?(e.status_code) && attempt <= @max_retries
            sleep(backoff_delay(attempt))
          elsif RETRYABLE_STATUS_CODES.include?(e.status_code)
            raise RetriesExhaustedError.new(
              "#{@provider} API error after #{@max_retries} retries (HTTP #{e.status_code})",
              status_code: e.status_code, provider: @provider
            )
          else
            raise
          end
        end
      end

      # Should not reach here, but just in case
      raise last_error if last_error
    end

    private

    def backoff_delay(attempt)
      # Exponential backoff with jitter, capped at MAX_BACKOFF_DELAY
      base = [@retry_base_delay * (2**(attempt - 1)), MAX_BACKOFF_DELAY].min
      jitter = rand * base * 0.5
      base + jitter
    end

    # Distinguish TLS certificate failures (security-critical, should not retry)
    # from transient SSL errors (handshake timeouts, etc.)
    def ssl_certificate_error?(error)
      return false unless error.is_a?(OpenSSL::SSL::SSLError)
      error.message =~ /certificate|verify|cert/i
    end

    def execute_chat_request(system_prompt:, user_prompt:, temperature:)
      uri = URI(@base_url)

      body = if @provider == :openai
        {
          model: @model,
          temperature: temperature,
          input: [
            { role: "system", content: [{ type: "input_text", text: system_prompt }] },
            { role: "user", content: [{ type: "input_text", text: user_prompt }] }
          ],
          text: { format: { type: "json_object" } }
        }
      else
        {
          model: @model,
          temperature: temperature,
          messages: [
            { role: "system", content: system_prompt },
            { role: "user", content: user_prompt }
          ],
          response_format: { type: "json_object" }
        }
      end

      headers = {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{@api_key}"
      }

      # OpenRouter specific headers
      if @provider == :openrouter
        headers["HTTP-Referer"] = "https://legendator.com.br"
        headers["X-Title"] = "Legendator"
      end

      # Configure SSL cert store without CRL checking (macOS/rbenv compatibility)
      cert_store = OpenSSL::X509::Store.new
      cert_store.set_default_paths

      request = Net::HTTP::Post.new(uri.path, headers)
      request.body = body.to_json

      raw_response = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: true,
        read_timeout: 180,
        open_timeout: 60,
        cert_store: cert_store,
        verify_mode: OpenSSL::SSL::VERIFY_PEER
      ) { |http| http.request(request) }

      unless raw_response.is_a?(Net::HTTPSuccess)
        raise ApiError.new(raw_response.code.to_i, raw_response.body)
      end

      parsed = JSON.parse(raw_response.body)
      if @provider == :openai
        choice = parsed.dig("output", 0, "content", 0, "text") || ""
        usage = parsed["usage"] || {}
        input_tokens = usage["input_tokens"] || 0
        output_tokens = usage["output_tokens"] || 0
        model = parsed["model"] || @model
        cost = nil
      else
        choice = parsed.dig("choices", 0, "message", "content") || ""
        usage = parsed["usage"] || {}
        input_tokens = usage["prompt_tokens"] || 0
        output_tokens = usage["completion_tokens"] || 0
        model = parsed["model"] || @model
        cost = usage["total_cost"]&.to_f
      end

      Response.new(
        content: choice,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        model: model,
        raw: parsed,
        cost: cost
      )
    end

    def build_system_prompt(target_language, context)
      lang_names = {
        "pt-BR" => "Brazilian Portuguese",
        "pt-PT" => "European Portuguese",
        "es" => "Spanish",
        "fr" => "French",
        "de" => "German",
        "it" => "Italian",
        "ja" => "Japanese",
        "ko" => "Korean",
        "zh" => "Simplified Chinese",
        "en" => "English"
      }

      lang = lang_names[target_language] || target_language

      prompt = <<~PROMPT
        You are a professional subtitle translator. Translate subtitles to #{lang}.

        Rules:
        - Maintain the exact same ID numbers
        - Translate naturally, as spoken dialogue (not literal/robotic)
        - Keep proper nouns (character names, place names) as they are commonly known in #{lang}
        - Preserve line breaks within subtitles using <br> placeholder
        - Return ONLY valid JSON in this exact format: {"translations": {"1": "translated text", "2": "translated text"}}
        - Do NOT add any explanation, markdown, or extra text
      PROMPT

      if context && !context.strip.empty?
        prompt += "\nContext about this content: #{context}\n"
        prompt += "Use this context to improve translation accuracy (character names, tone, setting).\n"
      end

      prompt
    end

    def build_user_prompt(chunk_text)
      "Translate these subtitles. Each line is formatted as ID|text:\n\n#{chunk_text}"
    end

    # Parse the AI response into { id => translated_text }
    def parse_translation_response(content)
      # Try JSON parse first
      parsed = begin
        JSON.parse(content)
      rescue JSON::ParserError
        nil
      end

      if parsed && parsed["translations"]
        # Convert string keys to integer keys
        return parsed["translations"].each_with_object({}) do |(k, v), hash|
          hash[k.to_i] = v.to_s
        end
      end

      # Fallback: try to extract JSON from markdown code blocks
      if content =~ /```(?:json)?\s*(\{.*?\})\s*```/m
        begin
          parsed = JSON.parse($1)
          if parsed["translations"]
            return parsed["translations"].each_with_object({}) do |(k, v), hash|
              hash[k.to_i] = v.to_s
            end
          end
        rescue JSON::ParserError
          # continue to line-by-line fallback
        end
      end

      # Fallback: parse line-by-line format (ID|text)
      translations = {}
      content.each_line do |line|
        line = line.strip
        next if line.empty? || !line.include?("|")
        id_str, text = line.split("|", 2)
        id = id_str.gsub(/\D/, "").to_i
        next if id.zero?
        translations[id] = text.strip
      end

      translations
    end
  end
end
