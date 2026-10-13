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
    # This method waits for one or more tasks to
    # return. Within this method, the tracer
    # associated with a task closes the `on_tool_start`
    # span that was opened when the task spawned.
    #
    # @note
    #  This method might raise an {LLM::Interrupt}
    #  if one or more tasks were interrupted but
    #  only after the tracer has accounted for each
    #  task and collected an exit status from each
    #  of them.
    # @raise [LLM::Interrupt]
    # @return [Array<LLM::Function::Return>]
    def wait
      spawn unless @spawned
      interrupt = nil
      vals = @tasks.map do |task|
        val, started_at, finished_at = task.wait, task.started_at, task.finished_at
        if LLM::Interrupt === val
          interrupt = val
          task.tracer&.on_tool_interrupt(ex: val, span: task.span, started_at:, finished_at:)
        else
          if val.error?
            task.tracer&.on_tool_error(ex: val, span: task.span, started_at:, finished_at:)
          else
            task.tracer&.on_tool_finish(result: val, span: task.span, started_at:, finished_at:)
          end
          val
        end
      end
      interrupt ? raise(interrupt) : vals
    end
    alias_method :value, :wait
  end
end
