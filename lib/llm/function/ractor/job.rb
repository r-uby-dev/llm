# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::Ractor::Job} class runs a tool call inside
  # the one ractor a task spawns, and delivers its result to the
  # port the task holds.
  class Ractor::Job
    ##
    # @api private
    Ractor = ::Ractor
    private_constant :Ractor

    ##
    # @param [Ractor::Port] port
    #  The port the task reads the result from
    # @param [Class] runner_class
    # @param [String, nil] id
    # @param [String] name
    # @param [Hash, Array, nil] arguments
    # @param [String] cookie
    # @return [LLM::Function::Ractor::Job]
    def initialize(port, runner_class, id, name, arguments, cookie)
      @port = port
      @runner_class = runner_class
      @id = id
      @name = name
      @arguments = arguments
      @cookie = cookie
    end

    ##
    # Runs the call, and answers with exactly one message: the result,
    # or a note that says the call was interrupted or raised.
    #
    # **The watcher is stopped before this ractor ends.** A ractor does
    # not end while a thread it made is still running, and the watcher is
    # a thread blocked on a message that will never come once the call is
    # done - so it is sent one, and joined, rather than left to hold the
    # ractor open for the rest of the process's life.
    # @return [void]
    def call
      finished_at = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      window = LLM::Function::Window.new(thread: ::Thread.current)
      runner = @runner_class.new
      watcher = watch(runner, window)
      kwargs = Hash === @arguments ? @arguments.transform_keys(&:to_sym) : @arguments
      window.running!
      result = runner.call(**kwargs)
      window.finished!
      @port.send([:done, @id, @name, result, finished_at.()])
    rescue LLM::Interrupt
      @port.send([:done, @id, @name, {interrupt: true, cookie: @cookie}, finished_at.()])
    rescue => ex
      @port.send([:done, @id, @name, {error: true, type: ex.class.name, message: ex.message}, finished_at.()])
    ensure
      watch_stop(watcher)
    end

    private

    ##
    # Tells the watcher that the call is over and waits for it to go.
    #
    # A watcher that never started has nothing to stop. One that is
    # blocked on `Ractor.receive` is released by the `:stop` message,
    # which is the only thing that ends it: killing it would leave the
    # ractor holding a thread that has gone, and a thread that has gone
    # is not what a ractor waits for before it ends.
    # @param [Thread, nil] watcher
    # @return [void]
    def watch_stop(watcher)
      return unless watcher
      ::Ractor.current.send(:stop)
      watcher.join(1)
      watcher.kill if watcher.alive?
      nil
    end

    private

    ##
    # Watches for an interrupt on a thread of the ractor's own, so the
    # ractor's main thread can stay inside the tool.
    #
    # The watcher is what an interrupt reaches, and it forwards in the
    # order the window promises: the tool is told first, and the raise
    # is issued after - so a tool that releases a resource has released
    # it by the time the raise lands.
    #
    # A watcher is ended by the `:stop` message `watch_stop` sends once
    # the call is over, rather than by the ractor ending underneath it:
    # a ractor does not end while a thread it made is still blocked.
    # @param [LLM::Tool] runner
    # @param [LLM::Function::Window] window
    # @return [Thread]
    def watch(runner, window)
      ::Thread.new do
        loop do
          kind = begin
            ::Ractor.receive
          rescue ::Ractor::Error
            break
          end
          break if kind == :stop
          next unless kind == :interrupt
          begin
            LLM::Function.interrupt(runner)
          ensure
            window.interrupt!
          end
        end
      end
    end
  end
end
