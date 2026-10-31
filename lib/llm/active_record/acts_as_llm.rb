# frozen_string_literal: true

# @!parse
#   module ::ActiveRecord
#     class Base
#     end
#   end

module LLM::ActiveRecord
  ##
  # ActiveRecord integration for persisting {LLM::Context LLM::Context} state.
  #
  # This wrapper maps model columns onto provider selection, model selection,
  # usage accounting, and serialized context data while leaving application-
  # specific concerns such as credentials, associations, and UI shaping to
  # the host app.
  #
  # Context state can be stored as a JSON string (`format: :string`, the
  # default) or as a structured object (`format: :json` / `:jsonb`) for
  # databases such as PostgreSQL that can persist JSON natively.
  # `:json` and `:jsonb` expect a real JSON column type with ActiveRecord
  # handling JSON typecasting for the model.
  #
  # The model implements `set_provider` (required) and `set_context`
  # (optional), and the wrapper resolves them by name. A tracer is not one of
  # those callbacks: give it to `acts_as_llm` as `tracer:` - a tracer, a proc,
  # or a method name - and only then is it assigned to the provider.
  module ActsAsLLM
    module Hooks
      ##
      # Called when hooks are extended onto an ActiveRecord model.
      #
      # @param [Class] model
      # @return [void]
      def self.extended(model)
        model.include InstanceMethods unless model.ancestors.include?(InstanceMethods)
      end
    end

    ##
    # Installs the `acts_as_llm` wrapper on an ActiveRecord model.
    #
    # @param [Hash] options
    # @option options [Symbol] :format
    #   Storage format for the serialized context. Use `:string` for text
    #   columns, or `:json` / `:jsonb` for structured JSON columns with
    #   ActiveRecord JSON typecasting enabled.
    # @option options [Proc, Symbol, LLM::Tracer, nil] :tracer
    #   Optional tracer, method name, or proc that resolves to one and is
    #   assigned through `llm.tracer = ...` on the resolved provider. There is
    #   no `set_tracer` callback: a tracer is given here, or not at all.
    # @option options [Proc, Symbol, LLM::Provider] :provider
    #   Must resolve to an `LLM::Provider` instance for the current record.
    # @return [void]
    def acts_as_llm(options = EMPTY_HASH)
      options = DEFAULTS.merge(options)
      class_attribute :llm_plugin_options, instance_accessor: false, default: DEFAULTS unless respond_to?(:llm_plugin_options)
      self.llm_plugin_options = options.freeze
      extend Hooks
    end

    module InstanceMethods
      ##
      # Continues the stored context with new input.
      #
      # The conversation is saved by {LLM::Step LLM::Step} at each request.
      # @see LLM::Context#talk
      # @return [LLM::Response]
      def talk(...)
        ctx.talk(...)
      end

      ##
      # Continues the stored context with new input.
      #
      # The conversation is saved by {LLM::Step LLM::Step} at each request.
      # @see LLM::Context#ask
      # @return [LLM::Response]
      def ask(...)
        ctx.ask(...)
      end

      ##
      # Waits for queued tool work to finish.
      # @see LLM::Context#wait
      # @return [Array<LLM::Function::Return>]
      def wait(...)
        ctx.wait(...)
      end

      ##
      # @see LLM::Context#mode
      # @return [Symbol]
      def mode
        ctx.mode
      end

      ##
      # Returns the messages this record holds.
      #
      # @note
      #   A record that stores its state as jsonb
      #   reads them from the column, as a relation:
      #   the conversation can be filtered, counted
      #   and ordered in the database, and nothing here
      #   needs a provider to be built. Every other format
      #   loads the runtime and hands back the messages
      #   it holds.
      #
      # @see LLM::Context#messages
      # @return [ActiveRecord::Relation, LLM::Buffer]
      def messages
        @__messages ||= begin
          options = self.class.llm_plugin_options
          if options[:format] == :jsonb
            LLM::ActiveRecord::Message.for(record: self)
          else
            ctx.messages
          end
        end
      end

      ##
      # Returns the messages the runtime holds
      # @see LLM::Context#messages
      # @return [LLM::Buffer]
      def messages!
        ctx.messages
      end

      ##
      # @see LLM::Context#model
      # @return [String]
      def model!
        ctx.model
      end

      ##
      # @see LLM::Context#pending_functions
      # @return [Array<LLM::Function>]
      def pending_functions
        ctx.pending_functions
      end

      ##
      # @see LLM::Context#pending_functions?
      # @return [Boolean]
      def pending_functions?
        ctx.pending_functions?
      end

      ##
      # @see LLM::Context#returns
      # @return [Array<LLM::Function::Return>]
      def returns
        ctx.returns
      end

      ##
      # @see LLM::Context#cost
      # @return [LLM::Cost]
      def cost
        ctx.cost
      end

      ##
      # Returns the overall size of the context window.
      # @see LLM::Context#context_window
      # @return [Integer, nil]
      def context_window
        @__context_window ||= begin
          options = self.class.llm_plugin_options
          if options[:format] == :jsonb
            agent = LLM::ActiveRecord::Agent.for(record: self)
            agent.context_window
          else
            ctx.context_window
          end
        end
      end

      ##
      # Returns how many tokens have been used.
      # @see LLM::Context#context_used
      # @return [Integer, nil]
      def context_used
        @__context_used ||= begin
          options = self.class.llm_plugin_options
          if options[:format] == :jsonb
            agent = LLM::ActiveRecord::Agent.for(record: self)
            agent.context_used
          else
            ctx.context_used
          end
        end
      end

      ##
      # Returns context window usage as a Rational
      # @return [Rational, nil]
      def context_usage
        ctx.context_usage
      end

      ##
      # Returns usage from the mapped usage columns.
      # @return [LLM::Usage]
      def token_usage
        ctx.token_usage
      end
      alias_method :usage, :token_usage

      ##
      # @see LLM::Context#interrupt!
      # @return [nil]
      def interrupt!
        ctx.interrupt!
      end
      alias_method :cancel!, :interrupt!

      ##
      # @see LLM::Context#prompt
      # @return [LLM::Prompt]
      def prompt(&)
        ctx.prompt(&)
      end
      alias_method :build_prompt, :prompt

      ##
      # @see LLM::Context#image_url
      # @return [LLM::Object]
      def image_url(...)
        ctx.image_url(...)
      end

      ##
      # @see LLM::Context#local_file
      # @return [LLM::Object]
      def local_file(...)
        ctx.local_file(...)
      end

      ##
      # @see LLM::Context#remote_file
      # @return [LLM::Object]
      def remote_file(...)
        ctx.remote_file(...)
      end

      ##
      # @see LLM::Context#tracer
      # @return [LLM::Tracer]
      def tracer
        ctx.tracer
      end

      ##
      # Returns the resolved provider instance for this record.
      # @return [LLM::Provider]
      def llm
        options = self.class.llm_plugin_options
        return @llm if @llm
        @llm = Utils.resolve_provider(self, options, EMPTY_HASH)
        @llm.tracer = Utils.resolve_option(self, options[:tracer]) if options[:tracer]
        @llm
      end

      ##
      # Returns the runtime this record wraps: an
      # {LLM::Context LLM::Context} for `acts_as_llm`, and an
      # {LLM::Agent LLM::Agent} for `acts_as_agent`. The runtime is
      # memoized, so every call returns the same object.
      # @return [LLM::Context, LLM::Agent]
      def unwrap!
        ctx
      end

      private

      ##
      # @return [LLM::Provider]
      # @raise [NotImplementedError]
      #  when neither this model nor one of its ancestors implements the
      #  callback
      def set_provider
        return super if defined?(super)
        raise NotImplementedError, "implement the set_provider callback"
      end

      ##
      # @return [Hash]
      def set_context
        return super if defined?(super)
        EMPTY_HASH.dup
      end

      ##
      # @return [LLM::Context]
      def ctx
        @ctx ||= begin
          options = self.class.llm_plugin_options
          columns = Utils.columns(options)
          params = Utils.resolve_options(self, options[:context], EMPTY_HASH).dup
          ctx = LLM::Context.new(llm, params.compact.merge(record: self))
          data = self[columns[:data_column]]
          if data.nil? || data == ""
            ctx
          else
            case options[:format]
            when :string then ctx.restore(string: data)
            when :json, :jsonb then ctx.restore(data:)
            else raise ArgumentError, "Unknown format: #{options[:format].inspect}"
            end
          end
        end
      end
    end
  end
end

# @!parse ::ActiveRecord::Base.extend(LLM::ActiveRecord::ActsAsLLM)
::ActiveRecord::Base.extend(LLM::ActiveRecord::ActsAsLLM)
