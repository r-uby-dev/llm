# frozen_string_literal: true

require_relative "lib/llm/version"

Gem::Specification.new do |spec|
  spec.name = "llm.rb"
  spec.version = LLM::VERSION
  spec.authors = ["Robert Gleeson",
                  "Antar Azri",
                  "Rodrigo Serrano",
                  "Azmi Muwahid",
                  "George Pickett",
                  "Mika Mikasuki",
                  "Nikulin Nikita",
                  "pttydou",
                  "Samad Mahmood",
                  "Rohan Sharma",
                  "erSpell",
                  "Madhavi Dayma"].sort
  spec.email = ["robert@r.uby.dev"]

  spec.summary = "An agentic runtime for Ruby"
  spec.description = <<~DESCRIPTION
llm.rb is a runtime for building agentic AI applications
on CRuby. It runs on Ruby's standard library and nothing
else by default, it supports concurrent and parallel tool
execution and has a single coherent API that spans 15+
providers.
DESCRIPTION

  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.0"

  spec.homepage = "https://r.uby.dev"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/r-uby-dev/llm"
  spec.metadata["documentation_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/r-uby-dev/llm/blob/main/CHANGELOG.md"

  spec.files = Dir[
    "README.md", "LICENSE",
    "lib/*.rb", "lib/**/*.rb",
    "data/*.json", "CHANGELOG.md",
    "docs/deepdive.md",
    "docs/deepdive/*/*.md",
    "llm.gemspec", "bin/llm.rb"
  ]
  spec.executables = ["llm.rb"]
  spec.require_paths = ["lib"]

  ##
  # Nothing outside Ruby's standard library
  spec.add_runtime_dependency "net-http", "~> 0.10"
  spec.add_runtime_dependency "json", "~> 3.1"

  ##
  # Optional dependencies
  spec.add_development_dependency "webmock", "~> 3.24.0"
  spec.add_development_dependency "yard", "~> 0.9.37"
  spec.add_development_dependency "redcarpet", "~> 3.6"
  spec.add_development_dependency "webrick", "~> 1.8"
  spec.add_development_dependency "test-cmd.rb", "~> 2.7.3"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "vcr", "~> 6.0"
  spec.add_development_dependency "dotenv", "~> 2.8"
  spec.add_development_dependency "net-http-persistent", "~> 4.0"
  spec.add_development_dependency "opentelemetry-sdk", "~> 1.10"
  spec.add_development_dependency "logger", "~> 1.7"
  spec.add_development_dependency "activerecord", "~> 8.1"
  spec.add_development_dependency "sequel", "~> 5.105"
  spec.add_development_dependency "sqlite3", "~> 2.0"
  spec.add_development_dependency "xchan.rb", "~> 0.24"
  spec.add_development_dependency "pg", "~> 1.5"
  spec.add_development_dependency "irb", "~> 1.18"
  spec.add_development_dependency "kramdown", "~> 2.5"
  spec.add_development_dependency "unicode-display_width", "~> 3.2"
  spec.add_development_dependency "async", "~> 2.45"

  ##
  # Not worth the hassle rn
  # spec.add_development_dependency "standard", "= 1.54.0"
  # spec.add_development_dependency "rubocop", "= 1.84.2"
end
