# Legendator

Translate SRT subtitles using AI (OpenAI / OpenRouter).

## Installation

Add to your Gemfile:

```ruby
gem "legendator"
```

And run:

```sh
bundle install
```

Or install directly:

```sh
gem install legendator
```

## Configuration

```ruby
Legendator.configure do |config|
  config.provider = :openai          # :openai or :openrouter
  config.api_key  = "sk-..."         # generic key (overrides provider-specific)
  config.model    = "gpt-4.1-mini"
  config.target_language = "pt-BR"
end
```

Provider-specific keys are also supported:

```ruby
Legendator.configure do |config|
  config.openai_api_key     = "sk-..."
  config.openrouter_api_key = "sk-or-..."
end
```

Environment variables (`.env`) work as defaults when no configuration block is set:

```
OPENAI_API_KEY=sk-...
DEFAULT_PROVIDER=openai
DEFAULT_MODEL=gpt-4.1-mini
DEFAULT_TARGET_LANGUAGE=pt-BR
```

## Usage

### Translate a file

```ruby
result = Legendator.translate("movie.srt", lang: "pt-BR", context: "Action movie")
result.srt_content   # translated SRT string
result.coverage      # { total_subtitles: 100, translated: 100, ... }
result.token_usage   # { input_tokens: 5000, output_tokens: 4000, ... }
```

### Translate a string

```ruby
srt_string = File.read("movie.srt")
result = Legendator.translate_content(srt_string, lang: "es")
```

### Dry run (estimate tokens, no API calls)

```ruby
info = Legendator.dry_run("movie.srt")
info[:subtitles]          # number of subtitles
info[:chunks]             # chunking details
info[:estimated_tokens]   # token estimate
```

### Rails initializer

```ruby
# config/initializers/legendator.rb
Legendator.configure do |config|
  config.provider = :openai
  config.api_key  = Rails.application.credentials.openai_api_key
  config.model    = "gpt-4.1-mini"
end
```

### Provider fallback cascade

Configure fallback providers so translation continues if the primary provider fails:

```ruby
Legendator.configure do |config|
  config.provider = :openrouter
  config.api_key  = "sk-or-..."
  config.model    = "openai/gpt-4.1-mini"

  # If primary fails, try these in order
  config.fallback_providers = [
    { provider: :openrouter, model: "google/gemini-2.5-flash" },
    { provider: :openrouter, model: "deepseek-ai/deepseek-chat" },
    { provider: :openai, model: "gpt-4.1-mini", api_key: "sk-..." }
  ]

  config.max_retries = 3       # retries per provider (default: 3)
  config.retry_base_delay = 2  # base delay in seconds (default: 2)
end
```

Each provider gets `max_retries` attempts with exponential backoff before moving to the next. Retryable errors include HTTP 429, 500, 502, 503, 504, timeouts, and connection failures.

### Per-call overrides

```ruby
Legendator.translate_content(
  srt_string,
  lang: "pt-BR",
  provider: :openrouter,
  model: "openai/gpt-4.1",
  fallback_providers: [{ provider: :openai, model: "gpt-4.1-mini", api_key: "sk-..." }]
)
```

## CLI

```sh
legendator translate movie.srt --lang=pt-BR --context="Action movie"
legendator dry-run movie.srt
legendator info movie.srt
legendator debug movie.srt
```

Options:

- `--provider=openai|openrouter`
- `--model=gpt-4.1-mini`
- `--lang=pt-BR`
- `--context="..."`
- `--max-tokens=6000`
- `--output=output.srt`

## Production Checklist

Items already implemented:

- [x] Provider fallback cascade (primary + N fallbacks)
- [x] Retry with exponential backoff and jitter per provider
- [x] Retryable error classification (429, 5xx, timeouts, connection errors)
- [x] Consistency checker (structural + semantic via AI)
- [x] Missing subtitle repair (up to 2 attempts)
- [x] UTF-8 encoding fallback chain (UTF-8, ISO-8859-1, Windows-1252, UTF-16)

Pending items for future hardening:

- [ ] Structured logging (configurable logger with levels)
- [ ] Cost calculation fallback when API does not return cost data
- [ ] Strict mode option (fail on incomplete translations instead of continuing)
- [ ] Encoding loss warnings (log when invalid chars are replaced with `?`)
- [ ] Rate limiting / request queueing for high-volume usage
- [ ] Benchmarks and performance profiling for large files

## License

MIT License. See [LICENSE.txt](LICENSE.txt).
