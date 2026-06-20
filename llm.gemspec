# frozen_string_literal: true

require_relative "lib/llm/version"

Gem::Specification.new do |spec|
  spec.name = "llm.rb"
  spec.version = LLM::VERSION
  spec.authors = ["0x1eef (Robert)", "Antar Azri", "Rodrigo Serrano"]
  spec.email = ["robert@4.4bsd.dev"]

  spec.summary = "Ruby's capable AI runtime"
  spec.description = <<~DESC
  llm.rb is Ruby's capable AI runtime.

  It runs on Ruby's standard library by default. loads optional pieces
  only when needed, and offers a single runtime for providers, agents,
  tools, skills, MCP, A2A (Agent2Agent), RAG (vector stores & embeddings),
  streaming, files, and persisted state. As a bonus, llm.rb is also available
  for mruby.

  It supports OpenAI, OpenAI-compatible endpoints, Anthropic, Google
  Gemini, DeepSeek, xAI, Z.ai, AWS Bedrock, Ollama, and llama.cpp. It
  also includes built-in ActiveRecord and Sequel support, plus concurrent
  tool execution through threads, tasks (via async gem), fibers, ractors,
  and fork (via xchan.rb gem).
  DESC

  spec.license = "0BSD"
  spec.required_ruby_version = ">= 3.3.0"

  spec.homepage = "https://r.uby.dev/llm/"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/llmrb/llm.rb"
  spec.metadata["documentation_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://0x1eef.github.io/x/llm.rb/file.CHANGELOG.html"

  spec.files = Dir[
    "README.md", "LICENSE",
    "lib/*.rb", "lib/**/*.rb",
    "data/*.json", "CHANGELOG.md",
    "llm.gemspec"
  ]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "webmock", "~> 3.24.0"
  spec.add_development_dependency "yard", "~> 0.9.37"
  spec.add_development_dependency "kramdown", "~> 2.4"
  spec.add_development_dependency "webrick", "~> 1.8"
  spec.add_development_dependency "test-cmd.rb", "~> 0.12.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "standard", "~> 1.50"
  spec.add_development_dependency "vcr", "~> 6.0"
  spec.add_development_dependency "dotenv", "~> 2.8"
  spec.add_development_dependency "net-http-persistent", "~> 4.0"
  spec.add_development_dependency "opentelemetry-sdk", "~> 1.10"
  spec.add_development_dependency "logger", "~> 1.7"
  spec.add_development_dependency "activerecord", "~> 8.0"
  spec.add_development_dependency "sequel", "~> 5.0"
  spec.add_development_dependency "sqlite3", "~> 2.0"
  spec.add_development_dependency "xchan.rb", "~> 0.20"
  spec.add_development_dependency "pg", "~> 1.5"
  spec.add_development_dependency "irb", "~> 1.18"
end
