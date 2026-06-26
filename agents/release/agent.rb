# frozen_string_literal: true

require "llm"
require "test/cmd"

Dir[File.join(__dir__, "tools", "*.rb")].sort.each { require(_1) }

class Agent < LLM::Agent
  skills(__dir__)
  concurrency :thread
  stream { Stream.new }

  def initialize(llm, params = {})
    super(llm, params)
  end

  def release!(version:)
    talk("Prepare the release for llm.rb #{version}")
  end
end

class Stream < LLM::Stream
  def on_content(content)
    $stdout << content
  end

  def on_tool_call(tool, error)
    puts "[tool] call #{tool.name} (error=#{error})"
  end

  def on_tool_return(tool, result)
    puts "[tool] return #{tool.name}"
  end
end

def main(_argv)
  print "target: "
  version = gets.chomp
  version = "v#{version}" unless version[0] == "v"
  print "Does #{version} look right to you [y/n]: "
  if gets.chomp.downcase[0] == "y"
    llm = LLM.deepseek(key: ENV["DEEPSEEK_SECRET"])
    Agent.new(llm).release!(version:)
  else
    puts "Aborted at user's request"
  end
end

main(ARGV) if $PROGRAM_NAME == __FILE__
