# frozen_string_literal: true

class LLM::DeepSeek
  ##
  # The {LLM::DeepSeek::Images LLM::DeepSeek::Images} class
  # provides image generation capabilities through DeepSeek.
  #
  # DeepSeek does not provide an image generation model however
  # its text-to-text models can generate vector graphics (SVGS)
  # and that's the approach that this class takes. It is somewhat
  # experimental.
  #
  # An SVG document can be converted to PNG or another format
  # with tools like rsvg-convert.
  class Images
    ##
    # @param [LLM::DeepSeek] llm
    # @return [LLM::DeepSeek::Images]
    def initialize(llm)
      @llm = llm
    end

    ##
    # @param [String] prompt
    #  A prompt
    # @param [String] model
    #  A text-to-image model.
    # @param [void] size
    #  This parameter is a noop.
    #  Exists for compatibility with other providers.
    # @param [void] n
    #  This parameter is a noop.
    #  Exists for compatibility with other providers.
    # @param [void] response_format
    #  This parameter is a noop.
    #  Exists for compatibility with other providers.
    # @param [void] quality
    #  This parameter is a noop.
    #  Exists for compatibility with other providers.
    # @param [void] style
    #  This parameter is a noop.
    #  Exists for compatibility with other providers.
    # @return [LLM::Response<LLM::DeepSeek::ResponseAdapter::Image>]
    #  Returns a response
    def create(prompt:, model: @llm.default_model, agent: nil, size: nil, n: nil, response_format: nil, quality: nil, style: nil)
      agent ||= LLM::Agent.new(@llm, model:, instructions: create_instructions, response_format: {type: "json_object"})
      res = agent.talk(prompt)
      res = LLM::DeepSeek::ResponseAdapter.adapt(res, type: :image)
      res.define_singleton_method(:agent) { agent }
      res
    end

    ##
    # @param [String] prompt
    #  A prompt
    # @param [String] model
    #  A text-to-image model.
    # @param [String, LLM::File] image
    #  The path to an SVG file
    # @param [void] size
    #  This parameter is a noop.
    #  Exists for compatibility with other providers.
    # @param [void] n
    #  This parameter is a noop.
    #  Exists for compatibility with other providers.
    # @param [void] response_format
    #  This parameter is a noop.
    #  Exists for compatibility with other providers.
    # @param [void] quality
    #  This parameter is a noop.
    #  Exists for compatibility with other providers.
    # @param [void] style
    #  This parameter is a noop.
    #  Exists for compatibility with other providers.
    # @return [LLM::Response<LLM::DeepSeek::ResponseAdapter::Image>]
    #  Returns a response
    def edit(prompt:, image:, model: @llm.default_model, agent: nil, size: nil, n: nil, response_format: nil, quality: nil, style: nil)
      file = LLM.File(image)
      agent ||= LLM::Agent.new(@llm, model:, instructions: edit_instructions(file), response_format: {type: "json_object"})
      res = agent.talk(prompt)
      res = LLM::DeepSeek::ResponseAdapter.adapt(res, type: :image)
      res.define_singleton_method(:agent) { agent }
      res
    end

    private

    def create_instructions
      "Generate a complete SVG document that satisfies the user's prompt. " \
      "Respond with a JSON object that has exactly one key: svg. " \
      "The value of svg must be a valid standalone SVG document as a string. " \
      "Do not include markdown, code fences, commentary, or any keys other than svg."
    end

    def edit_instructions(file)
      file.with_io do |io|
        "Edit the SVG document that is provided according to the user's prompt" \
        "Respond with a JSON object that has exactly one key: svg. " \
        "The value of svg must be a valid standalone SVG document as a string. " \
        "Do not include markdown, code fences, commentary, or any keys other than svg." \
        "The SVG document follows:\n\n#{io.read}" \
      end
    end

    [:path, :headers, :execute, :transport].each do |m|
      define_method(m) { |*args, **kwargs, &b| @llm.send(m, *args, **kwargs, &b) }
    end
  end
end
