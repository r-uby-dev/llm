# frozen_string_literal: true

module LLM::ActiveRecord
  ##
  # The {LLM::ActiveRecord::Message} class
  # represents messages from the jsonb column
  # belonging to an agent as a SQL view that
  # can be accessed via an ActiveRecord model
  # whose table never materializes in the database.
  class Message < ActiveRecord::Base
    self.table_name = "llm_agent_messages"

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
      from(<<~SQL).where(agent_id: record&.id)
        (SELECT #{table}.id                AS agent_id,
                (message ->> 'id')         AS id,
                (message ->> 'role')       AS role,
                (message ->> 'content')    AS content,
                (message -> 'tools')       AS tools,
                ordinality                 AS position,
                message                    AS data
         FROM #{table},
              jsonb_array_elements(#{table}.#{column} -> 'messages')
                WITH ORDINALITY AS each(message, ordinality))
          AS llm_agent_messages
      SQL
    end

    ##
    # @return (see LLM::Message#tool_call?)
    def tool_call?
      unwrap!.tool_call?
    end

    ##
    # @return (see LLM::Message#tool_return?)
    def tool_return?
      unwrap!.tool_return?
    end

    ##
    # @return [LLM::Message]
    def unwrap!
      @message ||= begin
        stored = Hash === data ? data : {}
        extra = stored.each_with_object({}) { |(key, value), acc| acc[key.to_sym] = value }
        extra[:id] = stored["id"] || id
        extra[:role] ||= role
        extra[:content] ||= content
        extra[:tool_calls] = stored["tools"] || tools
        LLM::Message.new(extra[:role], extra[:content], extra)
      end
    end
  end
end
