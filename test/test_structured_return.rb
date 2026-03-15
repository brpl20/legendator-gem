require_relative "test_helper"

class TestStructuredReturn < Minitest::Test
  # These tests verify the structured return parsing and SRT reconstruction
  # WITHOUT calling the actual AI API (miniature/mock tests)

  # ─── SRT Reconstructor ─────────────────────────────

  def test_basic_reconstruction
    translations = { 1 => "O mundo mudou.", 2 => "Eu sinto na agua." }
    timestamps = { 1 => "00:00:01,000 --> 00:00:04,000", 2 => "00:00:04,500 --> 00:00:07,000" }
    originals = { 1 => "The world is changed.", 2 => "I feel it in the water." }

    reconstructor = Legendator::SrtReconstructor.new(translations, timestamps, originals)
    srt = reconstructor.build

    assert_includes srt, "1\n00:00:01,000 --> 00:00:04,000\nO mundo mudou."
    assert_includes srt, "2\n00:00:04,500 --> 00:00:07,000\nEu sinto na agua."
  end

  def test_reconstruction_preserves_order
    translations = { 3 => "Tres", 1 => "Um", 2 => "Dois" }
    timestamps = { 1 => "00:00:01,000 --> 00:00:02,000", 2 => "00:00:03,000 --> 00:00:04,000", 3 => "00:00:05,000 --> 00:00:06,000" }
    originals = { 1 => "One", 2 => "Two", 3 => "Three" }

    reconstructor = Legendator::SrtReconstructor.new(translations, timestamps, originals)
    srt = reconstructor.build

    pos1 = srt.index("Um")
    pos2 = srt.index("Dois")
    pos3 = srt.index("Tres")

    assert pos1 < pos2, "Entry 1 should come before entry 2"
    assert pos2 < pos3, "Entry 2 should come before entry 3"
  end

  def test_reconstruction_falls_back_to_original
    translations = { 1 => "Traduzido" }
    timestamps = { 1 => "00:00:01,000 --> 00:00:02,000", 2 => "00:00:03,000 --> 00:00:04,000" }
    originals = { 1 => "Translated", 2 => "Not translated" }

    reconstructor = Legendator::SrtReconstructor.new(translations, timestamps, originals)
    srt = reconstructor.build

    assert_includes srt, "Traduzido"
    assert_includes srt, "Not translated" # fallback
  end

  def test_reconstruction_handles_br_placeholder
    translations = { 1 => "Primeira linha<br>Segunda linha" }
    timestamps = { 1 => "00:00:01,000 --> 00:00:04,000" }
    originals = { 1 => "First line\nSecond line" }

    reconstructor = Legendator::SrtReconstructor.new(translations, timestamps, originals)
    srt = reconstructor.build

    assert_includes srt, "Primeira linha\nSegunda linha"
    refute_includes srt, "<br>"
  end

  # ─── Coverage Report ───────────────────────────────

  def test_full_coverage
    translations = { 1 => "Um", 2 => "Dois", 3 => "Tres" }
    timestamps = { 1 => "t1", 2 => "t2", 3 => "t3" }
    originals = { 1 => "One", 2 => "Two", 3 => "Three" }

    reconstructor = Legendator::SrtReconstructor.new(translations, timestamps, originals)
    report = reconstructor.coverage_report

    assert_equal 3, report[:total_subtitles]
    assert_equal 3, report[:translated]
    assert_equal 100.0, report[:coverage_percent]
    assert_empty report[:missing_ids]
  end

  def test_partial_coverage
    translations = { 1 => "Um" }
    timestamps = { 1 => "t1", 2 => "t2", 3 => "t3" }
    originals = { 1 => "One", 2 => "Two", 3 => "Three" }

    reconstructor = Legendator::SrtReconstructor.new(translations, timestamps, originals)
    report = reconstructor.coverage_report

    assert_equal 3, report[:total_subtitles]
    assert_equal 1, report[:translated]
    assert_in_delta 33.3, report[:coverage_percent], 0.1
    assert_equal [2, 3], report[:missing_ids]
  end

  # ─── JSON Response Parsing (via AiClient) ──────────

  def test_parse_valid_json_response
    # Simulate what AiClient.parse_translation_response does
    json_content = '{"translations": {"1": "O mundo mudou.", "2": "Eu sinto na agua."}}'
    parsed = JSON.parse(json_content)

    translations = parsed["translations"].each_with_object({}) do |(k, v), hash|
      hash[k.to_i] = v.to_s
    end

    assert_equal({ 1 => "O mundo mudou.", 2 => "Eu sinto na agua." }, translations)
  end

  def test_parse_json_with_markdown_wrapper
    content = "```json\n{\"translations\": {\"1\": \"Ola\", \"2\": \"Mundo\"}}\n```"

    # Extract JSON from markdown
    if content =~ /```(?:json)?\s*(\{.*?\})\s*```/m
      parsed = JSON.parse($1)
      translations = parsed["translations"].each_with_object({}) do |(k, v), hash|
        hash[k.to_i] = v.to_s
      end
      assert_equal({ 1 => "Ola", 2 => "Mundo" }, translations)
    else
      flunk "Should have extracted JSON from markdown"
    end
  end

  def test_parse_pipe_format_fallback
    content = "1|O mundo mudou.\n2|Eu sinto na agua.\n"
    translations = {}

    content.each_line do |line|
      line = line.strip
      next if line.empty? || !line.include?("|")
      id_str, text = line.split("|", 2)
      id = id_str.gsub(/\D/, "").to_i
      next if id.zero?
      translations[id] = text.strip
    end

    assert_equal({ 1 => "O mundo mudou.", 2 => "Eu sinto na agua." }, translations)
  end

  # ─── Full Roundtrip (Parse → Mock Translate → Reconstruct) ─

  def test_full_roundtrip_mock
    # 1. Parse the real SRT
    content = fixture("sample.srt")
    parser = Legendator::SrtParser.new(content)
    texts = parser.extract_texts
    timestamps = parser.extract_timestamps

    # 2. Simulate AI translation (just prepend "[PT] ")
    mock_translations = texts.each_with_object({}) do |(id, text), hash|
      hash[id] = "[PT] #{text}"
    end

    # 3. Reconstruct
    reconstructor = Legendator::SrtReconstructor.new(mock_translations, timestamps, texts)
    srt_output = reconstructor.build
    coverage = reconstructor.coverage_report

    # 4. Verify
    assert_equal 100.0, coverage[:coverage_percent]

    # Verify it's valid SRT (can be re-parsed)
    re_parser = Legendator::SrtParser.new(srt_output)
    re_entries = re_parser.parse
    assert_equal texts.size, re_entries.size

    # All entries should have the mock prefix
    re_entries.each do |entry|
      assert entry.text.start_with?("[PT]"), "Entry #{entry.id} should have mock prefix"
    end
  end

  # ─── Pipeline Dry Run ──────────────────────────────

  def test_pipeline_dry_run
    content = fixture("sample.srt")
    pipeline = Legendator::Pipeline.new(
      provider: :openai,
      model: "gpt-4o-mini",
      target_language: "pt-BR",
      context: "Lord of the Rings"
    )

    # dry_run doesn't call API, just estimates
    info = pipeline.dry_run(content)

    assert info[:subtitles] > 0
    assert info[:chunks][:total_chunks] > 0
    assert info[:estimated_tokens][:total] > 0
    assert_equal :openai, info[:provider]
    assert_equal "gpt-4o-mini", info[:model]
    assert_equal "pt-BR", info[:target_language]
  end
end
