# Consistency Checker Design

## Problem

After translating an SRT file, there is no verification that the output is structurally correct or that subtitles were actually translated. Since users pay upfront, a bad translation is a critical error requiring manual intervention.

## Solution

A `ConsistencyChecker` class in the gem that runs two verification steps after translation:

1. **Structural check (deterministic, no AI):** Verifies IDs, timestamps, and subtitle count match between original and translated SRT.
2. **Translation check (AI, 5 random samples):** Sends 5 random subtitle pairs to an AI model asking "was this translated?" — not evaluating quality, just confirming the text changed language.

## API

```ruby
checker = Legendator::ConsistencyChecker.new(
  original_srt: "original SRT string",
  translated_srt: "translated SRT string",
  target_language: "pt-BR",
  provider: :openrouter,
  model: "deepseek/deepseek-chat-v3-0324",
  api_key: nil
)

result = checker.run
result.pass?          # true/false
result.errors         # ["ID mismatch: original has 150, translated has 148"]
result.sample_details # [{id: 42, original: "...", translated: "...", passed: true}, ...]
```

### Result Struct

```ruby
Result = Struct.new(:pass, :errors, :sample_details, keyword_init: true) do
  alias_method :pass?, :pass
end
```

## Step 1 — Structural Verification

Parse both SRTs with `SrtParser`. Compare:

- **Count:** Same number of subtitles?
- **IDs:** Every ID in original exists in translated?
- **Timestamps:** For each matching ID, timestamp is identical?

Any mismatch is added to `errors`. If structural errors exist, return `pass: false` immediately without making an AI request.

## Step 2 — Translation Verification

Only runs if Step 1 passes. Selects 5 random subtitle IDs. Sends pairs to AI with this prompt:

```
For each pair below, answer ONLY with a JSON object.
Each pair has an original subtitle and a supposed translation to {target_language}.
Answer whether each one was actually translated (not left in the original language).

{pairs as JSON}

Return: {"id": true/false, ...}
```

If any of the 5 returns `false`, adds error `"Subtitle ID {n} was not translated"` and sets `pass: false`.

The `sample_details` field stores all 5 checked pairs and their results for debugging.

## Pipeline Integration

`Pipeline#run` gains a new step `[5/6] Checking consistency...` after SRT reconstruction. The `Pipeline::Result` struct gains a `consistency` field containing the checker's result.

The pipeline passes its own `provider`, `model`, and `api_key` to the checker. Any cheap model works for verification.

## Rails Integration

In `TranslateSubtitleJob`:

```ruby
if result.consistency && !result.consistency.pass?
  translation.update!(
    status: :failed,
    error_message: "Consistency check failed: #{result.consistency.errors.join('; ')}"
  )
  return
end
```

## Scope Boundaries

- No retry logic — failure is critical, requires manual intervention
- No translation quality analysis — only checks "was it translated at all?"
- Structural check always runs; AI check only if structural passes
- Uses existing `SrtParser` and `AiClient` from the gem

## Files to Create/Modify

- **Create:** `lib/legendator/consistency_checker.rb`
- **Create:** `test/test_consistency_checker.rb`
- **Modify:** `lib/legendator/pipeline.rb` — add step 5/6 and `consistency` field to Result
- **Modify:** `lib/legendator.rb` — require the new file
- **Modify (Rails):** `app/jobs/translate_subtitle_job.rb` — check consistency result
