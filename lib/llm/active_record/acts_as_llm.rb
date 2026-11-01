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
        __context__.talk(...)
      end

      ##
      # Continues the stored context with new input.
      #
      # The conversation is saved by {LLM::Step LLM::Step} at each request.
      # @see LLM::Context#ask
      # @return [LLM::Response]
      def ask(...)
        __context__.ask(...)
      end

      ##
      # Waits for queued tool work to finish.
      # @see LLM::Context#wait
      # @return [Array<LLM::Function::Return>]
      def wait(...)
        __context__.wait(...)
      end

      ##
      # @see LLM::Context#mode
      # @return [Symbol]
      def mode
        __context__.mode
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
            __context__.messages
          end
        end
      end

      ##
      # Returns the messages the runtime holds
      # @see LLM::Context#messages
      # @return [LLM::Buffer]
      def messages!
        __context__.messages
      end

      ##
      # @see LLM::Context#model
      # @return [String]
      def model!
        __context__.model
      end

      ##
      # @see LLM::Context#pending_functions
      # @return [Array<LLM::Function>]
      def pending_functions
        __context__.pending_functions
      end

      ##
      # @see LLM::Context#pending_functions?
      # @return [Boolean]
      def pending_functions?
        __context__.pending_functions?
      end

      ##
      # @see LLM::Context#returns
      # @return [Array<LLM::Function::Return>]
      def returns
        __context__.returns
      end

      ##
      # @see LLM::Context#cost
      # @return [LLM::Cost]
      def cost
        __context__.cost
      end

      ##
      # Returns the overall size of the context window.
      # @see LLM::Context#context_window
      # @return [Integer, nil]
      def context_window
        if defined?(@context_window)
          @context_window
        else
          @context_window = begin
            options = self.class.llm_plugin_options
            if options[:format] == :jsonb
              __agent__.context_window
            else
              __context__.context_window
            end
          end
        end
      end

      ##
      # Returns how many tokens have been used.
      # @see LLM::Context#context_used
      # @return [Integer, nil]
      def context_used
        if defined?(@context_used)
          @context_used
        else
          @context_used = begin
            options = self.class.llm_plugin_options
            if options[:format] == :jsonb
              __agent__.context_used
            else
              __context__.context_used
            end
          end
        end
      end

      ##
      # Returns context window usage as a Rational
      # @return [Rational, nil]
      def context_usage
        if defined?(@context_usage)
          @context_usage
        else
          @context_usage = begin
            if [context_used, context_window].any?(&:nil?)
              nil
            else
              Rational(context_used, context_window)
            end
          end
        end
      end

      ##
      # Returns the accumulated token usage
      # @see LLM::Context#token_usage
      # @return [LLM::Usage]
      def token_usage
        if defined?(@token_usage)
          @token_usage
        else
          @token_usage = begin
            options = self.class.llm_plugin_options
            if options[:format] == :jsonb
              agent  = __agent__
              fields = LLM::Usage.fields.to_h { [_1.to_sym, agent.public_send(_1)] }
              LLM::Usage.new(**fields.transform_values { _1 || 0 })
            else
              __context__.token_usage
            end
          end
        end
      end
      alias_method :usage, :token_usage

      ##
      # @see LLM::Context#interrupt!
      # @return [nil]
      def interrupt!
        __context__.interrupt!
      end
      alias_method :cancel!, :interrupt!

      ##
      # @see LLM::Context#prompt
      # @return [LLM::Prompt]
      def prompt(&)
        __context__.prompt(&)
      end
      alias_method :build_prompt, :prompt

      ##
      # @see LLM::Context#image_url
      # @return [LLM::Object]
      def image_url(...)
        __context__.image_url(...)
      end

      ##
      # @see LLM::Context#local_file
      # @return [LLM::Object]
      def local_file(...)
        __context__.local_file(...)
      end

      ##
      # @see LLM::Context#remote_file
      # @return [LLM::Object]
      def remote_file(...)
        __context__.remote_file(...)
      end

      ##
      # @see LLM::Context#tracer
      # @return [LLM::Tracer]
      def tracer
        __context__.tracer
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
        __context__
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
      def __context__
        if defined?(@__context__)
          @__context__
        else
          @__context__ = begin
            options = self.class.llm_plugin_options
            columns = Utils.columns(options)
            params = Utils.resolve_options(self, options[:context], EMPTY_HASH).dup
            context = LLM::Context.new(llm, params.compact.merge(record: self))
            data = self[columns[:data_column]]
            if data.nil? || data == ""
              context
            else
              case options[:format]
              when :string then context.restore(string: data)
              when :json, :jsonb then context.restore(data:)
              else raise ArgumentError, "Unknown format: #{options[:format].inspect}"
              end
            end
          end
        end
      end

      ##
      # @return [LLM::ActiveRecord::Agent]
      def __agent__
        if defined?(@__agent__)
          @__agent__
        else
          @__agent__ = LLM::ActiveRecord::Agent.for(record: self)
        end
      end
    end
  end
end

# @!parse ::ActiveRecord::Base.extend(LLM::ActiveRecord::ActsAsLLM)
::ActiveRecord::Base.extend(LLM::ActiveRecord::ActsAsLLM)
