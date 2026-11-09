# frozen_string_literal: true

class LLM::Console::Command
  ##
  # The 'keep' command frees space in the
  # context window and llm.rb is designed to
  # support multiple compaction strategies with
  # different trade offs. This command, though,
  # uses the 'truncate' strategy. See
  # {LLM::Compactor::Truncate LLM::Compactor::Truncate}
  # for more details.
  class Keep < self
    name "keep"
    description "free space in the context window"
    parameter :n, String, "the number of messages to keep\n" \
                          "it can also be given as a percentage."
    required %i[n]

    ##
    # @return [void]
    def call(n:)
      write "keep in progress"
      compactor.call(keep: n)
      write "keep complete"
    end

    private

    ##
    # @return [LLM::Compactor::Truncate]
    def compactor
      @compactor ||= LLM::Compactor::Truncate.new(agent)
    end
  end
end
