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

## License

MIT License. See [LICENSE.txt](LICENSE.txt).
