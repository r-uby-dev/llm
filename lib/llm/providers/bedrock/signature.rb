# frozen_string_literal: true

class LLM::Bedrock
  ##
  # Signs HTTP requests and headers with AWS Signature V4.
  #
  # Returns the signed headers as a Hash through #to_h, ready to merge
  # into an {LLM::Transport::Request} or other HTTP client. Everything else is
  # private.
  #
  # Uses only Ruby's stdlib (openssl, digest) with no external deps.
  #
  # @example
  #   signature = LLM::Bedrock::Signature.new(
  #     credentials: LLM::Object.from(
  #       access_key_id: ENV["AWS_ACCESS_KEY_ID"],
  #       secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
  #       aws_region: "us-east-1",
  #       host: "bedrock-runtime.us-east-1.amazonaws.com",
  #       session_token: nil
  #     ),
  #     method: "POST",
  #     path: "/model/anthropic.claude-3/converse",
  #     body: '{"messages":[...]}'
  #   )
  #   signature.sign!(req)
  #
  # @api private
  class Signature
    SERVICE = "bedrock"

    ##
    # @param [LLM::Object] credentials AWS signing credentials and host
    # @param [String] method HTTP method ("POST", "GET", etc.)
    # @param [String] path Request path (e.g. "/model/.../converse")
    # @param [String] body Raw request body
    # @param [String, nil] query Canonical query string
    def initialize(credentials:, method:, path:, body:, query: nil)
      @credentials = credentials
      @method = method
      @path = path
      @query = query
      @body = body
    end

    ##
    # Returns the signed headers as a plain Hash.
    #
    # Call this once per request and merge the result into your
    # HTTP headers. Each call recomputes the signature with the
    # current time, so call it immediately before sending.
    #
    # @return [Hash{String => String}]
    def to_h
      now = Time.now.utc
      amz_date = now.strftime("%Y%m%dT%H%M%SZ")
      date_stamp = now.strftime("%Y%m%d")
      payload_hash = Digest::SHA256.hexdigest(@body)
      headers = {
        "X-Amz-Date" => amz_date,
        "X-Amz-Content-Sha256" => payload_hash,
        "Content-Type" => "application/json",
        "Host" => @credentials.host
      }
      headers["X-Amz-Security-Token"] = @credentials.session_token if @credentials.session_token
      signed_headers = build_signed_headers
      canonical_headers = build_canonical_headers(headers, signed_headers)
      canonical_uri = build_canonical_uri
      canonical_query = build_canonical_query
      canonical_request = build_canonical_request(
        canonical_uri, canonical_query, canonical_headers, signed_headers, payload_hash
      )
      credential_scope = "#{date_stamp}/#{@credentials.aws_region}/#{SERVICE}/aws4_request"
      string_to_sign = build_string_to_sign(
        amz_date, credential_scope, canonical_request
      )
      signing_key = derive_signing_key(date_stamp)
      signature = OpenSSL::HMAC.hexdigest(
        "sha256", signing_key, string_to_sign
      )
      headers["Authorization"] =
        "AWS4-HMAC-SHA256 " \
        "Credential=#{@credentials.access_key_id}/#{credential_scope}, " \
        "SignedHeaders=#{signed_headers}, Signature=#{signature}"
      headers
    end

    ##
    # @param [LLM::Transport::Request] req
    # @return [LLM::Transport::Request]
    def sign!(req)
      to_h.each { |k, v| req[k] = v }
      req
    end

    private

    def build_signed_headers
      %w[host x-amz-date x-amz-content-sha256].tap do |h|
        h << "x-amz-security-token" if @credentials.session_token
        h << "content-type"
      end.sort.join(";")
    end

    def build_canonical_headers(headers, signed_headers)
      headers = headers.transform_keys(&:downcase)
      signed_headers.split(";").map do |key|
        "#{key}:#{headers[key].to_s.strip}\n"
      end.join
    end

    def build_canonical_uri
      path = @path
      return "/" if path.nil? || path.empty?
      segments = path.split("/", -1).map { |s| uri_encode(s) }
      canonical = segments.join("/")
      canonical.start_with?("/") ? canonical : "/#{canonical}"
    end

    def build_canonical_query
      return "" if @query.to_s.empty?
      URI.decode_www_form(@query).sort.map do |key, value|
        "#{uri_encode(key)}=#{uri_encode(value)}"
      end.join("&")
    end

    def build_canonical_request(uri, query, canonical_headers,
                                signed_headers, payload_hash)
      [
        @method,
        uri,
        query,
        canonical_headers,
        signed_headers,
        payload_hash
      ].join("\n")
    end

    def build_string_to_sign(amz_date, credential_scope, canonical_request)
      [
        "AWS4-HMAC-SHA256",
        amz_date,
        credential_scope,
        Digest::SHA256.hexdigest(canonical_request)
      ].join("\n")
    end

    def derive_signing_key(date_stamp)
      k_date = OpenSSL::HMAC.digest(
        "sha256", "AWS4#{@credentials.secret_access_key}", date_stamp
      )
      k_region = OpenSSL::HMAC.digest("sha256", k_date, @credentials.aws_region)
      k_service = OpenSSL::HMAC.digest("sha256", k_region, SERVICE)
      OpenSSL::HMAC.digest("sha256", k_service, "aws4_request")
    end

    def uri_encode(str)
      URI.encode_www_form_component(str.to_s)
        .gsub("+", "%20")
        .gsub("%7E", "~")
    end
  end
end
