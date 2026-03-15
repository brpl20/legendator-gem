require_relative "test_helper"

class TestFileBreaker < Minitest::Test
  def setup
    @counter = Legendator::TokenCounter.new(model: "gpt-4o-mini")
  end

  # ─── Basic Chunking ────────────────────────────────

  def test_single_chunk_for_small_input
    texts = { 1 => "Hello", 2 => "World" }
    breaker = Legendator::FileBreaker.new(token_counter: @counter, max_tokens_per_chunk: 3000)
    chunks = breaker.break_into_chunks(texts)

    assert_equal 1, chunks.size
    assert_equal 2, chunks.first.entries.size
  end

  def test_multiple_chunks_for_large_input
    # Create 100 subtitles
    texts = (1..100).each_with_object({}) do |i, h|
      h[i] = "This is subtitle number #{i} with some extra text to make it longer and use more tokens."
    end

    breaker = Legendator::FileBreaker.new(token_counter: @counter, max_tokens_per_chunk: 500)
    chunks = breaker.break_into_chunks(texts)

    assert chunks.size > 1, "Should create multiple chunks"

    # Verify all subtitles are accounted for
    all_ids = chunks.flat_map { |c| c.entries.keys }
    assert_equal (1..100).to_a, all_ids.sort
  end

  def test_chunk_respects_token_limit
    texts = (1..50).each_with_object({}) do |i, h|
      h[i] = "This is a test subtitle line number #{i}."
    end

    max = 300
    breaker = Legendator::FileBreaker.new(token_counter: @counter, max_tokens_per_chunk: max, prompt_overhead: 50)
    chunks = breaker.break_into_chunks(texts)

    chunks.each_with_index do |chunk, i|
      # Allow some tolerance since we approximate
      assert chunk.token_count <= (max - 50 + 20),
        "Chunk #{i} has #{chunk.token_count} tokens, exceeds limit #{max - 50}"
    end
  end

  def test_preserves_order
    texts = { 3 => "Third", 1 => "First", 2 => "Second" }
    breaker = Legendator::FileBreaker.new(token_counter: @counter, max_tokens_per_chunk: 3000)
    chunks = breaker.break_into_chunks(texts)

    ids = chunks.flat_map { |c| c.entries.keys }
    assert_equal [1, 2, 3], ids
  end

  # ─── Format Chunk ──────────────────────────────────

  def test_format_chunk
    chunk = Legendator::FileBreaker::Chunk.new(
      entries: { 1 => "Hello world", 2 => "Foo bar" },
      token_count: 10
    )
    breaker = Legendator::FileBreaker.new(token_counter: @counter)
    formatted = breaker.format_chunk(chunk)

    assert_equal "1|Hello world\n2|Foo bar", formatted
  end

  # ─── Summary ───────────────────────────────────────

  def test_summary
    texts = (1..20).each_with_object({}) do |i, h|
      h[i] = "Subtitle #{i}"
    end

    breaker = Legendator::FileBreaker.new(token_counter: @counter, max_tokens_per_chunk: 200)
    chunks = breaker.break_into_chunks(texts)
    summary = breaker.summary(chunks)

    assert_kind_of Hash, summary
    assert_equal 20, summary[:total_entries]
    assert summary[:total_chunks] > 0
    assert summary[:total_tokens] > 0
    assert summary[:max_chunk_tokens] > 0
    assert summary[:avg_chunk_tokens] > 0
  end

  # ─── Edge Cases ────────────────────────────────────

  def test_empty_input
    breaker = Legendator::FileBreaker.new(token_counter: @counter)
    chunks = breaker.break_into_chunks({})
    assert_equal 0, chunks.size
  end

  def test_single_entry
    texts = { 1 => "Hello" }
    breaker = Legendator::FileBreaker.new(token_counter: @counter)
    chunks = breaker.break_into_chunks(texts)

    assert_equal 1, chunks.size
    assert_equal({ 1 => "Hello" }, chunks.first.entries)
  end

  def test_very_long_single_subtitle
    # A subtitle that exceeds the chunk limit by itself
    long_text = "word " * 5000
    texts = { 1 => long_text, 2 => "Short" }

    breaker = Legendator::FileBreaker.new(token_counter: @counter, max_tokens_per_chunk: 500)
    chunks = breaker.break_into_chunks(texts)

    # Should still work: long entry gets its own chunk
    assert chunks.size >= 2, "Long entry should get its own chunk"
    all_ids = chunks.flat_map { |c| c.entries.keys }
    assert_includes all_ids, 1
    assert_includes all_ids, 2
  end

  # ─── Integration with SRT Parser ───────────────────

  def test_chunks_from_real_srt
    content = fixture("sample.srt")
    parser = Legendator::SrtParser.new(content)
    texts = parser.extract_texts

    breaker = Legendator::FileBreaker.new(token_counter: @counter, max_tokens_per_chunk: 200)
    chunks = breaker.break_into_chunks(texts)

    assert chunks.size >= 1
    total_entries = chunks.sum { |c| c.entries.size }
    assert_equal texts.size, total_entries
  end
end
