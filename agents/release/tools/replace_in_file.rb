# frozen_string_literal: true

class ReplaceInFile < LLM::Tool
  name "replace-in-file"
  description "Replace an exact snippet in a file"
  parameter :path, String, "Path to file"
  parameter :before, String, "Exact text to replace"
  parameter :after, String, "Replacement text"
  parameter :expected_count, Integer, "How many matches should be replaced"
  required %i[path before after]

  def call(path:, before:, after:, expected_count: 1)
    content = File.read(path)
    count = content.scan(before).length
    raise "expected #{expected_count} match(es), found #{count}" unless count == expected_count.to_i
    File.write(path, content.sub(before, after))
    {ok: true, replaced: count}
  end
end
