# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Tracer::Rescue do
  let(:provider) { LLM.openai(key: "test") }
  let(:tracer) { klass.new(provider) }

  describe "a hook the tracer does not implement" do
    let(:klass) { Class.new(LLM::Tracer) }

    it "reports it rather than raising it" do
      expect($stderr).to receive(:puts).with(
        "",
        "an llm.rb tracer has crashed.",
        "",
        /\[  tracer    \] #</,
        "[  class     ] NotImplementedError",
        /\[  message   \] .*does not implement 'on_request_start'/,
        "[  backtrace ] ",
        "\n",
        a_kind_of(String),
        "\n\n"
      )
      tracer.on_request_start(operation: "chat", request_id: "req_1")
    end
  end

  describe "a hook of the tracer's own that raises" do
    let(:klass) do
      Class.new(LLM::Tracer) do
        ##
        # @param [Symbol] scope
        # @return [void]
        def on_interrupt(**)
          raise "boom"
        end
      end
    end

    it "reports it rather than raising it" do
      expect($stderr).to receive(:puts).with(
        "",
        "an llm.rb tracer has crashed.",
        "",
        /\[  tracer    \] #</,
        "[  class     ] RuntimeError",
        "[  message   ] boom",
        "[  backtrace ] ",
        "\n",
        a_kind_of(String),
        "\n\n"
      )
      tracer.on_interrupt(scope: :tool)
    end
  end
end
