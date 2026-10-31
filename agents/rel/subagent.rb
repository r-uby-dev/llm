# frozen_string_literal: true

class SubAgent < LLM::Tool
  name "subagent"
  description "prepare a release with a subagent"
  parameter :version, String, "the version to release"
  parameter :instructions, String, "optional instructions for the subagent"
  required %i[version]

  def call(version:, instructions: nil)
    options = {concurrency: :ractor,
               tracer: LLM::Tracer.pretty(llm, io: $stderr),
               instructions: File.read(prompts["release.md"]),
               tools: LLM::Tool.subclasses}
    subagent = LLM::Agent.new(llm, options)
    res = subagent.talk([
      "release version #{version}",
      instructions
    ].compact)
    {content: res.content}
  end

  private

  def llm
    LLM.deepseek
  end

  def prompts
    {"release.md" => File.join(__dir__, "release.md")}
  end
end
