# frozen_string_literal: true

module LLM::Sequel
  ##
  # Sequel plugin for persisting {LLM::Context LLM::Context} state.
  #
  # This plugin maps model columns onto provider selection, model
  # selection, usage accounting, and serialized context data while
  # leaving application-specific concerns such as credentials,
  # associations, and UI shaping to the host app.
  #
  # Context state can be stored as a JSON string (`format: :string`, the
  # default) or as a structured object (`format: :json` / `:jsonb`) for
  # databases such as PostgreSQL that can persist JSON natively.
  # `:json` and `:jsonb` expect a real JSON column type with Sequel handling
  # JSON typecasting for the model. `provider:`, `context:`, and `tracer:`
  # can also be configured as symbols that are called on the model.
  module Plugin
    DEFAULTS = {
      data_column: :data,
      format: :string,
      provider: :set_provider,
      context: :set_context,
      tracer: :set_tracer
    }.freeze
    EMPTY_HASH = {}.freeze

    ##
    # Shared helper methods for the ORM wrapper.
    #
    # These utilities keep persistence plumbing out of the wrapped model's
    # method namespace so the injected surface stays focused on the runtime
    # API itself.
    # @api private
    module Utils
      ##
      # Resolves a single configured option against a model instance.
      # @return [Object]
      def self.resolve_option(obj, option)
        LLM::Utils.resolve_option(obj, option)
      end

      ##
      # Resolves hash-like wrapper options against a model instance.
      # @return [Hash]
      def self.resolve_options(obj, option, empty_hash)
        case option
        when Proc, Symbol, Hash then resolve_option(obj, option)
        else empty_hash.dup
        end
      end

      ##
      # Serializes the runtime into the configured storage format.
      # @return [String, Hash]
      def self.serialize_context(ctx, format)
        case format
        when :string then ctx.to_json
        when :json, :jsonb then ctx.to_h
        else raise ArgumentError, "Unknown format: #{format.inspect}"
        end
      end

      ##
      # Maps wrapper options onto the record's storage columns.
      # @return [Hash]
      def self.columns(options)
        {
          data_column: options[:data_column]
        }.freeze
      end

      ##
      # Resolves the provider runtime for a record.
      # @return [LLM::Provider]
      def self.resolve_provider(obj, options, empty_hash)
        provider = resolve_option(obj, options[:provider])
        return provider if LLM::Provider === provider
        raise ArgumentError, "provider: must resolve to an LLM::Provider instance"
      end

      ##
      # Persists the runtime state and usage columns back onto the record.
      # @return [void]
      def self.save!(obj, ctx, options)
        columns = self.columns(options)
        payload = serialize_context(ctx, options[:format])
        payload = wrap_json_payload(payload, options[:format])
        obj[columns[:data_column]] = payload
        obj.save_changes(raise_on_failure: true)
      end

      ##
      # Wraps JSON payloads for Sequel PostgreSQL adapters when needed.
      # @return [Object]
      def self.wrap_json_payload(payload, format)
        case format
        when :json then Sequel.pg_json_wrap(payload)
        when :jsonb then Sequel.pg_jsonb_wrap(payload)
        else payload
        end
      end
    end

    ##
    # Called by Sequel when the plugin is first applied to a model class.
    #
    # This hook installs the plugin's class- and instance-level behavior on
    # the target model. It runs before {configure}, so it should only attach
    # methods and not depend on per-model plugin options.
    #
    # @param [Class] model
    # @return [void]
    def self.apply(model, **)
      model.extend ClassMethods
      model.include InstanceMethods
    end

    ##
    # Called by Sequel after {apply} with the options passed to
    # `plugin :llm, ...`.
    #
    # This hook merges plugin defaults with the model's explicit settings and
    # stores the resolved configuration on the model class for later use by
    # instance methods such as {InstanceMethods#llm} and {InstanceMethods#ctx}.
    #
    # @param [Class] model
    # @param [Hash] options
    # @option options [Symbol] :format
    #   Storage format for the serialized context. Use `:string` for text
    #   columns, or `:json` / `:jsonb` for structured JSON columns with Sequel
    #   JSON typecasting enabled.
    # @option options [Proc, Symbol, LLM::Tracer, nil] :tracer
    #   Optional tracer, method name, or proc that resolves to one and is
    #   assigned through `llm.tracer = ...` on the resolved provider.
    # @option options [Proc, Symbol, LLM::Provider] :provider
    #   Must resolve to an `LLM::Provider` instance for the current record.
    # @return [void]
    def self.configure(model, options = EMPTY_HASH)
      options = DEFAULTS.merge(options)
      model.db.extension :pg_json if %i[json jsonb].include?(options[:format])
      model.instance_variable_set(:@llm_plugin_options, options.freeze)
    end
  end

  module Plugin::ClassMethods
    ##
    # @return [Hash]
    def llm_plugin_options
      @llm_plugin_options || Plugin::DEFAULTS
    end
  end

  module Plugin::InstanceMethods
    Utils = Plugin::Utils

    ##
    # Continues the stored context with new input and flushes it.
    # @see LLM::Context#talk
    # @return [LLM::Response]
    def talk(...)
      options = self.class.llm_plugin_options
      ctx.talk(...).tap { Utils.save!(self, ctx, options) }
    end

    ##
    # Continues the stored context with new input and flushes it.
    # @see LLM::Context#ask
    # @return [LLM::Response]
    def ask(...)
      options = self.class.llm_plugin_options
      ctx.ask(...).tap { Utils.save!(self, ctx, options) }
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
    # @see LLM::Context#messages
    # @return [Array<LLM::Message>]
    def messages
      ctx.messages
    end

    ##
    # @note The bang is used because Sequel reserves `model` for the
    #   underlying model class on instances.
    # @see LLM::Context#model
    # @return [String]
    def model!
      ctx.model
    end

    ##
    # @see LLM::Context#functions
    # @return [Array<LLM::Function>]
    def functions
      ctx.functions
    end

    ##
    # @see LLM::Context#functions?
    # @return [Boolean]
    def functions?
      ctx.functions?
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
    # @see LLM::Context#context_window
    # @return [Integer]
    def context_window
      ctx.context_window
    rescue LLM::NoSuchModelError, LLM::NoSuchRegistryError
      0
    end

    ##
    # Returns usage from the mapped usage columns.
    # @return [LLM::Object]
    def usage
      ctx.usage || LLM::Object.from(input_tokens: 0, output_tokens: 0, total_tokens: 0)
    end

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
      @llm = Utils.resolve_provider(self, options, Plugin::EMPTY_HASH)
      @llm.tracer = Utils.resolve_option(self, options[:tracer]) if options[:tracer]
      @llm
    end

    private

    ##
    # @return [LLM::Provider]
    def set_provider
      raise NotImplementedError, "implement the set_provider callback"
    end

    ##
    # @return [Hash]
    def set_context
      Plugin::EMPTY_HASH.dup
    end

    ##
    # @return [LLM::Tracer]
    def set_tracer
      nil
    end

    ##
    # @return [LLM::Context]
    def ctx
      @ctx ||= begin
        options = self.class.llm_plugin_options
        columns = Utils.columns(options)
        params = Utils.resolve_options(self, options[:context], Plugin::EMPTY_HASH).dup
        ctx = LLM::Context.new(llm, params.compact)
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
