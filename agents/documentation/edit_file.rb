# frozen_string_literal: true

class EditFile < LLM::Tool
  name "edit-file"
  description "edit a file"
  parameter :file, Enum["CHANGELOG.md"], "the file to edit"
  parameter :instructions, String, "optional instructions for the subagent"
  required %i[file]

  def call(file:, instructions: nil)
    options  = {concurrency: :ractor,
                tracer: LLM::Tracer.pretty(llm, io: $stderr),
                instructions: File.read(prompts[file]),
                tools: [*(LLM::Tool.subclasses - [EditFile])]}
    subagent = LLM::Agent.new(llm, options)
    case file
    when "CHANGELOG.md"
      res = subagent.talk([
        "edit the changelog",
        instructions
      ].compact)
      {content: res.content}
    else
      raise LLM::Error, "'#{file}' is not a valid file"
    end
  end

  private

  def llm
    LLM.deepseek
  end

  def prompts
    {"CHANGELOG.md" => File.join(__dir__, "changelog.md") }
  end
end
