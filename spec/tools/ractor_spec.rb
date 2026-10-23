# frozen_string_literal: true

require "tmpdir"
require "setup"
require "llm/tools"

RSpec.describe "a tool that runs in a ractor" do
  before do
    skip "not supported by oj" unless ENV.fetch("JSON_PARSER", "json").downcase == "json"
  end

  def call_in_ractor(function, seconds = 15)
    task = function.task(:ractor)
    thread = Thread.new do
      Thread.current.report_on_exception = false
      task.wait
    end
    raise "timed out after #{seconds} seconds" unless thread.join(seconds)
    thread.value.to_h[:value]
  end

  describe "the value a call returns" do
    subject(:value) { call_in_ractor(function) }

    let(:function) do
      tool.function.dup.tap do |fn|
        fn.id = "call_1"
        fn.arguments = arguments
      end
    end

    context "when the call reads a class-level setting" do
      let(:tool) { LLM::Tool::ReadFile }
      let(:arguments) { {path:, start: 1, stop: 1} }
      let(:dir) { Dir.mktmpdir }
      let(:path) { File.join(dir, "sample.txt") }

      before { File.write(path, "line 1\nline 2\n") }
      after { FileUtils.remove_entry(dir) }

      it "is the value the tool produced" do
        expect(value).to eq(
          ok: true,
          lines: [{lineno: 1, content: "line 1\n"}],
          truncated: false
        )
      end
    end

    context "when the parameter defaults read a class-level setting" do
      let(:tool) { LLM::Tool::Exec }
      let(:arguments) { {arguments: [RbConfig.ruby, "-e", "print 1"]} }

      it "is the value the tool produced" do
        expect(value).to include(ok: true, stdout: "1")
      end
    end
  end

  describe "the sentinel an omitted argument falls back on" do
    [LLM, LLM::Tool, LLM::Agent, LLM::Buffer].each do |owner|
      context "when it is read from #{owner}::UNDEFINED" do
        let(:sentinel) { owner.const_get(:UNDEFINED, false) }

        it "is shareable" do
          expect(Ractor.shareable?(sentinel)).to be(true)
        end
      end
    end
  end
end
