# frozen_string_literal: true

class LLM::Tool
  ##
  # The {LLM::Tool::WriteFile LLM::Tool::WriteFile} class
  # implements a tool that can write a given string to a
  # given file path.
  class WriteFile < self
    name "write-file"
    description "write to a file"
    parameter :path, String, "The file path"
    parameter :content, String, "The file content"
    required %i[path content]

    ##
    # @param [String] path
    # @param [String] content
    # @return [Hash]
    def call(path:, content:)
      content = content.end_with?("\n") ? content : "#{content}\n"
      File.open(path, "w") { _1.write(content) }
      {ok: true}
    end
  end
end
