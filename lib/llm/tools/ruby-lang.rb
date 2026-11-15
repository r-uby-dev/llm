# frozen_string_literal: true

require "net/http"
require "openssl"
require "json"
require "uri"

class LLM::Tool
  ##
  # The superclass of all ruby-lang.org tools.
  #
  # The tools below this class talk to bugs.ruby-lang.org,
  # the Redmine that Ruby tracks its bugs, its features and
  # its backports in, and they talk to it over the REST API
  # that every Redmine has: a path, a `.json` extension,
  # and query parameters that Redmine calls filters.
  #
  # What is below this class is the public half of that
  # API - the endpoints an anonymous caller can read.
  # `issues` is the list, `issue` is one of them with its
  # journals, `projects` is the tree the issues live in,
  # and `search` is Redmine's own index over all of it.
  # The write endpoints - a new issue, a note, a status
  # change, an attachment - want an API key and are not
  # here yet, and neither is anything that reads a private
  # issue, because a private issue is a 404 to a caller
  # without a key.
  #
  # HTTP goes through Net::HTTP, one memoized client per
  # tool instance, with `use_ssl` on. A tool that wants to
  # replace the transport - a cache, a proxy, a fake -
  # replaces {#get}, and every tool below this class goes
  # through it.
  #
  # A response is returned to the model as it comes: `ok:`
  # says whether Redmine answered with a 2xx, `body:` is
  # the parsed JSON when it did, and `error:` is the status
  # and the head of the body when it did not. It is close
  # to the shape {LLM::Tool::Utils::Process#exec} has, so a
  # model reads a failed request and a failed command the
  # same way.
  #
  # @abstract
  # @see LLM::Tool::RubyLang::Issue
  # @see LLM::Tool::RubyLang::Issues
  # @see LLM::Tool::RubyLang::Projects
  # @see LLM::Tool::RubyLang::Search
  class RubyLang < self
    abstract!

    ##
    # The host the tools talk to
    # @return [String]
    HOST = "bugs.ruby-lang.org"

    ##
    # The port the tools talk to
    # @return [Integer]
    PORT = 443

    require_relative "ruby-lang/issue"
    require_relative "ruby-lang/issues"
    require_relative "ruby-lang/projects"
    require_relative "ruby-lang/search"

    private

    ##
    # Returns the HTTP client. Each tool instance keeps one,
    # and it speaks TLS to {HOST}.
    # @return [Net::HTTP]
    def http
      @http ||= begin
        http = Net::HTTP.new(HOST, PORT)
        http.use_ssl = true
        http.open_timeout = 10
        http
      end
    end

    ##
    # Sends a GET request to a path below {HOST} and returns
    # the parsed JSON, or the status and the body when the
    # request did not succeed.
    # @param [String] path
    #  The path, without the host, eg "/issues.json"
    # @param [Hash] params
    #  The query parameters. A nil or an empty value is
    #  dropped, and an array is joined with commas, which
    #  is how Redmine takes a list
    # @param [Integer] timeout
    #  The max number of seconds to wait for the response
    # @return [Hash]
    def get(path, params = {}, timeout: 30)
      uri = URI.parse("https://#{HOST}:#{PORT}#{path}")
      query = encode(params)
      uri.query = query unless query.empty?
      http.read_timeout = timeout
      response = http.request(Net::HTTP::Get.new(uri))
      if response.is_a?(Net::HTTPSuccess)
        {ok: true, status: response.code.to_i, body: JSON.parse(response.body)}
      else
        {ok: false, status: response.code.to_i, error: failure(response)}
      end
    rescue JSON::ParserError
      {ok: false, status: response&.code&.to_i, error: "the response was not JSON"}
    rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError => ex
      {ok: false, error: "#{ex.class}: #{ex.message}"}
    end

    ##
    # Turns a hash into a query string, dropping what is
    # empty and joining what is a list.
    # @param [Hash] params
    # @return [String]
    def encode(params)
      params = params.reject { |_, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
      URI.encode_www_form(params.transform_values { |value| ::Array === value ? value.join(",") : value })
    end

    ##
    # Describes a response that is not a 2xx.
    # @param [Net::HTTPResponse] response
    # @return [String]
    def failure(response)
      body = response.body.to_s[0, 300]
      "HTTP #{response.code} #{response.message}: #{body}".strip
    end
  end
end
