# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Tracer::Rescue do
  let(:provider) { LLM.openai(key: "test") }
  let(:tracer) { klass.new(provider) }

  describe "a hook the tracer does not implement" do
    let(:klass) { Class.new(LLM::Tracer) }

    it "reports it rather than raising it" do
      expect { tracer.on_request_start(operation: "chat", request_id: "req_1") }
        .to output(/\[  error     \] NotImplementedError.*does not implement 'on_request_start'/m)
        .to_stderr
    end
  end

  describe "a hook of the tracer's own that raises" do
    let(:klass) do
      Class.new(LLM::Tracer) do
        def on_interrupt(**)
          raise "boom"
        end
      end
    end

    it "reports it rather than raising it" do
      expect { tracer.on_interrupt(scope: :tool) }
        .to output(/\[  error     \] RuntimeError.*\[  message   \] boom/m)
        .to_stderr
    end
  end
end
