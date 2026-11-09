# frozen_string_literal: true

module LLM
  ##
  # The {LLM::Eval} class represents an
  # eval for a given provider, and path
  # to an eval.rb file that describes
  # the eval.
  class Eval
    require "llm"
    require "llm/tools"
    require "json"
    require "fileutils"
    require "stringio"
    require "time"
    require_relative "eval/tracer"
    require_relative "eval/run"

    extend FileUtils
    File = ::File

    ##
    # @api private
    UNDEFINED = Object.new

    ##
    # @param [LLM::Provider] llm
    # @param [String] model
    # @param [String] path
    # @return [LLM::Eval]
    def self.from(llm, model, path, sample=1)
      p = File.realpath(path)
      e = eval File.read(p), TOPLEVEL_BINDING, p, 1
      e.instance_variable_set(:@root, File.dirname(p))
      e.instance_variable_set(:@llm, llm)
      e.instance_variable_set(:@model, model)
      e.instance_variable_set(:@sample, sample)
      e
    end

    ##
    # @return [Integer]
    attr_reader :sample

    ##
    # @return [Array<String>]
    attr_reader :steps

    ##
    # @return [LLM::Provider]
    attr_reader :llm

    ##
    # @return [String]
    attr_reader :model

    ##
    # @return [String]
    attr_reader :root

    ##
    # @return [Array<Hash>]
    #  The reasons the score came out below 1.0
    attr_reader :penalties

    ##
    # @param [LLM::Provider] llm
    # @param [Proc] b
    # @return [LLM::Eval]
    def initialize(&b)
      @steps     = []
      @block     = b
      @result    = 1.0
      @final     = nil
      @penalties = []
    end

    ##
    # @param [Hash] options
    # @return [LLM::Eval]
    def set(**options)
      options.each { |key, value| public_send(key, value) }
      self
    end

    ##
    # @return [void]
    def configure(&)
      instance_eval(&)
    end

    ##
    # @param [String, nil] name
    # @return [String, nil]
    def name(name = UNDEFINED)
      if name == UNDEFINED
        @name
      else
        @name = name
      end
    end

    ##
    # @param [String, nil] desc
    # @return [String, nil]
    def description(desc = UNDEFINED)
      if desc == UNDEFINED
        @desc
      else
        @desc = desc
      end
    end

    ##
    # @param [String] path
    # @return [Array<String>]
    def step(path)
      target = File.join(@root, path)
      @steps << File.read(target)
    end

    ##
    # @param [Proc] block
    #   Receives the agent that ran and returns a
    #   Float between 0.0 and 1.0
    # @return [void]
    def score(&block)
      if block
        @score = block
      else
        @score
      end
    end

    ##
    # @return [Float, nil]
    def result
      @final ? @final.clamp(0.0, 1.0) : @final
    end

    ##
    # @param [Proc] block
    #  A proc.
    def setup(&block)
      if block
        @setup = block
      else
        @setup
      end
    end

    ##
    # @param [Proc] block
    #  A proc.
    def teardown(&block)
      if block
        @teardown = block
      else
        @teardown
      end
    end

    ##
    # @param [Proc] block
    #  A proc.
    def intercept(&block)
      if block
        @intercept = block
      else
        @intercept
      end
    end

    ##
    # @param [Proc] block
    #  A proc.
    def tracer(&block)
      if block
        @tracer = block
      else
        @tracer
      end
    end

    ##
    # Configures the agent
    # @return [void]
    def agent(&block)
      if block
        @agent = block
      else
        @agent
      end
    end

    ##
    # @param [Integer] samples
    # @return [Array<Hash>]
    def call
      eval
      _agent = agent
      steps.each { _agent.talk(it, model:) }
      score.call(_agent)
      penalties.each { @result -= it[:by] }
      @final = @result
      if tracer
        tracer.on_exit
        run_aggregate
      end
      {name:, score: @result}
    end

    ##
    # Evals @block within self.
    # @return [void]
    def eval
      instance_eval(&@block) if @block
      instance_eval(&@setup) if @setup
      @intercept = instance_eval(&@intercept) if @intercept
      @tracer = instance_eval(&@tracer) if @tracer
      @agent = @agent.call
    ensure
      instance_eval(&@teardown) if @teardown
    end

    ##
    # Reduce `@result`
    # @param [Integer] by
    # @param [String] why
    # @return [void]
    def penalize!(by:, why:)
      @penalties << {by:, why:}
    end
  end
end
