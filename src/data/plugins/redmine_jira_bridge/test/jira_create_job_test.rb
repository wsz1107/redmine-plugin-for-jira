require 'minitest/autorun'
require 'ostruct'
require 'stringio'
require 'logger'

require_relative 'support/test_redmine_bridge_helper'

class Issue
  attr_reader :id, :subject, :description, :project, :priority, :custom_field_values, :save_calls
  attr_accessor :jira_bridge_jira_key

  def initialize(id:, subject:, description: 'Body', project_identifier: 'JRI')
    @id = id
    @subject = subject
    @description = description
    @project = OpenStruct.new(identifier: project_identifier)
    @priority = OpenStruct.new(name: 'Normal')
    @custom_field_values = []
    @journals = []
    @save_calls = []
  end

  def self.find_by(id:)
    return Issue.new(id: id, subject: 'Translate spec') if id == 42

    nil
  end

  def journals
    @journals
  end

  def init_journal(user, notes)
    @journals << OpenStruct.new(user: user, notes: notes)
  end

  def save(*)
    @save_calls << { validate: false }
    true
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
      RedmineJiraBridge.project_configuration_provider = nil
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

    def test_persists_jira_key_and_records_journal
      payload = { 'fields' => { 'summary' => 'Translate spec' } }
      issue = Issue.new(id: 99, subject: 'Translate spec')

      RedmineJiraBridge::JiraPayloadBuilder.stub(:new, ->(_issue, _opts) { StubBuilder.new(payload) }) do
        client = Minitest::Mock.new
        client.expect(:create_issue, { 'key' => 'JRI-200', 'id' => '20000' }, [payload])

        RedmineJiraBridge::JiraClient.stub(:new, ->(**_) { client }) do
          job = RedmineJiraBridge::JiraCreateJob.new
          job.stub(:locate_issue, issue) do
            job.perform(99, {})
          end
        end
      end

      assert_equal 'JRI-200', issue.jira_bridge_jira_key
      assert_equal 2, issue.save_calls.size
      assert_equal 1, issue.journals.size
      assert_includes issue.journals.first.notes, 'https://example.atlassian.net/browse/JRI-200'
    end

    def test_does_not_overwrite_existing_jira_key_or_duplicate_journal
      payload = { 'fields' => { 'summary' => 'Translate spec' } }
      issue = Issue.new(id: 100, subject: 'Translate spec')
      issue.jira_bridge_jira_key = 'JRI-999'
      issue.init_journal(nil, 'Created Jira issue JRI-999: https://example.atlassian.net/browse/JRI-999')

      RedmineJiraBridge::JiraPayloadBuilder.stub(:new, ->(_issue, _opts) { StubBuilder.new(payload) }) do
        client = Minitest::Mock.new
        client.expect(:create_issue, { 'key' => 'JRI-1000', 'id' => '20001' }, [payload])

        RedmineJiraBridge::JiraClient.stub(:new, ->(**_) { client }) do
          job = RedmineJiraBridge::JiraCreateJob.new
          job.stub(:locate_issue, issue) do
            job.perform(100, {})
          end
        end
      end

      assert_equal 'JRI-999', issue.jira_bridge_jira_key
      assert_equal 1, issue.journals.size
      assert_empty issue.save_calls
    end

    def test_perform_applies_project_defaults_when_job_options_missing
      payload = { 'fields' => { 'summary' => 'Translate spec' } }
      builder_options = nil

      RedmineJiraBridge.project_configuration_provider = ->(project) {
        {
          enabled: true,
          jira_project_key: "CONF-#{project.identifier}",
          default_issue_type: 'Bug'
        }
      }

      builder_factory = lambda do |issue_arg, options_arg|
        builder_options = options_arg
        StubBuilder.new(payload)
      end

      client = Minitest::Mock.new
      client.expect(:create_issue, { 'key' => 'JRI-200', 'id' => '20000' }, [payload])

      RedmineJiraBridge::JiraPayloadBuilder.stub(:new, builder_factory) do
        RedmineJiraBridge::JiraClient.stub(:new, ->(**_) { client }) do
          job = RedmineJiraBridge::JiraCreateJob.new
          job.perform(42, {})
        end
      end

      assert_equal({ project_key: 'CONF-JRI', issue_type: 'Bug' }, builder_options)
      client.verify
    end

    def test_perform_returns_early_when_project_disabled
      RedmineJiraBridge.project_configuration_provider = ->(_project) {
        {
          enabled: false,
          jira_project_key: 'CONF',
          default_issue_type: 'Bug'
        }
      }

      payload = { 'fields' => { 'summary' => 'Translate spec' } }
      builder_invoked = false

      RedmineJiraBridge::JiraPayloadBuilder.stub(:new, ->(*_) { builder_invoked = true; StubBuilder.new(payload) }) do
        job = RedmineJiraBridge::JiraCreateJob.new
        result = job.perform(42, {})
        assert_nil result
      end

      refute builder_invoked, 'builder should not be invoked when project disabled'
    end

    def test_records_failure_journal_when_payload_validation_fails
      issue = Issue.new(id: 123, subject: 'Invalid issue')
      failing_builder = Object.new
      failing_builder.define_singleton_method(:build) do
        raise RedmineJiraBridge::JiraPayloadBuilder::ValidationError, 'summary missing'
      end

      RedmineJiraBridge::JiraPayloadBuilder.stub(:new, ->(*_) { failing_builder }) do
        job = RedmineJiraBridge::JiraCreateJob.new
        job.stub(:locate_issue, issue) do
          assert_raises(RedmineJiraBridge::JiraPayloadBuilder::ValidationError) do
            job.perform(issue.id, {})
          end
        end
      end

      assert_equal 1, issue.journals.size
      notes = issue.journals.first.notes
      assert_includes notes, 'Jira creation failed'
      assert_includes notes, 'summary missing'
    end

    def test_retryable_network_error_does_not_record_failure_journal
      payload = { 'fields' => { 'summary' => 'Translate spec' } }
      issue = Issue.new(id: 321, subject: 'Translate spec')

      RedmineJiraBridge::JiraPayloadBuilder.stub(:new, ->(_issue, _opts) { StubBuilder.new(payload) }) do
        network_error = RedmineJiraBridge::JiraClient::NetworkError.new('network', StandardError.new('timeout'))
        client = Object.new
        client.define_singleton_method(:create_issue) { |_payload| raise network_error }

        RedmineJiraBridge::JiraClient.stub(:new, ->(**_) { client }) do
          job = RedmineJiraBridge::JiraCreateJob.new
          waits = []
          job.stub(:locate_issue, issue) do
            job.stub(:retry_job, ->(wait:) { waits << wait }) do
              job.perform(issue.id, {})
            end
          end
          assert_equal [RedmineJiraBridge::JiraCreateJob::BASE_BACKOFF_SECONDS], waits
        end
      end

      assert_empty issue.journals
    end

    def test_records_failure_journal_when_retry_budget_exhausted
      payload = { 'fields' => { 'summary' => 'Translate spec' } }
      issue = Issue.new(id: 654, subject: 'Translate spec')

      RedmineJiraBridge::JiraPayloadBuilder.stub(:new, ->(_issue, _opts) { StubBuilder.new(payload) }) do
        network_error = RedmineJiraBridge::JiraClient::NetworkError.new('network', StandardError.new('timeout'))
        client = Object.new
        client.define_singleton_method(:create_issue) { |_payload| raise network_error }

        RedmineJiraBridge::JiraClient.stub(:new, ->(**_) { client }) do
          job = RedmineJiraBridge::JiraCreateJob.new
          job.executions = RedmineJiraBridge::JiraCreateJob::MAX_RETRY_ATTEMPTS
          job.stub(:locate_issue, issue) do
            assert_raises(RedmineJiraBridge::JiraClient::NetworkError) do
              job.perform(issue.id, {})
            end
          end
        end
      end

      assert_equal 1, issue.journals.size
      assert_includes issue.journals.first.notes, 'Network error'
    end
  end
end
