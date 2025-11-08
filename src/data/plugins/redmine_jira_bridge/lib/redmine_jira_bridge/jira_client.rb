require 'json'
require 'net/http'
require 'uri'
require 'openssl'

module RedmineJiraBridge
  class JiraClient
    DEFAULT_OPEN_TIMEOUT = 5
    DEFAULT_READ_TIMEOUT = 15

    Error = Class.new(StandardError)
    ConfigurationError = Class.new(Error)

    class NetworkError < Error
      attr_reader :cause

      def initialize(message, cause)
        @cause = cause
        super("#{message}: #{cause.class} #{cause.message}")
      end
    end

    class ApiError < Error
      attr_reader :status, :body

      def initialize(message, status:, body:)
        @status = status.to_i
        @body = body
        super("#{message} (status #{@status})")
      end
    end

    attr_reader :base_uri, :email, :api_token, :http_adapter

    def initialize(base_url:, email:, api_token:, http_adapter: nil,
                   open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT)
      @base_uri = parse_base_uri(base_url)
      @email = normalize_string(email)
      @api_token = normalize_string(api_token)
      @http_adapter = http_adapter
      @open_timeout = open_timeout
      @read_timeout = read_timeout

      validate_credentials!
    end

    def create_issue(payload)
      raise ArgumentError, 'payload must be a Hash' unless payload.is_a?(Hash)

      response = request(:post, '/rest/api/3/issue', payload)
      parse_body(response)
    end

    private

    def request(method, path, payload = nil)
      uri = request_uri(path)
      request = build_request(method, uri, payload)
      response = execute_http(uri, request)

      return response if response.is_a?(Net::HTTPSuccess)

      raise ApiError.new('Jira API request failed',
                         status: response.code,
                         body: safe_body(response))
    rescue Timeout::Error, SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT,
           Errno::EHOSTUNREACH, Errno::ECONNRESET, OpenSSL::SSL::SSLError => e
      raise NetworkError.new('Jira API network error', e)
    end

    def build_request(method, uri, payload)
      klass =
        case method.to_s.downcase
        when 'post' then Net::HTTP::Post
        when 'get' then Net::HTTP::Get
        when 'put' then Net::HTTP::Put
        when 'delete' then Net::HTTP::Delete
        else
          raise ArgumentError, "Unsupported HTTP method: #{method}"
        end

      request = klass.new(uri)
      request.basic_auth(email, api_token)
      request['Accept'] = 'application/json'
      request['Content-Type'] = 'application/json'
      request.body = JSON.generate(payload) if payload
      request
    end

    def execute_http(uri, request)
      return http_adapter.call(uri, request) if http_adapter.respond_to?(:call)

      Net::HTTP.start(uri.host, uri.port,
                      use_ssl: uri.scheme == 'https',
                      open_timeout: @open_timeout,
                      read_timeout: @read_timeout) do |http|
        http.request(request)
      end
    end

    def parse_body(response)
      body = safe_body(response)
      return {} if body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      { 'raw_body' => body }
    end

    def safe_body(response)
      response.body.to_s.dup
    end

    def request_uri(path)
      normalized_path = path.to_s.start_with?('/') ? path.to_s : "/#{path}"
      URI.join(base_uri.to_s.end_with?('/') ? base_uri.to_s : "#{base_uri}/", normalized_path)
    rescue URI::Error => e
      raise ConfigurationError, "Invalid Jira path '#{path}': #{e.message}"
    end

    def parse_base_uri(raw)
      value = normalize_string(raw)
      raise ConfigurationError, 'Jira base URL is required' if value.nil?

      uri = URI.parse(value)
      unless uri.is_a?(URI::HTTP) && uri.host && !uri.host.empty?
        raise ConfigurationError, 'Jira base URL must include http(s) scheme and host'
      end

      uri.path = '/' if uri.path.to_s.empty?
      uri
    rescue URI::InvalidURIError => e
      raise ConfigurationError, "Invalid Jira base URL: #{e.message}"
    end

    def validate_credentials!
      raise ConfigurationError, 'Jira email is required' if email.nil?
      raise ConfigurationError, 'Jira API token is required' if api_token.nil?
    end

    def normalize_string(value)
      return nil if value.nil?

      str = value.to_s.strip
      str.empty? ? nil : str
    end
  end
end
