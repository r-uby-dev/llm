# frozen_string_literal: true

class LLM::Console::Command
  ##
  # The 'exit' command exits the interactive console
  # by throwing. The {LLM::Console LLM::Console} class covers
  # the loop with a catch that gracefully recovers and
  # exits the loop.
  class Exit < self
    name "exit"
    description "exits the console"

    ##
    # @return [void]
    def call
      throw(:exit)
    end
  end

  class Quit < Exit
    name "quit"
  end
end
