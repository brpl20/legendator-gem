require_relative "test_helper"

class TestConsistencyChecker < Minitest::Test
  def setup
    @original_srt = fixture("sample.srt")
    @translated_srt = fixture("sample_pt-BR.srt")
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
    bad_translated = @translated_srt.sub(/14\n00:01:03.*?Um anel para governar todos eles\.\n*/m, "")
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
    bad_translated = @translated_srt.sub("00:00:01,000 --> 00:00:04,000", "00:00:01,000 --> 00:00:99,000")
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
