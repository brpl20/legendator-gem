require_relative "test_helper"

# Tests using real-world SRT files from actual translation jobs.
# Covers structural verification (IDs, timestamps, count) against
# real input/output pairs and simulates common failure modes.
class TestConsistencyCheckerRealSrts < Minitest::Test
  def setup
    @serie_original = fixture("serie-example.srt")
    @serie_translated = fixture("serie-example-pt-BR.srt")
    @movie_original = fixture("movie-example.srt")
    @movie_translated = fixture("movie-example-pt-BR.srt")
    @big_original = fixture("movie-big-example.srt")
    @big_translated = fixture("movie-big-example-pt-BR.srt")
  end

  # ─── Passing: Real translation pairs ──────────────

  def test_serie_passes_structural_check
    result = check_structure(@serie_original, @serie_translated)
    assert result.pass?, "Expected pass, errors: #{result.errors}"
  end

  def test_movie_passes_structural_check
    result = check_structure(@movie_original, @movie_translated)
    assert result.pass?, "Expected pass, errors: #{result.errors}"
  end

  def test_big_movie_passes_structural_check
    result = check_structure(@big_original, @big_translated)
    assert result.pass?, "Expected pass, errors: #{result.errors}"
  end

  def test_run_passes_without_provider
    checker = Legendator::ConsistencyChecker.new(
      original_srt: @serie_original,
      translated_srt: @serie_translated,
      target_language: "pt-BR"
    )
    result = checker.run
    assert result.pass?
    assert_empty result.sample_details
  end

  # ─── Passing: Subtitle counts match ───────────────

  def test_serie_subtitle_counts_match
    assert_equal parse_texts(@serie_original).size, parse_texts(@serie_translated).size
  end

  def test_movie_subtitle_counts_match
    assert_equal parse_texts(@movie_original).size, parse_texts(@movie_translated).size
  end

  def test_big_movie_subtitle_counts_match
    assert_equal parse_texts(@big_original).size, parse_texts(@big_translated).size
  end

  # ─── Passing: Timestamps preserved ────────────────

  def test_serie_timestamps_preserved
    assert_timestamps_match(@serie_original, @serie_translated)
  end

  def test_movie_timestamps_preserved
    assert_timestamps_match(@movie_original, @movie_translated)
  end

  def test_big_movie_timestamps_preserved
    assert_timestamps_match(@big_original, @big_translated)
  end

  # ─── Failing: Missing subtitles (chunk loss) ──────

  def test_fail_when_subtitles_missing_from_middle
    bad = remove_subtitle_range(@serie_translated, 100, 105)
    result = check_structure(@serie_original, bad)

    refute result.pass?
    assert result.errors.any? { |e| e.include?("count") },
      "Expected count mismatch, got: #{result.errors}"
    assert result.errors.any? { |e| e.include?("Missing") },
      "Expected missing IDs error, got: #{result.errors}"
  end

  def test_fail_when_subtitles_truncated_at_end
    truncated = keep_first_n_subtitles(@serie_translated, 200)
    result = check_structure(@serie_original, truncated)

    refute result.pass?
    assert result.errors.any? { |e| e.include?("count") },
      "Expected count mismatch, got: #{result.errors}"
  end

  def test_fail_reports_exact_missing_id
    bad = remove_subtitle_range(@serie_translated, 250, 250)
    result = check_structure(@serie_original, bad)

    refute result.pass?
    assert result.errors.any? { |e| e.include?("250") },
      "Expected error mentioning ID 250, got: #{result.errors}"
  end

  # ─── Failing: Extra subtitles (AI hallucination) ──

  def test_fail_when_extra_subtitle_appended
    extra = @serie_translated + "\n465\n00:22:00,000 --> 00:22:03,000\nLegenda extra.\n\n"
    result = check_structure(@serie_original, extra)

    refute result.pass?
    assert result.errors.any? { |e| e.include?("count") || e.include?("Extra") },
      "Expected count/extra error, got: #{result.errors}"
  end

  # ─── Failing: ID renumbering (bad reconstruction) ─

  def test_fail_when_id_renumbered
    bad = @serie_translated.sub(/^50\n/, "9999\n")
    result = check_structure(@serie_original, bad)

    refute result.pass?
    assert result.errors.any? { |e| e.include?("50") || e.include?("9999") },
      "Expected error about ID 50 or 9999, got: #{result.errors}"
  end

  def test_fail_when_multiple_ids_shifted
    bad = @serie_translated.dup
    (300..305).each { |id| bad.sub!(/^#{id}\n/, "#{id + 1000}\n") }
    result = check_structure(@serie_original, bad)

    refute result.pass?
    assert result.errors.any? { |e| e.include?("Missing") },
      "Expected missing IDs error, got: #{result.errors}"
  end

  # ─── Failing: Timestamp drift ─────────────────────

  def test_fail_when_single_timestamp_altered
    bad = @serie_translated.sub(
      "00:00:06,002 --> 00:00:08,263",
      "00:00:06,002 --> 00:00:09,000"
    )
    result = check_structure(@serie_original, bad)

    refute result.pass?
    assert result.errors.any? { |e| e.downcase.include?("timestamp") },
      "Expected timestamp error, got: #{result.errors}"
  end

  def test_fail_when_many_timestamps_altered
    bad = @serie_translated.dup
    bad.sub!("00:00:08,263 --> 00:00:10,551", "00:00:08,263 --> 00:00:10,999")
    bad.sub!("00:03:40,558 --> 00:03:42,041", "00:03:40,558 --> 00:03:42,999")
    bad.sub!("00:18:21,164 --> 00:18:22,373", "00:18:21,164 --> 00:18:22,999")
    result = check_structure(@serie_original, bad)

    refute result.pass?
    timestamp_errors = result.errors.select { |e| e.downcase.include?("timestamp") }
    assert_operator timestamp_errors.size, :>=, 3,
      "Expected at least 3 timestamp errors, got: #{timestamp_errors}"
  end

  # ─── Failing: Empty/broken output ─────────────────

  def test_fail_when_translation_is_empty
    result = check_structure(@serie_original, "")
    refute result.pass?
  end

  def test_fail_when_translation_is_garbage
    result = check_structure(@serie_original, "not a valid srt file\njust some text\n")
    refute result.pass?
  end

  # ─── Failing: Movie-sized failures ────────────────

  def test_movie_fail_when_chunk_lost
    bad = remove_subtitle_range(@movie_translated, 500, 520)
    result = check_structure(@movie_original, bad)

    refute result.pass?
    missing_error = result.errors.find { |e| e.include?("Missing") }
    assert missing_error, "Expected missing IDs error, got: #{result.errors}"
  end

  def test_movie_fail_when_first_subtitle_missing
    bad = remove_subtitle_range(@movie_translated, 1, 1)
    result = check_structure(@movie_original, bad)

    refute result.pass?
    assert result.errors.any? { |e| e.include?("1") },
      "Expected error about ID 1, got: #{result.errors}"
  end

  def test_movie_fail_when_last_subtitle_missing
    last_id = parse_texts(@movie_original).keys.max
    bad = remove_subtitle_range(@movie_translated, last_id, last_id)
    result = check_structure(@movie_original, bad)

    refute result.pass?
    assert result.errors.any? { |e| e.include?(last_id.to_s) },
      "Expected error about ID #{last_id}, got: #{result.errors}"
  end

  # ─── Failing: Big movie failures ──────────────────

  def test_big_movie_fail_when_large_chunk_lost
    bad = remove_subtitle_range(@big_translated, 1500, 1550)
    result = check_structure(@big_original, bad)

    refute result.pass?
    assert result.errors.any? { |e| e.include?("count") },
      "Expected count mismatch, got: #{result.errors}"
  end

  # ─── Failing: Wrong file comparison ───────────────

  def test_fail_when_different_files_compared
    result = check_structure(@serie_original, @movie_translated)

    refute result.pass?
    assert result.errors.any? { |e| e.include?("count") },
      "Expected count mismatch, got: #{result.errors}"
  end

  # ─── Result struct ────────────────────────────────

  def test_result_errors_empty_on_pass
    result = check_structure(@serie_original, @serie_translated)
    assert_instance_of Array, result.errors
    assert_empty result.errors
  end

  def test_result_errors_populated_on_fail
    bad = remove_subtitle_range(@serie_translated, 100, 100)
    result = check_structure(@serie_original, bad)
    assert_instance_of Array, result.errors
    refute_empty result.errors
  end

  private

  def check_structure(original, translated)
    Legendator::ConsistencyChecker.new(
      original_srt: original,
      translated_srt: translated,
      target_language: "pt-BR"
    ).check_structure
  end

  def parse_texts(srt)
    Legendator::SrtParser.new(srt).extract_texts
  end

  def parse_timestamps(srt)
    Legendator::SrtParser.new(srt).extract_timestamps
  end

  def assert_timestamps_match(original, translated)
    orig_ts = parse_timestamps(original)
    trans_ts = parse_timestamps(translated)
    orig_ts.each do |id, ts|
      assert_equal ts, trans_ts[id], "Timestamp mismatch for ID #{id}"
    end
  end

  def remove_subtitle_range(srt, from_id, to_id)
    lines = srt.split("\n")
    result = []
    skip = false

    lines.each_with_index do |line, i|
      if line.strip.match?(/\A\d+\z/)
        id = line.strip.to_i
        if id >= from_id && id <= to_id
          next_line = lines[i + 1]
          if next_line && next_line.include?("-->")
            skip = true
            next
          end
        end
      end

      if skip
        if line.strip.empty?
          skip = false
        end
        next
      end

      result << line
    end

    result.join("\n")
  end

  def keep_first_n_subtitles(srt, n)
    entries = Legendator::SrtParser.new(srt).send(:parse)
    entries.first(n).map do |entry|
      "#{entry.id}\n#{entry.timestamp}\n#{entry.text}\n"
    end.join("\n")
  end
end
