require 'minitest/autorun'
require 'ostruct'
require 'stringio'
require 'logger'

module RedmineJiraBridge
  LOGGER_PREFIX = '[test_redmine_jira_bridge]'.freeze unless const_defined?(:LOGGER_PREFIX)

  class << self
    attr_writer :logger_instance
    attr_accessor :jira_base_url_value, :jira_email_value, :jira_api_token_value

    def logger
      @logger_instance ||= Logger.new(StringIO.new)
    end

    def jira_base_url
      jira_base_url_value
    end

    def jira_email
      jira_email_value
    end

    def jira_api_token
      jira_api_token_value
    end
  end
end

class Issue
  attr_reader :id, :subject, :description, :project, :priority, :custom_field_values

  def initialize(id:, subject:, description: 'Body', project_identifier: 'JRI')
    @id = id
    @subject = subject
    @description = description
    @project = OpenStruct.new(identifier: project_identifier)
    @priority = OpenStruct.new(name: 'Normal')
    @custom_field_values = []
  end

  def self.find_by(id:)
    return Issue.new(id: id, subject: 'Translate spec') if id == 42

    nil
  end
end

require_relative '../lib/redmine_jira_bridge/jira_create_job'

module RedmineJiraBridge
  class JiraCreateJobTest < Minitest::Test
    class StubBuilder
      def initialize(payload)
        @payload = payload
      end

      def build
        @payload
      end
    end

    def setup
      RedmineJiraBridge.jira_base_url_value = 'https://example.atlassian.net'
      RedmineJiraBridge.jira_email_value = 'bot@example.com'
      RedmineJiraBridge.jira_api_token_value = 'token'
      RedmineJiraBridge.logger_instance = Logger.new(StringIO.new)
    end

    def test_perform_builds_payload_and_invokes_client
      payload = { 'fields' => { 'summary' => 'Translate spec' } }
      builder_options = nil
      captured_issue_ids = []

      builder_factory = lambda do |issue_arg, options_arg|
        captured_issue_ids << issue_arg.id
        builder_options = options_arg
        StubBuilder.new(payload)
      end

      client = Minitest::Mock.new
      client.expect(:create_issue, { 'key' => 'JRI-100', 'id' => '10100' }, [payload])

      RedmineJiraBridge::JiraPayloadBuilder.stub(:new, builder_factory) do
        RedmineJiraBridge::JiraClient.stub(:new, ->(**_) { client }) do
          job = RedmineJiraBridge::JiraCreateJob.new
          job.perform(42, project_key: 'JRI', issue_type: 'Task')
        end
      end

      client.verify
      assert_equal [42], captured_issue_ids
      assert_equal({ project_key: 'JRI', issue_type: 'Task' }, builder_options)
    end

    def test_perform_retries_on_network_errors_with_backoff
      payload = { 'fields' => { 'summary' => 'Translate spec' } }

      RedmineJiraBridge::JiraPayloadBuilder.stub(:new, ->(_issue, _opts) { StubBuilder.new(payload) }) do
        network_error = RedmineJiraBridge::JiraClient::NetworkError.new('network', StandardError.new('timeout'))
        client = Object.new
        client.define_singleton_method(:create_issue) do |_|
          raise network_error
        end

        RedmineJiraBridge::JiraClient.stub(:new, ->(**_) { client }) do
          job = RedmineJiraBridge::JiraCreateJob.new
          waits = []
          job.stub(:retry_job, ->(wait:) { waits << wait }) do
            job.perform(42, {})
          end

          assert_equal 1, waits.size
          assert_equal RedmineJiraBridge::JiraCreateJob::BASE_BACKOFF_SECONDS, waits.first
        end
      end
    end

    def test_perform_raises_when_retry_budget_exhausted
      payload = { 'fields' => { 'summary' => 'Translate spec' } }

      RedmineJiraBridge::JiraPayloadBuilder.stub(:new, ->(_issue, _opts) { StubBuilder.new(payload) }) do
        network_error = RedmineJiraBridge::JiraClient::NetworkError.new('network', StandardError.new('timeout'))
        client = Object.new
        client.define_singleton_method(:create_issue) { |_payload| raise network_error }

        RedmineJiraBridge::JiraClient.stub(:new, ->(**_) { client }) do
          job = RedmineJiraBridge::JiraCreateJob.new
          job.executions = RedmineJiraBridge::JiraCreateJob::MAX_RETRY_ATTEMPTS

          assert_raises(RedmineJiraBridge::JiraClient::NetworkError) do
            job.perform(42, {})
          end
        end
      end
    end
  end
end
