# frozen_string_literal: true

class LLM::Function
  module Ractor
    require_relative "ractor/job"
    require_relative "ractor/task"
  end
end
