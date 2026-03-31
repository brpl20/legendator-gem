module Legendator
  # Errors (defined before requires so subclasses in other files can inherit)
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class TranslationError < Error; end
  class ParseError < Error; end
end

require_relative "legendator/version"
require_relative "legendator/configuration"
require_relative "legendator/config"
require_relative "legendator/srt_parser"
require_relative "legendator/token_counter"
require_relative "legendator/file_breaker"
require_relative "legendator/ai_client"
require_relative "legendator/srt_reconstructor"
require_relative "legendator/pipeline"
require_relative "legendator/consistency_checker"

module Legendator

  class << self
    # Returns the global configuration singleton.
    def configuration
      @configuration ||= Configuration.new
    end

    # Yields the configuration for block-style setup.
    #
    #   Legendator.configure do |config|
    #     config.provider = :openai
    #     config.api_key  = "sk-..."
    #   end
    def configure
      yield(configuration)
    end

    # Reset configuration (useful in tests).
    def reset_configuration!
      @configuration = Configuration.new
    end

    # Translate an SRT file on disk.
    # Returns a Pipeline::Result.
    def translate(path, lang: nil, output: nil, context: nil, **overrides)
      content = File.read(path)
      result = translate_content(content, lang: lang, context: context, **overrides)

      if output || path
        output_path = output || path.sub(/\.srt\z/i, "_#{lang || configuration.target_language}.srt")
        File.write(output_path, result.srt_content)
      end

      result
    end

    # Translate an SRT string in memory.
    # Returns a Pipeline::Result.
    def translate_content(srt_string, lang: nil, context: nil, **overrides)
      pipeline = build_pipeline(lang: lang, context: context, **overrides)
      pipeline.run(srt_string)
    end

    # Dry run on a file (no API calls).
    def dry_run(path)
      dry_run_content(File.read(path))
    end

    # Dry run on an SRT string (no API calls).
    def dry_run_content(srt_string, **overrides)
      pipeline = build_pipeline(**overrides)
      pipeline.dry_run(srt_string)
    end

    private

    # Build a Pipeline merging keyword overrides > configuration defaults.
    def build_pipeline(lang: nil, context: nil, **overrides)
      cfg = configuration
      Pipeline.new(
        provider:             overrides[:provider]   || cfg.provider,
        model:                overrides[:model]      || cfg.model,
        target_language:      lang                   || cfg.target_language,
        context:              context,
        max_tokens_per_chunk: overrides[:max_tokens_per_chunk] || cfg.max_tokens_per_chunk,
        api_key:              overrides[:api_key],
        fallback_providers:   overrides[:fallback_providers] || cfg.fallback_providers
      )
    end
  end
end
