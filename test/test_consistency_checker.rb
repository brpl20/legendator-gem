require_relative "test_helper"

class TestConsistencyChecker < Minitest::Test
  def setup
    @original_srt = fixture("serie-example.srt")
    @translated_srt = fixture("serie-example-pt-BR.srt")
  end

  # ─── Structural: Count ───────────────────────────

  def test_structural_pass_when_counts_match
    checker = Legendator::ConsistencyChecker.new(
      original_srt: @original_srt,
      translated_srt: @translated_srt,
      target_language: "pt-BR"
    )
    result = checker.check_structure
    assert result.pass?, "Expected structural check to pass, errors: #{result.errors}"
  end

  def test_structural_fail_when_subtitle_missing
    # Remove subtitle 100 from translation
    bad_translated = @translated_srt.sub(/\n100\n[^\n]+\n[^\n]+\n/m, "\n")
    checker = Legendator::ConsistencyChecker.new(
      original_srt: @original_srt,
      translated_srt: bad_translated,
      target_language: "pt-BR"
    )
    result = checker.check_structure
    refute result.pass?
    assert result.errors.any? { |e| e.include?("count") || e.include?("Missing") },
      "Expected count/missing error, got: #{result.errors}"
  end

  # ─── Structural: IDs ────────────────────────────

  def test_structural_fail_when_id_missing
    bad_translated = @translated_srt.sub(/^7\n/, "77\n")
    checker = Legendator::ConsistencyChecker.new(
      original_srt: @original_srt,
      translated_srt: bad_translated,
      target_language: "pt-BR"
    )
    result = checker.check_structure
    refute result.pass?
    assert result.errors.any? { |e| e.include?("7") },
      "Expected error mentioning ID 7, got: #{result.errors}"
  end

  # ─── Structural: Timestamps ─────────────────────

  def test_structural_fail_when_timestamp_differs
    bad_translated = @translated_srt.sub("00:00:02,810 --> 00:00:06,002", "00:00:02,810 --> 00:00:99,000")
    checker = Legendator::ConsistencyChecker.new(
      original_srt: @original_srt,
      translated_srt: bad_translated,
      target_language: "pt-BR"
    )
    result = checker.check_structure
    refute result.pass?
    assert result.errors.any? { |e| e.downcase.include?("timestamp") },
      "Expected timestamp error, got: #{result.errors}"
  end

  # ─── Result struct ──────────────────────────────

  def test_result_has_expected_fields
    checker = Legendator::ConsistencyChecker.new(
      original_srt: @original_srt,
      translated_srt: @translated_srt,
      target_language: "pt-BR"
    )
    result = checker.check_structure
    assert_respond_to result, :pass?
    assert_respond_to result, :errors
    assert_respond_to result, :sample_details
  end
end

class TestConsistencyCheckerTranslation < Minitest::Test
  def setup
    @original_srt = fixture("serie-example.srt")
    @translated_srt = fixture("serie-example-pt-BR.srt")
  end

  def test_pick_sample_ids_returns_requested_count
    checker = Legendator::ConsistencyChecker.new(
      original_srt: @original_srt,
      translated_srt: @translated_srt,
      target_language: "pt-BR"
    )

    orig_texts = Legendator::SrtParser.new(@original_srt).extract_texts
    sample_ids = checker.send(:pick_sample_ids, orig_texts.keys, 5)
    assert_equal 5, sample_ids.size
    assert sample_ids.all? { |id| orig_texts.key?(id) }
  end

  def test_pick_sample_ids_caps_at_available
    checker = Legendator::ConsistencyChecker.new(
      original_srt: "1\n00:00:01,000 --> 00:00:02,000\nHi\n\n2\n00:00:03,000 --> 00:00:04,000\nBye\n\n",
      translated_srt: "1\n00:00:01,000 --> 00:00:02,000\nOi\n\n2\n00:00:03,000 --> 00:00:04,000\nTchau\n\n",
      target_language: "pt-BR"
    )
    sample = checker.send(:pick_sample_ids, [1, 2], 5)
    assert_equal 2, sample.size
  end

  def test_build_verification_prompt
    checker = Legendator::ConsistencyChecker.new(
      original_srt: @original_srt,
      translated_srt: @translated_srt,
      target_language: "pt-BR"
    )

    pairs = {
      1 => { original: "The world is changed.", translated: "O mundo mudou." },
      2 => { original: "I feel it in the water.", translated: "Eu sinto na agua." }
    }

    prompt = checker.send(:build_verification_prompt, pairs)
    assert_includes prompt, "pt-BR"
    assert_includes prompt, "The world is changed."
    assert_includes prompt, "O mundo mudou."
  end

  def test_parse_verification_response_all_pass
    checker = Legendator::ConsistencyChecker.new(
      original_srt: @original_srt,
      translated_srt: @translated_srt,
      target_language: "pt-BR"
    )

    json_response = '{"1": true, "2": true, "3": true}'
    result = checker.send(:parse_verification_response, json_response)
    assert_equal({ 1 => true, 2 => true, 3 => true }, result)
  end

  def test_parse_verification_response_some_fail
    checker = Legendator::ConsistencyChecker.new(
      original_srt: @original_srt,
      translated_srt: @translated_srt,
      target_language: "pt-BR"
    )

    json_response = '{"1": true, "2": false, "3": true}'
    result = checker.send(:parse_verification_response, json_response)
    assert_equal false, result[2]
  end

  def test_run_skips_ai_check_when_no_provider
    checker = Legendator::ConsistencyChecker.new(
      original_srt: @original_srt,
      translated_srt: @translated_srt,
      target_language: "pt-BR"
    )
    result = checker.run
    assert result.pass?
    assert_empty result.sample_details
  end
end
