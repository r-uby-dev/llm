# frozen_string_literal: true

module LLM::ResponseFactory
  def response!(choices:, usage: {})
    body = LLM::Object.from(id: "test", choices:, usage:)
    res = Net::HTTPOK.new("1.1", "200", "OK")
    res.body = body
    res.instance_variable_set(:@read, true)
    LLM::Response.new(LLM::Transport::Response.from(res))
  end
end

RSpec.configure do |config|
  config.include LLM::ResponseFactory
end

