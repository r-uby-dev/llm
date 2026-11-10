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
    parameter :newline, Boolean, "insert final newline (yes or no)"
    required %i[path content]
    defaults newline: true

    ##
    # @param [String] path
    # @param [String] content
    # @return [Hash]
    def call(path:, content:, newline: true)
      content = content.end_with?("\n") ? content : "#{content}\n" if newline
      File.open(path, "w") { _1.write(content) }
      {ok: true}
    end
  end
end
