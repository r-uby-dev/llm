# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::Ractor::Job} class manages execution and mailbox
  # coordination for a single ractor-backed function call.
  class Ractor::Job
    ##
    # @param [::Ractor] mailbox
    # @param [::Ractor] result
    #  The ractor the result is handed to, which the task holds it in.
    # @param [Class] runner_class
    # @param [String, nil] id
    # @param [String] name
    # @param [Hash, Array, nil] arguments
    # @return [LLM::Function::Ractor::Job]
    def initialize(mailbox, result, runner_class, id, name, arguments, cookie)
      @mailbox = mailbox
      @result = result
      @runner_class = runner_class
      @id = id
      @name = name
      @arguments = arguments
      @cookie = cookie
    end

    ##
    # @return [void]
    def call
      spawn
      wait
    end

    private

    ##
    # The loop owes one thing: the result, handed to the ractor the task
    # holds it in before this one ends. It answers `alive?` while the tool
    # runs, forwards interrupts to the tool, hands the result over, and
    # goes - so a wait cannot arrive at a ractor that is on its way out,
    # which is what asking this one for a result used to do.
    # @return [void]
    def wait
      loop do
        case ::Ractor.receive
        in [:done, *data]
          @result.send(data)
          break
        in [:alive?, reply]
          reply.send(true)
        in [:interrupt]
          interrupt_tool
        end
      end
    end

    ##
    # Forwards an interrupt to the tool's ractor.
    #
    # A tool whose ractor has gone has nothing left to interrupt, and this
    # loop is the thing that owes the result to the ractor the task waits
    # on. A raise here takes the loop with it before the result has been
    # handed over, so that a forward to a ractor that has gone turns the
    # failure that used to name it into a wait that never comes back.
    # @return [nil]
    def interrupt_tool
      @tool&.send(:interrupt)
      nil
    rescue ::Ractor::ClosedError
      nil
    end

    def spawn
      @tool = ::Ractor.new(@mailbox, @runner_class, @id, @name, @arguments, @cookie) do |mailbox, runner_class, id, name, arguments, cookie|
        ##
        # Before the watcher exists, because an interrupt can arrive
        # first: it is a message, and it waits in the inbox until the
        # watcher reads it. The thread the interrupt is raised on is
        # named rather than defaulted, which is what the window asks of
        # a caller: it is `Thread.current`, the ractor's own main
        # thread, and the thread the tool runs on.
        window = LLM::Function::Window.new(thread: ::Thread.current)
        ##
        # The tool is built outside the window, so a raise from
        # `initialize` is not answered as an interrupt, and before the
        # watcher, so that the watcher has something to tell: a ractor
        # cannot be handed the function, and the instance the parent
        # holds is not this one.
        runner = runner_class.new
        ::Thread.new do
          ##
          # Only the receive is guarded: it raises when the ractor this
          # one talks to has gone, and nothing else here should be
          # answerable to that rescue. A hook that raises must not be
          # swallowed by it, and must not take the raise with it either -
          # hence the `ensure` below, which delivers whatever the hook
          # does.
          kind = begin
            ::Ractor.receive
          rescue ::Ractor::Error
            next
          end
          next unless kind == :interrupt
          begin
            ##
            # The tool is told first, so a tool that releases a resource
            # has done so by the time the raise lands on it, and so that
            # a tool which rescues `LLM::Interrupt` reads what its hook
            # wrote.
            LLM::Function.interrupt(runner)
          ensure
            ##
            # The window decides whether the raise is the tool's to
            # handle, or whether the tool has already been and gone.
            window.interrupt!
          end
        end
        ##
        # Everything the call needs is prepared outside the window, so
        # the distance from `running!` to the tool's first instruction is
        # the method dispatch and nothing else.
        kwargs = Hash === arguments ? arguments.transform_keys(&:to_sym) : arguments
        window.running!
        result = runner.call(**kwargs)
        ##
        # The window closes the moment the tool has returned and before
        # the result is written, so an interrupt that arrives once the
        # work is done is a no-op rather than a reason to throw the
        # result away.
        window.finished!
        mailbox.send([:done, id, name, result])
      rescue LLM::Interrupt
        mailbox.send([:done, id, name, {interrupt: true, cookie:}])
      rescue => ex
        mailbox.send([:done, id, name, {error: true, type: ex.class.name, message: ex.message}])
      end
    end
  end
end
