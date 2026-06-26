# frozen_string_literal: true

require_relative "lib/llm/version"

Gem::Specification.new do |spec|
  spec.name = "llm.rb"
  spec.version = LLM::VERSION
  spec.authors = ["Robert (0x1eef)", "Antar Azri", "Rodrigo Serrano"]
  spec.email = ["robert@r.uby.dev"]

  spec.summary = "Ruby's capable AI runtime"
  spec.description = "llm.rb is not a library, framework or toolkit but " \
                     "an advanced runtime for building highly capable AI " \
                     "applications on CRuby."
  spec.license = "0BSD"
  spec.required_ruby_version = ">= 3.3.0"

  spec.homepage = "https://r.uby.dev/llm/"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/r-uby-dev/llm.rb"
  spec.metadata["documentation_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://r.uby.dev/api-docs/llm.rb/file.CHANGELOG.html"

  spec.files = Dir[
    "README.md", "LICENSE",
    "lib/*.rb", "lib/**/*.rb",
    "data/*.json", "CHANGELOG.md",
    "resources/deepdive.md",
    "llm.gemspec"
  ]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "webmock", "~> 3.24.0"
  spec.add_development_dependency "yard", "~> 0.9.37"
  spec.add_development_dependency "redcarpet", "~> 3.6"
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
