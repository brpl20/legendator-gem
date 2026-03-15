module Legendator
  class SrtReconstructor
    def initialize(translations, timestamps, original_texts)
      @translations = translations   # { id => translated_text }
      @timestamps = timestamps         # { id => "00:00:01,000 --> 00:00:04,000" }
      @original_texts = original_texts # { id => original_text } (fallback)
    end

    # Build the final SRT content
    def build
      blocks = []

      @timestamps.keys.sort.each do |id|
        timestamp = @timestamps[id]
        text = @translations[id] || @original_texts[id] || "[TRANSLATION MISSING]"

        # Replace <br> placeholder back to real newlines
        text = text.gsub("<br>", "\n")

        blocks << "#{id}\n#{timestamp}\n#{text}"
      end

      blocks.join("\n\n") + "\n"
    end

    # Report on translation coverage
    def coverage_report
      total = @timestamps.keys.size
      translated = @translations.keys.count { |id| @timestamps.key?(id) }
      missing = @timestamps.keys - @translations.keys
      extra = @translations.keys - @timestamps.keys

      {
        total_subtitles: total,
        translated: translated,
        missing_ids: missing.sort,
        extra_ids: extra.sort,
        coverage_percent: total.zero? ? 0 : ((translated.to_f / total) * 100).round(1)
      }
    end
  end
end
