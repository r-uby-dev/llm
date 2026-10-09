# frozen_string_literal: true

module LLM
  ##
  # The {LLM::Tracer::Logger LLM::Tracer::Logger} class provides a
  # tracer that provides logging facilities through Ruby's
  # standard library.
  #
  # @example
  #   llm = LLM.openai(key: ENV["KEY"])
  #   # Log to a file
  #   llm.tracer = LLM::Tracer.logger(llm, path: "/tmp/log.txt")
  #   # Log to $stdout (default)
  #   llm.tracer = LLM::Tracer.logger(llm, io: $stdout)
  class Tracer::Logger < Tracer
    ##
    # @param (see LLM::Tracer#initialize)
    def initialize(provider, options = {})
      super
      setup!(**options)
    end

    ##
    # @param (see LLM::Tracer#on_request_start)
    # @return [void]
    def on_request_start(operation:, model: nil, **)
      case operation
      when "chat" then start_chat(operation:, model:)
      when "retrieval" then start_retrieval(operation:)
      else nil
      end
    end

    ##
    # @param (see LLM::Tracer#on_request_finish)
    # @return [void]
    def on_request_finish(operation:, res:, model: nil, **)
      case operation
      when "chat" then finish_chat(operation:, res:, model:)
      when "retrieval" then finish_retrieval(operation:, res:)
      else nil
      end
    end

    ##
    # @param (see LLM::Tracer#on_request_error)
    # @return [void]
    def on_request_error(ex:, **)
      @logger.error(
        tracer: "llm.rb (logger)",
        event: "request.error",
        provider: provider_name,
        error_class: ex.class.to_s,
        error_message: ex.message
      )
    end

    ##
    # @note An "ending" describes the method
    #  that matches the end of a tool call, and it can be one of:
    #  on_tool_finish, on_tool_error or on_tool_interrupt.
    # @param (see LLM::Tracer#on_tool_start)
    # @return [LLM::Object]
    #  The span an ending is handed, with the call's id and name
    def on_tool_start(id:, name:, arguments:, model:, **)
      @logger.info(
        tracer: "llm.rb (logger)",
        event: "tool.start",
        provider: provider_name,
        operation: "execute_tool",
        tool_id: id,
        tool_name: name,
        tool_arguments: arguments,
        model:
      )
      LLM::Object.from(id:, name:)
    end

    ##
    # @param (see LLM::Tracer#on_tool_finish)
    # @return [void]
    def on_tool_finish(result:, **)
      @logger.info(
        tracer: "llm.rb (logger)",
        event: "tool.finish",
        provider: provider_name,
        operation: "execute_tool",
        tool_id: result.id,
        tool_name: result.name,
        tool_result: result.value
      )
    end

    ##
    # @param (see LLM::Tracer#on_tool_error)
    # @return [void]
    def on_tool_error(ex:, **)
      @logger.error(
        tracer: "llm.rb (logger)",
        event: "tool.error",
        provider: provider_name,
        operation: "execute_tool",
        error_class: ex.class.to_s,
        error_message: ex.message
      )
    end

    private

    ##
    # @api private
    def setup!(path: nil, io: $stdout)
      require "logger" unless defined?(::Logger)
      @logger = ::Logger.new(path || io)
    end

    ##
    # @param [String] operation
    # @param [LLM::Response] res
    # @api private
    def finish_attributes(operation, res)
      case @llm.class.to_s
      when "LLM::OpenAI" then openai_attributes(operation, res)
      else {}
      end
    end

    ##
    # @param [String] operation
    # @param [LLM::Response] res
    # @api private
    def openai_attributes(operation, res)
      case operation
      when "chat"
        {
          openai_service_tier: res.service_tier,
          openai_system_fingerprint: res.system_fingerprint
        }.compact
      when "retrieval"
        {
          openai_vector_store_search_result_count: res.size,
          openai_vector_store_search_has_more: res.has_more
        }.compact
      else {}
      end
    end

    ##
    # start_*

    def start_chat(operation:, model:)
      @logger.info(
        tracer: "llm.rb (logger)",
        event: "request.start",
        provider: provider_name,
        operation:,
        model:
      )
    end

    def start_retrieval(operation:)
      @logger.info(
        tracer: "llm.rb (logger)",
        event: "request.start",
        provider: provider_name,
        operation:
      )
    end

    ##
    # finish_*

    def finish_chat(operation:, model:, res:)
      @logger.info(
        tracer: "llm.rb (logger)",
        event: "request.finish",
        provider: provider_name,
        operation:,
        model:,
        response_id: res.id,
        input_tokens: res.usage.input_tokens,
        output_tokens: res.usage.output_tokens,
        **finish_attributes(operation, res)
      )
    end

    def finish_retrieval(operation:, res:)
      @logger.info(
        tracer: "llm.rb (logger)",
        event: "request.finish",
        provider: provider_name,
        operation:,
        **finish_attributes(operation, res)
      )
    end

    ##
    # @param (see LLM::Tracer#set_finish_metadata_proc)
    # @return [self]
    def set_finish_metadata_proc(_proc = nil)
      Thread.current[LLM::Tracer::FINISH_METADATA_PROC_KEY] = nil
      self
    end
  end
end
