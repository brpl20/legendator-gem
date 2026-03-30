module Legendator
  class Configuration
    attr_accessor :provider, :model, :target_language,
                  :max_tokens_per_chunk, :prompt_overhead, :temperature,
                  :api_key, :openai_api_key, :openrouter_api_key,
                  :fallback_providers, :max_retries, :retry_base_delay

    def initialize
      @provider             = ENV.fetch("DEFAULT_PROVIDER", "openai").to_sym
      @model                = ENV.fetch("DEFAULT_MODEL", "gpt-4.1-mini")
      @target_language      = ENV.fetch("DEFAULT_TARGET_LANGUAGE", "pt-BR")
      @max_tokens_per_chunk = ENV.fetch("MAX_TOKENS_PER_CHUNK", "6000").to_i
      @prompt_overhead      = ENV.fetch("PROMPT_OVERHEAD", "200").to_i
      @temperature          = ENV.fetch("TEMPERATURE", "0.1").to_f
      @api_key              = nil
      @openai_api_key       = nil
      @openrouter_api_key   = nil
      @fallback_providers   = []       # e.g. [{ provider: :openai, model: "gpt-4.1-mini" }]
      @max_retries          = 3        # retries per provider before moving to fallback
      @retry_base_delay     = 2        # base delay in seconds for exponential backoff
    end

    # Resolve the API key for a given provider.
    # Priority: generic api_key > provider-specific key > ENV variable
    def api_key_for(provider)
      provider = provider.to_sym
      return @api_key if @api_key

      case provider
      when :openai
        @openai_api_key || ENV["OPENAI_API_KEY"]
      when :openrouter
        @openrouter_api_key || ENV["OPENROUTER_API_KEY"]
      else
        ENV[Legendator::AiClient::PROVIDERS.dig(provider, :env_key)]
      end
    end
  end
end
