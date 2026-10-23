# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Function::Ractor::Group do
  before do
    skip "not supported by oj" unless ENV.fetch("JSON_PARSER", "json").downcase == "json"
  end

  def within(seconds = 5, &block)
    thread = Thread.new do
      Thread.current.report_on_exception = false
      block.call
    end
    thread.join(seconds) ? thread.value : raise("timed out after #{seconds} seconds")
  end

  let(:group) { LLM::Function::Ractor::Group.new([finished, holding]) }

  let(:finished) do
    Class.new(LLM::Tool) do
      name "finished"

      def call
        {ok: true}
      end
    end.function.dup.tap do |fn|
      fn.id = "call_1"
      fn.arguments = {}
    end.task(:ractor)
  end

  let(:holding) do
    Class.new(LLM::Tool) do
      name "holding"

      def call
        sleep 2
        {ok: true}
      end
    end.function.dup.tap do |fn|
      fn.id = "call_2"
      fn.arguments = {}
    end.task(:ractor)
  end

  describe "a cancel for a group with a returned call in it" do
    before do
      group.spawn
      within { finished.wait }
      group.interrupt!
    end

    it "reaches the calls after the one that has returned" do
      expect { within { group.wait } }.to raise_error(LLM::Interrupt)
    end
  end
end
