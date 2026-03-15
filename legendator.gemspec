require_relative "lib/legendator/version"

Gem::Specification.new do |spec|
  spec.name          = "legendator"
  spec.version       = Legendator::VERSION
  spec.authors       = ["brpl20"]
  spec.summary       = "Translate SRT subtitles using AI (OpenAI / OpenRouter)"
  spec.description   = "A Ruby library and CLI for translating SRT subtitle files using AI providers (OpenAI, OpenRouter). Supports chunked translation, token counting, and structured output."
  spec.homepage      = "https://github.com/brpl20/legendator"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.1.0"

  spec.files         = Dir["lib/**/*.rb", "bin/*", "LICENSE.txt", "README.md", "CHANGELOG.md"]
  spec.bindir        = "bin"
  spec.executables   = ["legendator"]
  spec.require_paths = ["lib"]

  spec.add_dependency "net-http"
  spec.add_dependency "tiktoken_ruby", "~> 0.0.9"
end
