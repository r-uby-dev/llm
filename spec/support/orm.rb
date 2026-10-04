# frozen_string_literal: true

module LLM::Test
  class Runtime
    attr_reader :messages, :usage

    def initialize
      @messages = []
      @usage = LLM::Usage.zero
      @talk_result = Object.new
      @ask_result = Object.new
    end

    def talk(message)
      @messages << LLM::Message.new("user", message)
      @talk_result
    end

    def ask(message)
      @messages << LLM::Message.new("user", message)
      @ask_result
    end

    def talk_result
      @talk_result
    end

    def ask_result
      @ask_result
    end
  end

  ##
  # A record, as far as a context is concerned: a bound object is asked
  # for an id, and nothing else about it is a context's business.
  Record = Struct.new(:id)

  module Harness
    module_function

    def postgres_url
      ENV["LLMRB_POSTGRESQL_URL"]
    end

    def postgres_available?
      postgres_unavailable_reason.nil?
    end

    def postgres_unavailable_reason
      return "LLMRB_POSTGRESQL_URL is not configured" unless postgres_url
      require "pg"
      conn = ::PG.connect(postgres_url)
      conn.close
      nil
    rescue LoadError
      "pg is not installed"
    rescue ::PG::Error => ex
      "PostgreSQL is unavailable: #{ex.message.lines.first.strip}"
    rescue StandardError => ex
      "PostgreSQL is unavailable: #{ex.message}"
    end

    def active_record_base(adapter = :sqlite)
      const_name = {
        sqlite: :ActiveRecordSQLiteBase,
        postgres: :ActiveRecordPostgresBase
      }.fetch(adapter) { raise ArgumentError, "Unknown ActiveRecord adapter: #{adapter.inspect}" }
      return const_get(const_name) if const_defined?(const_name, false)
      klass = const_set(const_name, Class.new(::ActiveRecord::Base))
      klass.abstract_class = true
      case adapter
      when :sqlite
        klass.establish_connection(adapter: "sqlite3", database: ":memory:")
      when :postgres
        klass.establish_connection(postgres_url)
      end
      klass
    end

    def active_record_connection(adapter = :sqlite)
      active_record_base(adapter).connection
    end

    def create_active_record_table(name, adapter: :sqlite, jsonb: false)
      conn = active_record_connection(adapter)
      return if conn.data_source_exists?(name)
      conn.create_table(name) do |t|
        t.string :provider
        t.string :model
        jsonb ? t.jsonb(:data) : t.text(:data)
        t.integer :input_tokens
        t.integer :output_tokens
        t.integer :total_tokens
      end
    end

    def build_active_record_model(name, adapter: :sqlite, jsonb: false, &block)
      create_active_record_table(name, adapter:, jsonb:)
      Class.new(active_record_base(adapter)) do
        self.table_name = name.to_s
        class_eval(&block) if block
      end
    end

    def sequel_db(adapter = :sqlite)
      @sequel_dbs ||= {}
      @sequel_dbs[adapter] ||= case adapter
      when :sqlite then ::Sequel.sqlite
      when :postgres then ::Sequel.connect(postgres_url)
      else raise ArgumentError, "Unknown Sequel adapter: #{adapter.inspect}"
      end
    end

    def create_sequel_table(name, adapter: :sqlite, jsonb: false)
      db = sequel_db(adapter)
      return if db.table_exists?(name)
      db.create_table(name) do
        primary_key :id
        String :provider
        String :model
        if jsonb
          column :data, "jsonb"
        else
          String :data, text: true
        end
        Integer :input_tokens
        Integer :output_tokens
        Integer :total_tokens
      end
    end

    def build_sequel_model(name, adapter: :sqlite, jsonb: false, &block)
      create_sequel_table(name, adapter:, jsonb:)
      Class.new(::Sequel::Model(sequel_db(adapter)[name])) do
        class_eval(&block) if block
      end
    end
  end
end
