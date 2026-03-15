module Legendator
  class TokenCounter
    attr_reader :method_used

    def initialize(model: Config.model)
      @model = model
      @encoder = nil
      @method_used = :estimation

      # Try to use tiktoken for accurate counting
      begin
        require "tiktoken_ruby"
        @encoder = Tiktoken.encoding_for_model(@model)
        @method_used = :tiktoken
      rescue LoadError
        # tiktoken_ruby not installed, use estimation
      rescue => e
        # Model not supported by tiktoken, use estimation
        warn "TokenCounter: tiktoken fallback for model '#{@model}': #{e.message}"
      end
    end

    # Count tokens in a string
    def count(text)
      return 0 if text.nil? || text.empty?

      if @encoder
        @encoder.encode(text).length
      else
        estimate(text)
      end
    end

    # Count tokens for an array of texts
    def count_many(texts)
      texts.sum { |t| count(t) }
    end

    # Estimate tokens without tiktoken (fallback)
    # Rule of thumb: ~4 chars per token for English, ~3 for other languages
    def estimate(text)
      return 0 if text.nil? || text.empty?

      # Count words and characters
      words = text.split(/\s+/).length
      chars = text.length

      # Hybrid estimation: average of char-based and word-based
      char_estimate = (chars / 4.0).ceil
      word_estimate = (words * 1.3).ceil

      # Use average, biased toward char estimate
      ((char_estimate * 0.6) + (word_estimate * 0.4)).ceil
    end

    # Estimate total tokens for a translation request
    # (prompt overhead + input text + estimated output)
    def estimate_request(text, prompt_overhead: 100)
      input_tokens = count(text) + prompt_overhead
      # Output is roughly same size as input for translation
      output_tokens = count(text)

      { input: input_tokens, output: output_tokens, total: input_tokens + output_tokens }
    end

    # Check if text fits within a token limit
    def fits?(text, max_tokens:)
      count(text) <= max_tokens
    end

    def accurate?
      @method_used == :tiktoken
    end
  end
end
