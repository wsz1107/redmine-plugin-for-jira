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
  class IssueStatusHookTest < Minitest::Test
    RoleStub = Struct.new(:id)

    class ProjectStub
      attr_reader :identifier

      def initialize(identifier:, role_ids: ['7'])
        @identifier = identifier
        @role_ids = Array(role_ids)
      end

      def roles_for_user(_user)
        @role_ids.map { |rid| RoleStub.new(rid.to_s) }
      end
    end

    class ProjectWithoutRolesForUserStub
      attr_reader :identifier

      def initialize(identifier:)
        @identifier = identifier
      end
    end

    class IssueStub
      attr_reader :id, :project
      attr_accessor :jira_bridge_jira_key

      def initialize(id:, project:)
        @id = id
        @project = project
        @jira_bridge_jira_key = nil
      end
    end

    class UserStub
      attr_reader :login

      def initialize(login: 'alice', allowed: true, role_ids: nil)
        @login = login
        @allowed = allowed
        @role_ids = Array(role_ids).compact
      end

      def allowed_to?(permission, _project)
        permission == :trigger_jira_creation && @allowed
      end

      def roles_for_project(_project)
        return [] if @role_ids.empty?

        @role_ids.map { |rid| RoleStub.new(rid.to_s) }
      end
    end

    JournalDetailStub = Struct.new(:property, :prop_key, :value, :old_value)
    JournalStub = Struct.new(:user, :details)

    def setup
      RedmineJiraBridge.reset_test_state!
      RedmineJiraBridge.accepted_status_id_value = '3'
      RedmineJiraBridge.allowed_role_ids_value = ['7']
      RedmineJiraBridge.logger_instance = Logger.new(StringIO.new)
    end

    def test_enqueues_job_when_transition_matches_configuration
      issue = IssueStub.new(id: 42, project: ProjectStub.new(identifier: 'demo'))
      journal = JournalStub.new(UserStub.new, [accepted_detail('3', '2')])
      enqueued = []

      RedmineJiraBridge::JiraCreateJob.stub(:perform_later, ->(issue_id) { enqueued << issue_id }) do
        hook.controller_issues_edit_after_save(issue: issue, journal: journal)
      end

      assert_equal [42], enqueued
    end

    def test_does_not_enqueue_when_user_lacks_permission
      issue = IssueStub.new(id: 5, project: ProjectStub.new(identifier: 'demo'))
      journal = JournalStub.new(UserStub.new(allowed: false), [accepted_detail('3', '1')])
      enqueued = []

      RedmineJiraBridge::JiraCreateJob.stub(:perform_later, ->(issue_id) { enqueued << issue_id }) do
        hook.controller_issues_edit_after_save(issue: issue, journal: journal)
      end

      assert_empty enqueued
    end

    def test_does_not_enqueue_when_actor_role_not_allowed
      issue = IssueStub.new(id: 11, project: ProjectStub.new(identifier: 'demo', role_ids: ['5']))
      journal = JournalStub.new(UserStub.new, [accepted_detail('3', '1')])
      enqueued = []

      RedmineJiraBridge.allowed_role_ids_value = ['9']

      RedmineJiraBridge::JiraCreateJob.stub(:perform_later, ->(issue_id) { enqueued << issue_id }) do
        hook.controller_issues_edit_after_save(issue: issue, journal: journal)
      end

      assert_empty enqueued
    end

    def test_does_not_enqueue_when_issue_already_has_jira_key
      issue = IssueStub.new(id: 7, project: ProjectStub.new(identifier: 'demo'))
      issue.jira_bridge_jira_key = 'JRI-1'
      journal = JournalStub.new(UserStub.new, [accepted_detail('3', '2')])
      enqueued = []

      RedmineJiraBridge::JiraCreateJob.stub(:perform_later, ->(issue_id) { enqueued << issue_id }) do
        hook.controller_issues_edit_after_save(issue: issue, journal: journal)
      end

      assert_empty enqueued
    end

    def test_does_not_enqueue_when_prior_successful_sync_log_exists
      issue = IssueStub.new(id: 31, project: ProjectStub.new(identifier: 'demo'))
      journal = JournalStub.new(UserStub.new, [accepted_detail('3', '2')])
      enqueued = []

      sync_log = Struct.new(:status, :jira_key).new('success', 'JRI-77')

      RedmineJiraBridge.stub(:latest_sync_log, sync_log) do
        RedmineJiraBridge::JiraCreateJob.stub(:perform_later, ->(issue_id) { enqueued << issue_id }) do
          hook.controller_issues_edit_after_save(issue: issue, journal: journal)
        end
      end

      assert_empty enqueued
    end

    def test_uses_actor_roles_when_project_lacks_roles_for_user
      issue = IssueStub.new(id: 21, project: ProjectWithoutRolesForUserStub.new(identifier: 'demo'))
      user = UserStub.new(role_ids: ['7'])
      journal = JournalStub.new(user, [accepted_detail('3', '2')])
      enqueued = []

      RedmineJiraBridge::JiraCreateJob.stub(:perform_later, ->(issue_id) { enqueued << issue_id }) do
        hook.controller_issues_edit_after_save(issue: issue, journal: journal)
      end

      assert_equal [21], enqueued
    end

    private

    def hook
      @hook ||= RedmineJiraBridge::Hooks::IssueStatusHook.new
    end

    def accepted_detail(value, old_value)
      JournalDetailStub.new('attr', 'status_id', value, old_value)
    end
  end
end
