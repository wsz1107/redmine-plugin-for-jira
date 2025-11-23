require 'minitest/autorun'
require 'ostruct'
require 'stringio'
require 'logger'

module Redmine
  module Hook
    class Listener; end
  end
end unless defined?(Redmine)

require_relative '../lib/redmine_jira_bridge/jira_create_job'
require_relative '../lib/redmine_jira_bridge/hooks/issue_status_hook'
require_relative 'support/test_redmine_bridge_helper'

module RedmineJiraBridge
  class JiraTriggerIntegrationTest < Minitest::Test
    RoleStub = Struct.new(:id)
    JournalDetailStub = Struct.new(:property, :prop_key, :value, :old_value)
    JournalStub = Struct.new(:user, :details)

    class ProjectStub
      attr_reader :identifier

      def initialize(identifier:, role_ids: ['2'])
        @identifier = identifier
        @role_ids = Array(role_ids)
      end

      def roles_for_user(_user)
        @role_ids.map { |rid| RoleStub.new(rid.to_s) }
      end
    end

    class UserStub
      attr_reader :login

      def initialize(login: 'integration')
        @login = login
      end

      def allowed_to?(permission, _project)
        permission == :trigger_jira_creation
      end
    end

    class IssueStub
      attr_reader :id, :subject, :description, :project, :priority, :custom_field_values, :journals, :save_calls
      attr_accessor :jira_bridge_jira_key

      def initialize(id:, subject:, project:)
        @id = id
        @subject = subject
        @description = "Details for #{subject}"
        @project = project
        @priority = OpenStruct.new(name: 'Normal')
        @custom_field_values = []
        @journals = []
        @save_calls = []
        @jira_bridge_jira_key = nil
      end

      def init_journal(user, notes)
        @journals << OpenStruct.new(user: user, notes: notes)
      end

      def save(*args)
        @save_calls << args
        true
      end
    end

    class CapturingClient
      attr_reader :payloads

      def initialize(response_key: 'JRI-123')
        @payloads = []
        @response = { 'key' => response_key, 'id' => '2000' }
      end

      def create_issue(payload)
        @payloads << payload
        @response
      end
    end

    def setup
      RedmineJiraBridge.reset_test_state!
      RedmineJiraBridge.jira_base_url_value = 'https://example.atlassian.net'
      RedmineJiraBridge.jira_email_value = 'bot@example.com'
      RedmineJiraBridge.jira_api_token_value = 'token'
      RedmineJiraBridge.accepted_status_id_value = '5'
      RedmineJiraBridge.allowed_role_ids_value = ['2']
      RedmineJiraBridge.test_default_issue_type = 'Task'
      RedmineJiraBridge.logger_instance = Logger.new(StringIO.new)
    end

    def test_status_change_to_accepted_creates_jira_issue_and_persists_key
      project = ProjectStub.new(identifier: 'JRI')
      issue = IssueStub.new(id: 99, subject: 'Translate acceptance spec', project: project)
      journal = JournalStub.new(UserStub.new, [JournalDetailStub.new('attr', 'status_id', '5', '3')])
      client = CapturingClient.new(response_key: 'JRI-451')

      RedmineJiraBridge::JiraClient.stub(:new, ->(**_) { client }) do
        perform_inline_job(issue) do
          hook.controller_issues_edit_after_save(issue: issue, journal: journal)
        end
      end

      assert_equal 'JRI-451', issue.jira_bridge_jira_key
      assert_equal 1, issue.journals.size
      assert_includes issue.journals.first.notes, 'JRI-451'
      refute_empty issue.save_calls

      payload = client.payloads.first
      refute_nil payload
      assert_equal 'JRI', payload['fields']['project']['key']
      assert_equal 'Task', payload['fields']['issuetype']['name']
      assert_equal 'Translate acceptance spec', payload['fields']['summary']
    end

    private

    def hook
      @hook ||= RedmineJiraBridge::Hooks::IssueStatusHook.new
    end

    def perform_inline_job(issue)
      RedmineJiraBridge::JiraCreateJob.stub(:perform_later, ->(issue_id) {
        job = RedmineJiraBridge::JiraCreateJob.new
        job.stub(:locate_issue, issue) do
          job.perform(issue_id, {})
        end
      }) do
        yield
      end
    end
  end
end
