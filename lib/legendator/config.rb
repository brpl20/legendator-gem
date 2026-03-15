module Legendator
  module Config
    def self.provider
      Legendator.configuration.provider
    end

    def self.model
      Legendator.configuration.model
    end

    def self.target_language
      Legendator.configuration.target_language
    end

    def self.max_tokens_per_chunk
      Legendator.configuration.max_tokens_per_chunk
    end

    def self.prompt_overhead
      Legendator.configuration.prompt_overhead
    end

    def self.temperature
      Legendator.configuration.temperature
    end
  end
end
