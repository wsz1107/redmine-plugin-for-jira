require 'minitest/autorun'
require 'timeout'
require_relative '../lib/redmine_jira_bridge/jira_client'

module RedmineJiraBridge
  class JiraClientTest < Minitest::Test
    def setup
      @base_url = 'https://example.atlassian.net'
      @email = 'redmine@example.com'
      @token = 'api-token'
      @payload = { 'fields' => { 'summary' => 'Test issue' } }
    end

    def test_create_issue_returns_parsed_body_on_success
      response = http_success({ id: '100', key: 'JRI-1' }.to_json)
      adapter = ->(_uri, _request) { response }
      client = build_client(http_adapter: adapter)

      result = client.create_issue(@payload)

      assert_equal 'JRI-1', result['key']
      assert_equal '100', result['id']
    end

    def test_create_issue_raises_api_error_on_internal_server_error
      response = http_response(Net::HTTPInternalServerError, '500', 'boom')
      adapter = ->(_uri, _request) { response }
      client = build_client(http_adapter: adapter)

      error = assert_raises(JiraClient::ApiError) { client.create_issue(@payload) }
      assert_equal 500, error.status
      assert_match 'boom', error.body
    end

    def test_create_issue_raises_network_error_on_timeout
      adapter = lambda { |_uri, _request| raise Timeout::Error, 'execution expired' }
      client = build_client(http_adapter: adapter)

      error = assert_raises(JiraClient::NetworkError) { client.create_issue(@payload) }
      assert_kind_of Timeout::Error, error.cause
    end

    def test_request_uses_custom_open_and_read_timeouts
      client = build_client(http_adapter: nil, open_timeout: 9, read_timeout: 22)

      captured = {}
      response = http_success('{}')
      http_double = Minitest::Mock.new
      http_double.expect(:request, response, [Net::HTTPRequest])

      Net::HTTP.stub(:start, proc do |host, port, **opts, &block|
        captured[:host] = host
        captured[:port] = port
        captured[:use_ssl] = opts[:use_ssl]
        captured[:open_timeout] = opts[:open_timeout]
        captured[:read_timeout] = opts[:read_timeout]
        block.call(http_double)
      end) do
        client.create_issue(@payload)
      end

      assert_equal 'example.atlassian.net', captured[:host]
      assert_equal 443, captured[:port]
      assert_equal true, captured[:use_ssl]
      assert_equal 9, captured[:open_timeout]
      assert_equal 22, captured[:read_timeout]
      http_double.verify
    end

    private

    def build_client(**opts)
      JiraClient.new(base_url: @base_url, email: @email, api_token: @token, **opts)
    end

    def http_success(body)
      stub_response(Net::HTTPOK, '200', body)
    end

    def http_response(klass, code, body)
      stub_response(klass, code, body)
    end

    def stub_response(klass, code, body)
      response = klass.new('1.1', code, klass.name.split('::').last)
      response.instance_variable_set(:@stub_body, body)
      response.define_singleton_method(:body) { @stub_body }
      response
    end
  end
end
