# frozen_string_literal: true

module LLM::ActiveRecord
  ##
  # The {LLM::ActiveRecord::Agent} class
  # represents the jsonb column belonging
  # to an agent as a SQL view that can be
  # accessed via an ActiveRecord model whose
  # table never materializes in the database.
  class Agent < ActiveRecord::Base
    self.table_name = "llm_agent_context"

    ##
    # The derived table does not exist.
    # There is no schema to load.
    # @api private
    # @return [void]
    def self.load_schema!
      @columns_hash = {}.freeze
    end

    ##
    # @param [ActiveRecord::Base<ActsAsLLM|ActsAsAgent>] record
    #  An agent record.
    # @return [ActiveRecord::Relation]
    def self.for(record:)
      klass      = record.class
      connection = klass.connection
      table      = connection.quote_table_name(klass.table_name)
      options    = klass.llm_plugin_options
      column     = connection.quote_column_name(options.fetch(:data_column))
      usage_sql  = LLM::Usage.fields.map do |field|
        "((#{table}.#{column} -> 'token_usage') ->> '#{field}')::int AS #{field}"
      end.join("\n")
      from(<<~SQL).where(id: record&.id)
        (SELECT #{table}.id                                       AS id,
                (#{table}.#{column} ->> 'context_used')::int      AS context_used,
                (#{table}.#{column} ->> 'context_window')::int    AS context_window,
                #{usage_sql}
         FROM #{table})
         AS llm_agent_context
      SQL
    end
  end
end
