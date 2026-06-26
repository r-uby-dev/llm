# frozen_string_literal: true

class ReadFile < LLM::Tool
  name "read-file"
  description "Read the contents of a file"
  parameter :path, String, "The file path"
  parameter :limit, Integer, "Optional maximum number of lines to read"
  required %i[path]

  def call(path:, limit: nil)
    out = if limit
      File.readlines(path).first(limit.to_i).join
    else
      File.read(path)
    end
    {ok: true, out:}
  end
end
