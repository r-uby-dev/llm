# frozen_string_literal: true

class LLM::Console
  class Help < Command
    name "help"
    description "show help for a given command"
    parameter :name, String, "The name of a command"

    ##
    # @param [String] name
    # @return [void]
    def call(name: nil)
      if name.nil?
        write(self.class.help)
      elsif command = LLM::Command.find_by(name:)
        write(command.help)
      else
        write "no help for #{name} was found"
      end
    end
  end
end
