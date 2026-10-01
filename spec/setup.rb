# frozen_string_literal: true

require "llm"
require "webmock/rspec"
require "vcr"
require "dotenv"

# A run's output is a pipe in CI, and a pipe is block-buffered: an example
# that hangs leaves a log that says nothing about which one it was.
STDOUT.sync = true

Dir[File.join(__dir__, "support/**/*.rb")].sort.each { require(_1) }
Dotenv.load

LLM.json = ENV.fetch("JSON_PARSER", "JSON")

RSpec.configure do |config|
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.around(:each, :interval) do |example|
    example.run
  ensure
    interval = example.metadata[:interval].to_f
    sleep(interval) if interval > 0 && !cassette_recorded?(example)
  end
end

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  ##
  # scrub
  config.filter_sensitive_data("TOKEN") { ENV["ANTHROPIC_SECRET"] }
  config.filter_sensitive_data("TOKEN") { ENV["GOOGLE_SECRET"] }
  config.filter_sensitive_data("TOKEN") { ENV["OPENAI_SECRET"] }
  config.filter_sensitive_data("TOKEN") { ENV["DEEPSEEK_SECRET"] }
  config.filter_sensitive_data("TOKEN") { ENV["DEEPINFRA_SECRET"] }
  config.filter_sensitive_data("TOKEN") { ENV["XAI_SECRET"] }
  config.filter_sensitive_data("TOKEN") { ENV["ZAI_SECRET"] }
  config.filter_sensitive_data("TOKEN") { ENV["MOONSHOT_API_KEY"] }
  config.filter_sensitive_data("TOKEN") { ENV["OPENROUTER_API_KEY"] }
  config.filter_sensitive_data("TOKEN") { ENV["DASHSCOPE_API_KEY"] }
  config.filter_sensitive_data("TOKEN") { ENV["AWS_ACCESS_KEY_ID"] }
  config.filter_sensitive_data("TOKEN") { ENV["AWS_SECRET_ACCESS_KEY"] }
  config.filter_sensitive_data("TOKEN") { ENV["AWS_SESSION_TOKEN"] }
  config.filter_sensitive_data("localhost") { ENV["OLLAMA_HOST"] }
  config.filter_sensitive_data("localhost") { ENV["LLAMACPP_HOST"] }

  config.before_record do
    body = _1.response.body
    body.gsub! %r|#{Regexp.escape("https://oaidalleapiprodscus.blob.core.windows.net/")}[^"]+|,
               "https://openai.com/generated/image.png"
  end
end

def cassette_recorded?(example)
  vcr = example.metadata[:vcr] || {}
  name = vcr[:cassette_name]
  return false unless name
  File.exist?(File.join(VCR.configuration.cassette_library_dir, "#{name}.yml"))
end
