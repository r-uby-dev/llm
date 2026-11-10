LLM::Eval.new do
  set name: "freebsd-update-eval",
      description: "resolve a kernel version mismatch"

  step "step1.txt"
  freebsd = nil

  setup do
    require_relative "freebsd"
    freebsd = FreeBSD.new
  end

  score do |_agent|
    if not freebsd.diagnosed?
      penalize!(by: 0.5, why: "did not run diagnositics")
    end
    if not freebsd.solved?
      penalize!(by: 0.5, why: "version mismatch not resolved")
    end
  end

  configure do
    agent do
      LLM::Agent.new(
        llm,
        tracer:,
        intercept:,
        tools: [LLM::Tool::Exec]
      )
    end

    tracer do
      LLM::Tracer.multi(
        llm,
        LLM::Eval::Tracer::Console.new(llm, eval: self),
        LLM::Eval::Tracer::JSON.new(llm, eval: self)
      )
    end

    intercept do
      Class.new(LLM::Intercept) do
        define_method(:call) do |function:, **|
          next nil unless function.name == "exec"
          LLM::Function::Return.new(
            function.id,
            function.name,
            freebsd.call([function.arguments[:command], *function.arguments[:arguments]])
          )
        end
      end
    end
  end
end
