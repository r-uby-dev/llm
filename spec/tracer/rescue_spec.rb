# frozen_string_literal: true

require "setup"

##
# The promise `LLM::Tracer::Rescue` makes, and the two ways a
# tracer breaks it: a hook the base class raises for because
# nobody answered it, and a hook of the tracer's own that
# raises. Both are reported to stderr rather than raised, and
# an agent keeps running either way.
#
# **The subclass is defined inside the example rather than at
# the top of the file, and that is half of what is being
# tested.** The module reaches a subclass through
# `Tracer.inherited`, which only fires for classes defined
# after the hook exists - so a tracer defined at load time
# here would prove the mechanism works while telling us
# nothing about the order the requires are in.
#
# **And the first example uses `on_request_start` rather
# than `on_interrupt`.** It is about the base class raising
# for a hook nobody answered, which is the case the module
# has to contain, and `on_request_start` is the hook whose
# default has always done that. `on_interrupt` is the one
# that only just started to.
RSpec.describe LLM::Tracer::Rescue do
  let(:provider) { LLM.openai(key: "test") }
  let(:tracer) { klass.new(provider) }

  describe "a hook the tracer does not implement" do
    let(:klass) { Class.new(LLM::Tracer) }

    ##
    # The message is matched in its stable halves rather than
    # whole. Both ends of it name the class, and the class is
    # anonymous - so what is printed there is an address, and
    # an address is not a thing to write a regexp around.
    it "reports it rather than raising it" do
      expect($stderr).to receive(:puts).with(
        /crashed: NotImplementedError \(.*does not implement 'on_request_start'\)/,
        a_kind_of(String)
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
        /crashed: RuntimeError \(boom\)/,
        a_kind_of(String)
      )
      tracer.on_interrupt(scope: :tool)
    end
  end
end
