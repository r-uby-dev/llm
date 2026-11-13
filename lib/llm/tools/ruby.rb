# frozen_string_literal: true

class LLM::Tool
  ##
  # The {LLM::Tool::Ruby} class implements a tool that
  # evaluates Ruby code with the `ruby` command. It is
  # a tool an LLM can not use by accident.
  #
  # @note
  #  The evaluated code runs with the permissions of the
  #  process, which is to say it can do anything the
  #  process can do. The code is handed to `ruby -e` and
  #  `-e` only ever takes one argument, so nothing that
  #  follows it can be read as another option.
  class Ruby < self
    name "ruby"
    description "Evaluate Ruby code with the ruby command"
    parameter :code, String, "the Ruby code to evaluate"
    parameter :stdin, String, "data to write to the standard input of the code"
    parameter :timeout, Integer, "the maximum allowed time for the code to run (in seconds)"
    required %i[code]
    defaults stdin: nil, timeout: 60

    ##
    # @param [String] code
    #  The Ruby code to evaluate
    # @param [String, nil] stdin
    #  Data to write to the standard input of the code
    # @param [Integer] timeout
    #  The maximum time to allow the code to run, in seconds
    # @return [Hash]
    def call(code:, stdin: nil, timeout: 60)
      exec(command: "ruby", arguments: [*parse!(code:)], timeout:)
    end

    private

    ##
    # @api private
    def parse!(code:)
      if code.empty?
        raise LLM::Error, "'code' must not be empty"
      else
        ["-e", code]
      end
    end
  end
end
