# frozen_string_literal: true

module LLM::Function::Async
  ##
  # Runs submitted work on a reactor of its own thread.
  class Reactor
    ##
    # @return [Thread]
    attr_reader :thread

    def initialize
      @inbox = Queue.new
      @wake_r, @wake_w = IO.pipe
      @thread = Thread.new { run }
    end

    ##
    # @return [nil]
    def submit(&block)
      @inbox << block
      wake!
      nil
    end

    ##
    # @return [nil]
    def stop
      @inbox << :stop
      wake!
      return nil if @thread == ::Thread.current
      @thread.join(5)
      @thread.kill if @thread.alive?
      nil
    end

    private

    ##
    # @return [void]
    def wake!
      @wake_w.write_nonblock(".", exception: false)
    rescue IOError, Errno::EPIPE
      nil
    end

    ##
    # @return [nil]
    def run
      reactor = ::Async::Reactor.new
      reactor.async do
        stopped = false
        until stopped
          @wake_r.read(1)
          loop do
            work = begin
              @inbox.pop(true)
            rescue ThreadError
              break
            end
            if work == :stop
              stopped = true
              break
            end
            reactor.async { work.call }
          end
        end
        reactor.stop
      end
      reactor.run
    ensure
      ::Fiber.set_scheduler(nil)
    end
  end
end
