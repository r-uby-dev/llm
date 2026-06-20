# frozen_string_literal: true

module LLM
  ##
  # The {LLM::Stream LLM::Stream} class provides the callback interface for
  # streamed model output in llm.rb.
  #
  # A stream object can be an instance of {LLM::Stream LLM::Stream} or a
  # subclass that overrides the callbacks it needs. For basic streaming,
  # llm.rb also accepts any object that implements `#<<`. {#queue} provides
  # a small helper for collecting asynchronous tool work started from a
  # callback.
  #
  # @note The `on_*` callbacks run inline with the streaming parser. They
  #   therefore block streaming progress and should generally return as
  #   quickly as possible.
  #
  # The most common callback is {#on_content}, which also maps to `#<<`.
  # Providers may also call {#on_reasoning_content} and {#on_tool_call} when
  # that data is available. Runtime features such as context compaction may
  # also emit lifecycle callbacks like {#on_transform} or {#on_compaction}.
  class Stream
    require_relative "stream/queue"

    ##
    # Returns extra context associated with the current streamed request.
    # @return [Hash]
    def extra
      @extra ||= LLM::Object.from({})
    end

    ##
    # Returns the current context, if one was attached to the stream.
    # @return [LLM::Context, nil]
    def ctx
      extra[:ctx]
    end

    ##
    # Returns a lazily-initialized queue for tool results or spawned work.
    # @return [LLM::Stream::Queue]
    def queue
      @queue ||= Queue.new(self)
    end

    ##
    # Waits for queued tool work to finish and returns function results.
    # Any passed arguments are ignored because queued work is waited according
    # to the actual task types already present in the queue.
    # @return [Array<LLM::Function::Return>]
    def wait(*)
      queue.wait
    end

    # @group Public callbacks

    ##
    # Called when visible assistant output is streamed.
    # @param [String] content
    #  A chunk of assistant-visible text.
    # @return [nil]
    def on_content(content)
      nil
    end
    alias_method :<<, :on_content

    ##
    # Called when reasoning output is streamed separately from visible content.
    # @param [String] content
    #  A chunk of reasoning text.
    # @return [nil]
    def on_reasoning_content(content)
      nil
    end

    ##
    # Called when a streamed tool call has been fully constructed.
    # @note A stream implementation may start tool execution here, for
    #   example by pushing `ctx.spawn(tool, :thread)`,
    #   `ctx.spawn(tool, :fiber)`, or `ctx.spawn(tool, :task)` onto {#queue}.
    #   Mixed strategies can also be selected per tool, such as
    #   `tool.mcp? ? ctx.spawn(tool, :task) : ctx.spawn(tool, :ractor)`.
    #   When a streamed tool cannot be resolved, `error` is passed as an
    #   {LLM::Function::Return}. It can be sent back to the model, allowing
    #   the tool-call path to recover and the session to continue. Streamed
    #   tool resolution now prefers the current request tools, so
    #   {LLM.function}, MCP tools, bound tool instances, and normal
    #   {LLM::Tool LLM::Tool} classes can all resolve through the same
    #   request-local path. The current `:ractor` mode is for class-based
    #   tools and does not support MCP tools.
    # @param [LLM::Function] tool
    #  The parsed tool call.
    # @param [LLM::Function::Return, nil] error
    #  An in-band tool error for unresolved tool calls.
    # @return [nil]
    def on_tool_call(tool, error)
      nil
    end

    ##
    # Called when queued streamed tool work returns.
    # @note This callback runs when {#wait} resolves work that was queued from
    #   {#on_tool_call}, such as values returned by `ctx.spawn(tool, :thread)`,
    #   `ctx.spawn(tool, :fiber)`, or `ctx.spawn(tool, :task)`.
    # @param [LLM::Function] tool
    #  The tool that returned.
    # @param [LLM::Function::Return] result
    #  The completed tool return.
    # @return [nil]
    def on_tool_return(tool, result)
      nil
    end

    ##
    # Called before a context transformer rewrites a prompt.
    # @param [LLM::Context] ctx
    # @param [#call] transformer
    # @return [nil]
    def on_transform(ctx, transformer)
      nil
    end

    ##
    # Called after a context transformer finishes rewriting a prompt.
    # @param [LLM::Context] ctx
    # @param [#call] transformer
    # @return [nil]
    def on_transform_finish(ctx, transformer)
      nil
    end

    ##
    # Called before a context compaction starts.
    # @param [LLM::Context] ctx
    # @param [LLM::Compactor] compactor
    # @return [nil]
    def on_compaction(ctx, compactor)
      nil
    end

    ##
    # Called after a context compaction finishes.
    # @param [LLM::Context] ctx
    # @param [LLM::Compactor] compactor
    # @return [nil]
    def on_compaction_finish(ctx, compactor)
      nil
    end

    # @endgroup

    # @group Finders

    ##
    # Resolves a streamed tool call against the current request tools first,
    # then falls back to the global function registry.
    # @param [String] name
    # @return [LLM::Function, nil]
    def __find__(name)
      tools = extra[:tools] || ctx&.params&.dig(:tools) || []
      tool = tools.find do
        candidate = _1.respond_to?(:function) ? _1.function.name : _1.name
        candidate.to_s == name.to_s
      end
      if tool
        tool.respond_to?(:function) ? tool.function : tool
      else
        LLM::Function.find_by_name(name)
      end
    end

    # @endgroup
  end
end
