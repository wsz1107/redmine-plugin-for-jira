require 'minitest/autorun'
require 'ostruct'

require_relative '../lib/redmine_jira_bridge/patches/projects_helper_patch'

unless defined?(ProjectsHelper)
  module ProjectsHelper
    def project_settings_tabs
      [{name: 'info'}]
    end
  end
end

ProjectsHelper.prepend(RedmineJiraBridge::Patches::ProjectsHelperPatch) unless ProjectsHelper < RedmineJiraBridge::Patches::ProjectsHelperPatch

class User
  class << self
    attr_accessor :current_user
  end

  def self.current
    current_user
  end

  def initialize(allowed: true)
    @allowed = allowed
  end

  def allowed_to?(permission, _project)
    permission == :edit_project && @allowed
  end
end

class ProjectSettingsTabTest < Minitest::Test
  def setup
    User.current_user = User.new(allowed: true)
    @project = OpenStruct.new(id: 1, identifier: 'demo')
  end

  def helper_instance
    helper = Object.new
    helper.extend(ProjectsHelper)
    helper.instance_variable_set(:@project, @project)
    helper
  end

  def test_jira_tab_appended_for_authorized_users
    tabs = helper_instance.project_settings_tabs
    assert_includes tabs.map { |tab| tab[:name] }, 'jira_bridge'
  end

  def test_jira_tab_hidden_when_user_lacks_permission
    User.current_user = User.new(allowed: false)
    tabs = helper_instance.project_settings_tabs
    refute_includes tabs.map { |tab| tab[:name] }, 'jira_bridge'
  end
end
