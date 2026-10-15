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

  ##
  # Windows has no `fork`, and the fork specs ask whether `xchan.rb` is
  # installed rather than whether a process can be forked. An example that
  # runs a tool on a fork is skipped where `fork` is not there: it is one
  # of the files under `spec/function/fork`, one tagged `:fork`, or one
  # whose group says in its description that a fork is what the tool runs
  # on - which is how `spec/agent_spec.rb` and `spec/context_spec.rb` ask
  # for one. The tracer's shared group asks its own strategy.
  config.before(:each) do |example|
    skip "fork is not available" if !Process.respond_to?(:fork) && fork_example?(example)
  end

  ##
  # A ractor is not usable on Windows either: a call that runs a tool in
  # one does not come back, and the examples that run one - the ractor
  # specs, and the rest of the suite where it asks for one - do not come
  # back either. Such an example is skipped the way a fork example is: it
  # is one of the files under `spec/function/ractor`, one tagged `:ractor`
  # (a task built on a group's default strategy cannot say so in a
  # description), or one whose description names a ractor.
  config.before(:each) do |example|
    skip "a ractor hangs on this platform" if !ractors? && ractor_example?(example)
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

##
# True when a call can be run in a ractor. It cannot on Windows, where a
# call that runs a tool in one does not come back. The question is asked
# by a hook rather than while this file loads, the way the rest of these
# helpers are.
def ractors?
  !Gem.win_platform?
end

def cassette_recorded?(example)
  vcr = example.metadata[:vcr] || {}
  name = vcr[:cassette_name]
  return false unless name
  File.exist?(File.join(VCR.configuration.cassette_library_dir, "#{name}.yml"))
end

##
# True when an example runs a tool on a fork. The files under
# `spec/function/fork` are fork examples whole, and the rest say so in the
# description their group was given, or with a `:fork` tag.
def fork_example?(example)
  metadata = example.metadata
  metadata[:fork] ||
    metadata[:file_path].include?("/function/fork/") ||
    metadata[:full_description].match?(/fork/i)
end

##
# True when an example runs a tool in a ractor. The files under
# `spec/function/ractor` are ractor examples whole, and the rest say so in
# the description their group was given, or with a `:ractor` tag.
def ractor_example?(example)
  metadata = example.metadata
  metadata[:ractor] ||
    metadata[:file_path].include?("/function/ractor/") ||
    metadata[:full_description].match?(/ractor/i)
end
