module Legendator
  class FileBreaker
    # Each chunk is a hash: { subtitle_id => text }
    Chunk = Struct.new(:entries, :token_count, keyword_init: true)

    def initialize(token_counter:, max_tokens_per_chunk: Config.max_tokens_per_chunk, prompt_overhead: Config.prompt_overhead)
      @counter = token_counter
      @max_tokens = max_tokens_per_chunk
      @prompt_overhead = prompt_overhead
      # Available tokens = max - overhead for prompt + response format
      @available_tokens = @max_tokens - @prompt_overhead
    end

    # Takes a hash { id => text } and breaks into chunks
    # Each chunk fits within the token limit
    def break_into_chunks(texts)
      chunks = []
      current_entries = {}
      current_tokens = 0

      texts.keys.sort.each do |id|
        text = texts[id]
        # Format as it will be sent: "ID|text"
        line = "#{id}|#{text}"
        line_tokens = @counter.count(line)

        # If single entry exceeds limit, it goes alone (we can't split a subtitle)
        if line_tokens > @available_tokens
          # Flush current chunk first
          if current_entries.any?
            chunks << Chunk.new(entries: current_entries.dup, token_count: current_tokens)
            current_entries = {}
            current_tokens = 0
          end
          chunks << Chunk.new(entries: { id => text }, token_count: line_tokens)
          next
        end

        # Would adding this entry exceed the limit?
        if current_entries.any? && (current_tokens + line_tokens) > @available_tokens
          chunks << Chunk.new(entries: current_entries.dup, token_count: current_tokens)
          current_entries = {}
          current_tokens = 0
        end

        current_entries[id] = text
        current_tokens += line_tokens
      end

      # Don't forget the last chunk
      if current_entries.any?
        chunks << Chunk.new(entries: current_entries.dup, token_count: current_tokens)
      end

      chunks
    end

    # Format a chunk as text to send to the AI
    def format_chunk(chunk)
      chunk.entries.keys.sort.map { |id| "#{id}|#{chunk.entries[id]}" }.join("\n")
    end

    # Summary info about the chunking
    def summary(chunks)
      {
        total_chunks: chunks.size,
        total_entries: chunks.sum { |c| c.entries.size },
        total_tokens: chunks.sum(&:token_count),
        max_chunk_tokens: chunks.map(&:token_count).max,
        avg_chunk_tokens: chunks.empty? ? 0 : (chunks.sum(&:token_count) / chunks.size.to_f).round
      }
    end
  end
end
