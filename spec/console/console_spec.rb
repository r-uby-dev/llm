# frozen_string_literal: true

require "setup"
require "llm/console"

RSpec.describe "LLM::Console" do
  it "aliases LLM::Console" do
    expect(LLM::Console).to be(LLM::Console)
  end
end
