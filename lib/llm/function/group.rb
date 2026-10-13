# frozen_string_literal: true

class LLM::Function
  ##
  # Abstract superclass for all concurrency strategy groups.
  # Each strategy (sequential, thread, fiber, async, fork, ractor)
  # subclasses this and implements {#spawn}, {#alive?} and
  # {#interrupt!}. {#wait} is shared, and a strategy whose tasks
  # report themselves answers with one of its own.
  class Group
    ##
    # @abstract
    # @return [nil]
    def spawn
      raise NotImplementedError
    end

    ##
    # @abstract
    # @return [Boolean]
    def alive?
      raise NotImplementedError
    end

    ##
    # @abstract
    # @return [nil]
    def interrupt!
      raise NotImplementedError
    end
    alias_method :cancel!, :interrupt!

    ##
    # Wait for the calls to answer.
    #
    # This is where the calls are reported to the tracer. A task answers
    # with its outcome - the value the tool returned, or the exception
    # it ended with - and a group is the frame that knows a call was
    # interrupted, so it is the frame that tells the tracer and then
    # raises, which puts the callback before the caller sees anything.
    #
    # A strategy whose tasks report themselves, or whose ending is not
    # an outcome, answers with its own {#wait}.
    # @return [Array<LLM::Function::Return>]
    def wait
      spawn unless @spawned
      interrupt = nil
      vals = @tasks.map do |task|
        val = task.wait
        if LLM::Interrupt === val
          interrupt = val
          task.tracer&.on_tool_interrupt(ex: val, span: task.span, finished_at: task.finished_at)
        else
          if val.error?
            task.tracer&.on_tool_error(ex: val, span: task.span, finished_at: task.finished_at)
          else
            task.tracer&.on_tool_finish(result: val, span: task.span, finished_at: task.finished_at)
          end
          val
        end
      end
      interrupt ? raise(interrupt) : vals
    end
    alias_method :value, :wait
  end
end
