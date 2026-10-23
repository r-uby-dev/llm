# frozen_string_literal: true

class LLM::Bedrock
  ##
  # The {LLM::Bedrock::Models} class provides a model object for
  # interacting with [AWS Bedrock's ListFoundationModels API](
  # https://docs.aws.amazon.com/bedrock/latest/APIReference/API_ListFoundationModels.html).
  #
  # Unlike the Converse API (which lives on `bedrock-runtime.<region>.amazonaws.com`),
  # the models endpoint lives on the control plane at
  # `bedrock.<region>.amazonaws.com`. This class builds a matching
  # transport for the control-plane host from the provider's current
  # transport class.
  #
  # @example
  #   llm = LLM.bedrock(
  #     access_key_id: ENV["AWS_ACCESS_KEY_ID"],
  #     secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
  #     region: "us-east-1"
  #   )
  #   llm.models.all.each { |m| puts m.id }
  class Models
    ##
    # @param [LLM::Bedrock] llm
    # @return [LLM::Bedrock::Models]
    def initialize(llm)
      @llm = llm
    end

    ##
    # List all foundation models available in the configured region.
    #
    # @note
    #  This calls AWS Bedrock's ListFoundationModels API which returns
    #  all models available in the region, not just the ones the
    #  current account is subscribed to.
    #
    # @param [Hash] params Optional query parameters
    #  (e.g. `byProvider: "Anthropic"`, `byInferenceType: "ON_DEMAND"`)
    # @return [LLM::Response]
    def all(**params)
      host = credentials.host
      request_id = SecureRandom.uuid_v7
      req = build_request(host, params)
      res = build_transport(host).request(req, owner: self)
      handle_response(res, request_id)
    end

    private

    ##
    # @param [String] host
    # @return [LLM::Transport]
    def build_transport(host)
      transport.class.new(host:, port: 443, timeout:, connect_timeout:, ssl: true)
    end

    ##
    # @param [String] host
    # @param [Hash] params
    # @return [LLM::Transport::Request]
    def build_request(host, params)
      path = "/foundation-models"
      query = URI.encode_www_form(params) unless params.empty?
      path = "#{path}?#{query}" if query && !query.empty?
      body = ""
      req = LLM::Transport::Request.get(path, {"Content-Type" => "application/json", "Accept" => "application/json"})
      req.tap { sign!(req, body, host, query) }
    end

    ##
    # @param [LLM::Transport::Response, Net::HTTPResponse] res
    # @param [String] request_id
    # @return [LLM::Response]
    # @raise [LLM::Error]
    def handle_response(res, request_id)
      res = LLM::Transport::Response.from(res)
      if res.success?
        res.body = LLM::Object.from(LLM.json.load(res.body || "{}"))
        LLM::Bedrock::ResponseAdapter.adapt(res, type: :models)
      else
        body = +""
        res.read_body { body << _1 } if res.body.nil?
        LLM::Bedrock::ErrorHandler.new(tracer, nil, res, request_id).raise_error!
      end
    end

    ##
    # @param [LLM::Transport::Request] req
    # @param [String] body
    # @param [String] host
    # @param [String, nil] query
    # @return [LLM::Transport::Request]
    def sign!(req, body, host = credentials.host, query = nil)
      creds = credentials.tap { _1.host = host }
      Signature.new(credentials: creds, method: "GET", path: "/foundation-models", query:, body:).sign!(req)
    end

    ##
    # @return [LLM::Object]
    def credentials
      LLM::Object.from(@llm.send(:credentials).to_h).tap do
        _1.host = "bedrock.#{_1.aws_region}.amazonaws.com"
      end
    end

    [:timeout, :connect_timeout, :tracer, :transport].each do |m|
      define_method(m) { @llm.send(m) }
    end
  end
end
