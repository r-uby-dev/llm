# frozen_string_literal: true

class LLM::Function
  ##
  # Runs a tool call inside the one ractor a task spawns,
  # and delivers its result to the port the task holds.
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
    # Runs the call and answers with one message: the
    # result, or a note that the call was interrupted or
    # raised.
    #
    # The watcher is stopped before this ractor ends. A
    # ractor does not end while a thread it made is still
    # running, and the watcher would sit blocked on a
    # message that never comes.
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
    # Tells the watcher the call is over, and waits for it to
    # go.
    #
    # The `:stop` message is what ends it. Killing it would
    # leave the ractor holding a thread that has gone, and a
    # ractor waits on threads that have gone.
    # @param [Thread, nil] watcher
    # @return [void]
    def watch_stop(watcher)
      return unless watcher
      ::Ractor.current.send(:stop)
      watcher.join(1)
      watcher.kill if watcher.alive?
      nil
    end

    ##
    # Watches for an interrupt on a thread of the ractor's
    # own, so the main thread can stay inside the tool.
    #
    # It forwards in the order the window promises: the tool
    # is told first, and the raise is issued after.
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
