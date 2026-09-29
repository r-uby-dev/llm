# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::Fork::Job} class represents a single fork-backed
  # function call inside the child process.
  #
  # It is executed in the forked process and is responsible for running the
  # resolved tool instance, handling control messages such as interrupts, and
  # writing the final result back to the parent process.
  class Fork::Job
    ##
    # @param [LLM::Function] function
    # @param [LLM::Object] ch
    # @return [LLM::Function::Fork::Job]
    def initialize(function, ch)
      @function = function
      @ch = ch
    end

    ##
    # @return [void]
    def call
      runner = @function.runner
      ##
      # Before the watcher exists, because an interrupt can arrive first:
      # it is a datagram and it waits in the channel until the watcher
      # reads it.
      @window = LLM::Function::Window.new
      controller = setup(runner)
      ##
      # And everything the call needs is prepared outside the window, so
      # the distance from `running!` to the tool's first instruction is
      # the method dispatch and nothing else.
      kwargs = arguments_for(@function)
      @window.running!
      result = call!(runner, kwargs)
      ##
      # The window closes the moment the tool has returned and before the
      # result is written, so an interrupt that arrives once the work is
      # done is a no-op rather than a reason to throw the result away.
      @window.finished!
      @ch.result.write([:result, result])
    rescue LLM::Interrupt
      @ch.result.write([:interrupt])
    rescue => ex
      @ch.result.write([:result, error(ex)])
    ensure
      ##
      # For the paths above that did not reach the line, and nil-safe for
      # a raise before the window existed.
      @window&.finished!
      controller&.kill
      [@ch.control, @ch.result].each { _1.close unless _1.closed? }
    end

    private

    def call!(runner, kwargs)
      {id: @function.id, name: @function.name, value: runner.call(**kwargs)}
    end

    def arguments_for(function)
      Hash === function.arguments ? function.arguments.transform_keys(&:to_sym) : function.arguments
    end

    def error(ex)
      {
        id: @function.id,
        name: @function.name,
        value: {error: true, type: ex.class.name, message: ex.message}
      }
    end

    def setup(runner)
      ready = Queue.new
      thread = ::Thread.new do
        ready << true
        kind = @ch.control.recv
        next unless kind == :interrupt
        ##
        # The window decides whether this is the tool's to handle, or
        # whether the tool has already been and gone.
        @window.interrupt!
      rescue IOError, ArgumentError
      end
      ready.pop
      thread
    end
  end
end
