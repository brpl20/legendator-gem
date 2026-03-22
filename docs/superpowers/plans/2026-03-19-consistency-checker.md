# Consistency Checker Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `ConsistencyChecker` to the legendator gem that verifies structural integrity and translation presence after SRT translation, returning a result the Rails app uses to mark failures.

**Architecture:** New `ConsistencyChecker` class uses existing `SrtParser` to compare original and translated SRTs (IDs, timestamps, count), then uses `AiClient` to sample 5 random subtitles and verify they were actually translated. Integrates into `Pipeline#run` as step 5/6.

**Tech Stack:** Ruby, Minitest, existing Legendator gem classes (`SrtParser`, `AiClient`)

---

## Chunk 1: ConsistencyChecker — Structural Verification

### Task 1: Test fixture — translated SRT

**Files:**
- Create: `test/fixtures/sample_pt-BR.srt`

- [ ] **Step 1: Create the translated fixture file**

This is a pre-translated version of `test/fixtures/sample.srt` with identical IDs and timestamps but Portuguese text:

```srt
1
00:00:01,000 --> 00:00:04,000
O mundo mudou.

2
00:00:04,500 --> 00:00:07,000
Eu sinto na agua.

3
00:00:07,500 --> 00:00:10,000
Eu sinto na terra.

4
00:00:10,500 --> 00:00:13,000
Eu sinto no ar.

5
00:00:14,000 --> 00:00:18,000
Muito do que existia se perdeu,
pois ninguem vive que se lembre.

6
00:00:20,000 --> 00:00:25,000
Comecou com a forja
dos Grandes Aneis.

7
00:00:26,000 --> 00:00:30,000
Tres foram dados aos Elfos,
imortais, os mais sabios e belos de todos os seres.

8
00:00:31,000 --> 00:00:35,000
Sete para os Senhores dos Anoes,
grandes mineradores e artesaos dos saloes da montanha.

9
00:00:36,000 --> 00:00:40,000
E nove, nove aneis foram dados a raca dos Homens,
que acima de tudo desejam o poder.

10
00:00:41,000 --> 00:00:45,000
Pois dentro destes aneis estava a forca
e a vontade de governar cada raca.

11
00:00:46,000 --> 00:00:50,000
Mas todos eles foram enganados,
pois outro anel foi feito.

12
00:00:51,000 --> 00:00:56,000
Na terra de Mordor, nas chamas da Montanha da Perdicao,
o Senhor das Trevas Sauron forjou um anel mestre.

13
00:00:57,000 --> 00:01:02,000
E neste anel ele despejou sua crueldade,
sua malicia e sua vontade de dominar toda a vida.

14
00:01:03,000 --> 00:01:06,000
Um anel para governar todos eles.
```

- [ ] **Step 2: Commit**

```bash
git add test/fixtures/sample_pt-BR.srt
git commit -m "test: add Portuguese translated SRT fixture for consistency checker tests"
```

---

### Task 2: ConsistencyChecker — structural checks with tests

**Files:**
- Create: `lib/legendator/consistency_checker.rb`
- Create: `test/test_consistency_checker.rb`

- [ ] **Step 1: Write failing tests for structural verification**

Create `test/test_consistency_checker.rb`:

```ruby
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
    # Remove subtitle 14 from translated
    bad_translated = @translated_srt.sub(/14\n00:01:03.*?Um anel para governar todos eles\.\n*/m, "")
    checker = Legendator::ConsistencyChecker.new(
      original_srt: @original_srt,
      translated_srt: bad_translated,
      target_language: "pt-BR"
    )
    result = checker.check_structure
    refute result.pass?
    assert result.errors.any? { |e| e.include?("count") || e.include?("missing") },
      "Expected count/missing error, got: #{result.errors}"
  end

  # ─── Structural: IDs ────────────────────────────

  def test_structural_fail_when_id_missing
    # Replace ID 7 with ID 77
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
    assert result.errors.any? { |e| e.include?("timestamp") || e.include?("Timestamp") },
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/brpl20/code/legendator-gem && ruby -Ilib -Itest test/test_consistency_checker.rb`
Expected: FAIL — `ConsistencyChecker` class not found

- [ ] **Step 3: Implement ConsistencyChecker with structural checks**

Create `lib/legendator/consistency_checker.rb`:

```ruby
module Legendator
  class ConsistencyChecker
    Result = Struct.new(:pass, :errors, :sample_details, keyword_init: true) do
      alias_method :pass?, :pass
    end

    def initialize(original_srt:, translated_srt:, target_language:, provider: nil, model: nil, api_key: nil)
      @original_srt = original_srt
      @translated_srt = translated_srt
      @target_language = target_language
      @provider = provider
      @model = model
      @api_key = api_key
    end

    def run
      result = check_structure
      return result unless result.pass?

      check_translation(result)
    end

    def check_structure
      original = SrtParser.new(@original_srt)
      translated = SrtParser.new(@translated_srt)

      orig_texts = original.extract_texts
      orig_timestamps = original.extract_timestamps
      trans_texts = translated.extract_texts
      trans_timestamps = translated.extract_timestamps

      errors = []

      # Check count
      if orig_texts.size != trans_texts.size
        errors << "Subtitle count mismatch: original has #{orig_texts.size}, translated has #{trans_texts.size}"
      end

      # Check missing IDs
      missing_ids = orig_texts.keys - trans_texts.keys
      if missing_ids.any?
        errors << "Missing subtitle IDs in translation: #{missing_ids.sort.join(', ')}"
      end

      # Check extra IDs
      extra_ids = trans_texts.keys - orig_texts.keys
      if extra_ids.any?
        errors << "Extra subtitle IDs in translation: #{extra_ids.sort.join(', ')}"
      end

      # Check timestamps match for common IDs
      common_ids = orig_texts.keys & trans_texts.keys
      common_ids.each do |id|
        if orig_timestamps[id] != trans_timestamps[id]
          errors << "Timestamp mismatch for ID #{id}: original '#{orig_timestamps[id]}' vs translated '#{trans_timestamps[id]}'"
        end
      end

      Result.new(pass: errors.empty?, errors: errors, sample_details: [])
    end

    private

    def check_translation(structural_result)
      # Will be implemented in Task 3
      structural_result
    end
  end
end
```

- [ ] **Step 4: Add require to legendator.rb**

In `lib/legendator.rb`, add after the `require_relative "legendator/pipeline"` line:

```ruby
require_relative "legendator/consistency_checker"
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/brpl20/code/legendator-gem && ruby -Ilib -Itest test/test_consistency_checker.rb`
Expected: All 5 tests PASS

- [ ] **Step 6: Commit**

```bash
cd /Users/brpl20/code/legendator-gem
git add lib/legendator/consistency_checker.rb test/test_consistency_checker.rb lib/legendator.rb
git commit -m "feat: add ConsistencyChecker with structural verification (IDs, timestamps, count)"
```

---

## Chunk 2: ConsistencyChecker — AI Translation Verification

### Task 3: AI translation check with tests

**Files:**
- Modify: `lib/legendator/consistency_checker.rb` — implement `check_translation`
- Modify: `test/test_consistency_checker.rb` — add AI check tests

- [ ] **Step 1: Write failing tests for AI translation verification**

Append to `test/test_consistency_checker.rb`:

```ruby
class TestConsistencyCheckerTranslation < Minitest::Test
  def setup
    @original_srt = fixture("sample.srt")
    @translated_srt = fixture("sample_pt-BR.srt")
  end

  def test_check_translation_detects_untranslated_subtitle
    # Build a "translated" SRT that keeps original English for ID 3
    bad_translated = @translated_srt.sub("Eu sinto na terra.", "I feel it in the earth.")
    checker = Legendator::ConsistencyChecker.new(
      original_srt: @original_srt,
      translated_srt: bad_translated,
      target_language: "pt-BR"
    )

    # Stub the AI response to say ID 3 was not translated
    result = checker.check_structure
    assert result.pass?, "Structural check should pass"

    # Test the prompt building
    orig_texts = Legendator::SrtParser.new(@original_srt).extract_texts
    trans_texts = Legendator::SrtParser.new(bad_translated).extract_texts

    # Verify sample_ids picks from available IDs
    sample_ids = checker.send(:pick_sample_ids, orig_texts.keys, 5)
    assert_equal 5, sample_ids.size
    assert sample_ids.all? { |id| orig_texts.key?(id) }
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

  def test_pick_sample_ids_caps_at_available
    checker = Legendator::ConsistencyChecker.new(
      original_srt: "1\n00:00:01,000 --> 00:00:02,000\nHi\n\n2\n00:00:03,000 --> 00:00:04,000\nBye\n\n",
      translated_srt: "1\n00:00:01,000 --> 00:00:02,000\nOi\n\n2\n00:00:03,000 --> 00:00:04,000\nTchau\n\n",
      target_language: "pt-BR"
    )
    sample = checker.send(:pick_sample_ids, [1, 2], 5)
    assert_equal 2, sample.size
  end
end
```

- [ ] **Step 2: Run tests to verify new tests fail**

Run: `cd /Users/brpl20/code/legendator-gem && ruby -Ilib -Itest test/test_consistency_checker.rb`
Expected: New tests FAIL — `pick_sample_ids`, `build_verification_prompt`, `parse_verification_response` not defined

- [ ] **Step 3: Implement AI translation verification methods**

In `lib/legendator/consistency_checker.rb`, replace the private `check_translation` method and add helpers:

```ruby
    SAMPLE_SIZE = 5

    private

    def check_translation(structural_result)
      return structural_result unless @provider && @model

      original_texts = SrtParser.new(@original_srt).extract_texts
      translated_texts = SrtParser.new(@translated_srt).extract_texts

      sample_ids = pick_sample_ids(original_texts.keys, SAMPLE_SIZE)

      pairs = sample_ids.each_with_object({}) do |id, hash|
        hash[id] = {
          original: original_texts[id],
          translated: translated_texts[id]
        }
      end

      client = AiClient.new(provider: @provider, model: @model, api_key: @api_key)
      prompt = build_verification_prompt(pairs)

      response = client.chat(
        system_prompt: "You are a translation verification assistant. Answer ONLY with valid JSON.",
        user_prompt: prompt,
        temperature: 0
      )

      verdicts = parse_verification_response(response.content)

      errors = structural_result.errors.dup
      sample_details = []

      pairs.each do |id, pair|
        passed = verdicts[id] != false
        sample_details << { id: id, original: pair[:original], translated: pair[:translated], passed: passed }
        unless passed
          errors << "Subtitle ID #{id} was not translated"
        end
      end

      Result.new(pass: errors.empty?, errors: errors, sample_details: sample_details)
    end

    def pick_sample_ids(all_ids, count)
      all_ids.sample([count, all_ids.size].min)
    end

    def build_verification_prompt(pairs)
      pairs_json = pairs.each_with_object({}) do |(id, pair), hash|
        hash[id.to_s] = { "original" => pair[:original], "translated" => pair[:translated] }
      end

      <<~PROMPT
        For each pair below, answer ONLY with a JSON object.
        Each pair has an original subtitle and a supposed translation to #{@target_language}.
        Answer whether each one was actually translated (not left in the original language).

        #{JSON.generate(pairs_json)}

        Return format: {"1": true, "2": false, ...}
        Return ONLY the JSON, nothing else.
      PROMPT
    end

    def parse_verification_response(content)
      parsed = begin
        JSON.parse(content)
      rescue JSON::ParserError
        {}
      end

      parsed.each_with_object({}) do |(k, v), hash|
        hash[k.to_i] = v
      end
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/brpl20/code/legendator-gem && ruby -Ilib -Itest test/test_consistency_checker.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/brpl20/code/legendator-gem
git add lib/legendator/consistency_checker.rb test/test_consistency_checker.rb
git commit -m "feat: add AI translation verification to ConsistencyChecker (5 random samples)"
```

---

## Chunk 3: Pipeline Integration + Rails Integration

### Task 4: Integrate into Pipeline

**Files:**
- Modify: `lib/legendator/pipeline.rb` — add consistency step and `consistency` field to Result

- [ ] **Step 1: Modify Pipeline::Result to include consistency field**

In `lib/legendator/pipeline.rb`, change line 3-5 from:

```ruby
    Result = Struct.new(
      :srt_content, :coverage, :token_usage, :chunks_info, :provider, :model, :cost,
      keyword_init: true
    )
```

to:

```ruby
    Result = Struct.new(
      :srt_content, :coverage, :token_usage, :chunks_info, :provider, :model, :cost, :consistency,
      keyword_init: true
    )
```

- [ ] **Step 2: Add consistency check step to Pipeline#run**

In `lib/legendator/pipeline.rb`, replace lines 83-93 (the `[4/5]` and `[5/5]` block) with:

```ruby
      log "[4/6] Reconstructing SRT..."
      reconstructor = SrtReconstructor.new(all_translations, timestamps, texts)
      srt_output = reconstructor.build
      coverage = reconstructor.coverage_report
      log "     Coverage: #{coverage[:coverage_percent]}% (#{coverage[:translated]}/#{coverage[:total_subtitles]})"

      if coverage[:missing_ids].any?
        log "     Missing IDs: #{coverage[:missing_ids].join(', ')}"
      end

      log "[5/6] Checking consistency..."
      consistency_checker = ConsistencyChecker.new(
        original_srt: srt_content,
        translated_srt: srt_output,
        target_language: @target_language,
        provider: @provider,
        model: @model,
        api_key: @api_key
      )
      consistency = consistency_checker.run

      if consistency.pass?
        log "     Consistency check passed"
      else
        log "     Consistency check FAILED: #{consistency.errors.join('; ')}"
      end

      log "[6/6] Done!"
```

Also update the step numbers for earlier steps: `[1/5]` -> `[1/6]`, `[2/5]` -> `[2/6]`, `[3/5]` -> `[3/6]`.

- [ ] **Step 3: Add consistency to the Result.new call**

In the same file, add `consistency: consistency` to the `Result.new` block (around line 95-107):

```ruby
      Result.new(
        srt_content: srt_output,
        coverage: coverage,
        token_usage: {
          input_tokens: total_input_tokens,
          output_tokens: total_output_tokens,
          total_tokens: total_input_tokens + total_output_tokens
        },
        chunks_info: chunks_info,
        provider: @provider,
        model: @model,
        cost: total_cost,
        consistency: consistency
      )
```

- [ ] **Step 4: Run all gem tests to make sure nothing broke**

Run: `cd /Users/brpl20/code/legendator-gem && ruby -Ilib -Itest test/test_srt_parser.rb test/test_consistency_checker.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/brpl20/code/legendator-gem
git add lib/legendator/pipeline.rb
git commit -m "feat: integrate ConsistencyChecker into Pipeline as step 5/6"
```

---

### Task 5: Rails — check consistency result in TranslateSubtitleJob

**Files:**
- Modify: `/Users/brpl20/code/legendator-rails/app/jobs/translate_subtitle_job.rb`

- [ ] **Step 1: Add consistency check after translation**

In `app/jobs/translate_subtitle_job.rb`, add after the `result = Legendator.translate_content(...)` call (after line 16) and before the `costs = ...` line:

```ruby
    # Consistency check — critical failure if translation is structurally wrong
    if result.consistency && !result.consistency.pass?
      translation.update!(
        status: :failed,
        error_message: "Consistency check failed: #{result.consistency.errors.join('; ')}"
      )
      return
    end
```

- [ ] **Step 2: Verify the job file looks correct**

Run: `cd /Users/brpl20/code/legendator-rails && cat app/jobs/translate_subtitle_job.rb`
Expected: The consistency check block appears between the `translate_content` call and the `CostCalculator` call.

- [ ] **Step 3: Commit**

```bash
cd /Users/brpl20/code/legendator-rails
git add app/jobs/translate_subtitle_job.rb
git commit -m "feat: fail translation job when consistency check detects errors"
```

---

### Task 6: Manual integration test with test files

- [ ] **Step 1: Run a quick sanity check with the gem's test fixtures**

```bash
cd /Users/brpl20/code/legendator-gem
ruby -Ilib -e "
require 'legendator'
original = File.read('test/fixtures/sample.srt')
translated = File.read('test/fixtures/sample_pt-BR.srt')
checker = Legendator::ConsistencyChecker.new(
  original_srt: original,
  translated_srt: translated,
  target_language: 'pt-BR'
)
result = checker.check_structure
puts \"Pass: #{result.pass?}\"
puts \"Errors: #{result.errors}\"
"
```

Expected: `Pass: true`, `Errors: []`

- [ ] **Step 2: Test with a deliberately broken file**

```bash
cd /Users/brpl20/code/legendator-gem
ruby -Ilib -e "
require 'legendator'
original = File.read('test/fixtures/sample.srt')
# Remove last subtitle from translated
translated = File.read('test/fixtures/sample_pt-BR.srt').sub(/14\n00:01:03.*\z/m, '')
checker = Legendator::ConsistencyChecker.new(
  original_srt: original,
  translated_srt: translated,
  target_language: 'pt-BR'
)
result = checker.check_structure
puts \"Pass: #{result.pass?}\"
puts \"Errors: #{result.errors}\"
"
```

Expected: `Pass: false`, errors mentioning missing ID 14

- [ ] **Step 3: Run full test suite**

Run: `cd /Users/brpl20/code/legendator-gem && ruby -Ilib -Itest test/test_consistency_checker.rb test/test_srt_parser.rb`
Expected: All tests PASS
