require_relative "test_helper"

class TestSrtParser < Minitest::Test
  # ─── UTF-8 Cleanup Tests ───────────────────────────

  def test_parse_clean_srt
    content = fixture("sample.srt")
    parser = Legendator::SrtParser.new(content)
    entries = parser.parse

    assert entries.size >= 10, "Should parse at least 10 entries, got #{entries.size}"
    assert_equal 1, entries.first.id
    assert_equal "The world is changed.", entries.first.text
  end

  def test_extract_texts_returns_hash
    content = fixture("sample.srt")
    parser = Legendator::SrtParser.new(content)
    texts = parser.extract_texts

    assert_kind_of Hash, texts
    assert_equal "The world is changed.", texts[1]
    refute_nil texts[14] # last entry
  end

  def test_extract_timestamps
    content = fixture("sample.srt")
    parser = Legendator::SrtParser.new(content)
    timestamps = parser.extract_timestamps

    assert_kind_of Hash, timestamps
    assert_match(/\d{2}:\d{2}:\d{2},\d{3}/, timestamps[1])
  end

  def test_multiline_subtitles_joined
    content = fixture("sample.srt")
    parser = Legendator::SrtParser.new(content)
    texts = parser.extract_texts

    # Entry 5 has two lines in the SRT
    text5 = texts[5]
    refute_nil text5
    # Should be joined with space (not newline)
    assert text5.include?("Much that once was"), "Should contain first line"
  end

  # ─── UTF-8 BOM Handling ────────────────────────────

  def test_handles_utf8_bom
    # UTF-8 BOM: EF BB BF
    bom_content = "\xEF\xBB\xBF1\n00:00:01,000 --> 00:00:04,000\nHello world.\n\n"
    parser = Legendator::SrtParser.new(bom_content)
    entries = parser.parse

    assert_equal 1, entries.size
    assert_equal "Hello world.", entries.first.text
  end

  def test_handles_windows_line_endings
    content = "1\r\n00:00:01,000 --> 00:00:04,000\r\nHello world.\r\n\r\n"
    parser = Legendator::SrtParser.new(content)
    entries = parser.parse

    assert_equal 1, entries.size
    assert_equal "Hello world.", entries.first.text
  end

  def test_strips_bold_but_keeps_italic
    content = "1\n00:00:01,000 --> 00:00:04,000\n<i>Hello</i> <b>world</b>.\n\n"
    parser = Legendator::SrtParser.new(content)
    entries = parser.parse

    assert_equal 1, entries.size
    assert_equal "<i>Hello</i> world.", entries.first.text
  end

  def test_strips_font_tags
    content = "1\n00:00:01,000 --> 00:00:04,000\n<font color=\"#FFFFFF\">Hello world.</font>\n\n"
    parser = Legendator::SrtParser.new(content)
    entries = parser.parse

    assert_equal 1, entries.size
    assert_equal "Hello world.", entries.first.text
  end

  def test_handles_latin1_encoding
    # Simulating Latin-1 content with accented chars
    content = "1\n00:00:01,000 --> 00:00:04,000\nCaf\u00E9 com leite.\n\n"
    parser = Legendator::SrtParser.new(content)
    entries = parser.parse

    assert_equal 1, entries.size
    assert_includes entries.first.text, "Caf"
  end

  def test_removes_null_bytes
    content = "1\n00:00:01,000 --> 00:00:04,000\nHello\x00 world.\n\n"
    parser = Legendator::SrtParser.new(content)
    cleaned = parser.cleanup_utf8(content)

    refute_includes cleaned, "\x00"
  end

  def test_handles_empty_content
    parser = Legendator::SrtParser.new("")
    entries = parser.parse

    assert_equal 0, entries.size
  end

  def test_handles_garbage_content
    parser = Legendator::SrtParser.new("this is not an srt file at all")
    entries = parser.parse

    assert_equal 0, entries.size
  end
end
