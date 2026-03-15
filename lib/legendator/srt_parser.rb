module Legendator
  class SrtParser
    Entry = Struct.new(:id, :timestamp, :text, keyword_init: true)

    SRT_PATTERN = /(\d+)\n(\d{2}:\d{2}:\d{2},\d{3}\s*-->\s*\d{2}:\d{2}:\d{2},\d{3})\n(.*?)(?=\n\n\d+\n|\n*\z)/m

    def initialize(content)
      @raw_content = content
    end

    # Parse SRT file into structured entries
    def parse
      content = cleanup_utf8(@raw_content)
      entries = []

      content.scan(SRT_PATTERN).each do |id_str, timestamp, text|
        entries << Entry.new(
          id: id_str.to_i,
          timestamp: timestamp.strip,
          text: text.strip
        )
      end

      entries
    end

    # Extract only the text lines (no timestamps, no IDs) for AI processing
    # Returns hash: { id => clean_text }
    def extract_texts
      parse.each_with_object({}) do |entry, hash|
        hash[entry.id] = entry.text.gsub("\n", " ")
      end
    end

    # Extract timestamps separately for reconstruction
    # Returns hash: { id => timestamp }
    def extract_timestamps
      parse.each_with_object({}) do |entry, hash|
        hash[entry.id] = entry.timestamp
      end
    end

    # Clean and normalize UTF-8 content
    def cleanup_utf8(content)
      # Work with a dup to avoid frozen string issues
      content = content.dup

      # Force binary encoding first to safely strip BOM bytes
      content.force_encoding("ASCII-8BIT")

      # Remove BOM (Byte Order Mark)
      content.sub!("\xEF\xBB\xBF".b, "")

      # Now try to interpret as UTF-8
      content.force_encoding("UTF-8")

      # If not valid UTF-8, try common subtitle encodings
      unless content.valid_encoding?
        content.force_encoding("ASCII-8BIT")
        %w[UTF-8 ISO-8859-1 Windows-1252 UTF-16LE UTF-16BE].each do |enc|
          begin
            converted = content.encode("UTF-8", enc, invalid: :replace, undef: :replace, replace: "?")
            if converted.valid_encoding?
              content = converted
              break
            end
          rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
            next
          end
        end
      end

      # Final safety: force to UTF-8, replacing invalid chars
      content = content.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")

      # Normalize line endings
      content = content.gsub("\r\n", "\n").gsub("\r", "\n")

      # Remove null bytes and other control characters (keep newlines and tabs)
      content = content.gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")

      # Remove HTML tags commonly found in subtitles (keep <i> for italics)
      content = content.gsub(/<\/?[bB]>/, "")
      content = content.gsub(/<font[^>]*>|<\/font>/i, "")

      content
    end
  end
end
