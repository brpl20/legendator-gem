require_relative "test_helper"

class TestTokenCounter < Minitest::Test
  def setup
    @counter = Legendator::TokenCounter.new(model: "gpt-4o-mini")
  end

  # ─── Basic Counting ────────────────────────────────

  def test_count_empty_string
    assert_equal 0, @counter.count("")
    assert_equal 0, @counter.count(nil)
  end

  def test_count_simple_text
    tokens = @counter.count("Hello, world!")
    assert tokens > 0, "Should count at least 1 token"
    assert tokens < 10, "Simple text should be under 10 tokens, got #{tokens}"
  end

  def test_count_longer_text
    text = "The world is changed. I feel it in the water. I feel it in the earth. I smell it in the air."
    tokens = @counter.count(text)
    assert tokens > 10, "Longer text should have >10 tokens"
    assert tokens < 50, "Should not overestimate, got #{tokens}"
  end

  # ─── Estimation Fallback ───────────────────────────

  def test_estimate_returns_positive
    text = "Hello world"
    estimate = @counter.estimate(text)
    assert estimate > 0
  end

  def test_estimate_empty
    assert_equal 0, @counter.estimate("")
    assert_equal 0, @counter.estimate(nil)
  end

  def test_estimate_proportional
    short = @counter.estimate("Hello")
    long = @counter.estimate("Hello world, this is a longer sentence with many more words.")
    assert long > short, "Longer text should estimate more tokens"
  end

  # ─── Count Many ────────────────────────────────────

  def test_count_many
    texts = ["Hello", "World", "Foo bar baz"]
    total = @counter.count_many(texts)
    individual = texts.sum { |t| @counter.count(t) }
    assert_equal individual, total
  end

  # ─── Request Estimation ────────────────────────────

  def test_estimate_request
    text = "The world is changed."
    result = @counter.estimate_request(text)

    assert_kind_of Hash, result
    assert result[:input] > 0
    assert result[:output] > 0
    assert_equal result[:input] + result[:output], result[:total]
    # Input should include overhead
    assert result[:input] > result[:output], "Input should include prompt overhead"
  end

  # ─── Fits Check ────────────────────────────────────

  def test_fits_short_text
    assert @counter.fits?("Hello", max_tokens: 100)
  end

  def test_does_not_fit_with_tiny_limit
    refute @counter.fits?("Hello world, this is a long text", max_tokens: 1)
  end

  # ─── Method Reporting ──────────────────────────────

  def test_reports_method
    assert [:tiktoken, :estimation].include?(@counter.method_used)
  end

  def test_accurate_flag
    if @counter.method_used == :tiktoken
      assert @counter.accurate?
    else
      refute @counter.accurate?
    end
  end

  # ─── Subtitle-Specific Tests ───────────────────────

  def test_count_formatted_subtitle_line
    line = "1|The world is changed."
    tokens = @counter.count(line)
    assert tokens > 0
    assert tokens < 20
  end

  def test_count_batch_of_subtitles
    batch = (1..10).map { |i| "#{i}|This is subtitle number #{i}." }.join("\n")
    tokens = @counter.count(batch)
    assert tokens > 30, "10 subtitles should use >30 tokens"
    assert tokens < 200, "10 short subtitles should not exceed 200 tokens, got #{tokens}"
  end
end
