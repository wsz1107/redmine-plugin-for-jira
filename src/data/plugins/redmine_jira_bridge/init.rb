require_relative 'lib/redmine_jira_bridge'

Redmine::Plugin.register :redmine_jira_bridge do
  name 'Redmine Jira Bridge'
  author 'Jira Bridge Team'
  description 'Skeleton plugin that will bridge Redmine and Jira.'
  version RedmineJiraBridge::VERSION
  url 'https://example.com/redmine_jira_bridge'
  author_url 'https://example.com'

  settings default: {
    'jira_base_url' => '',
    'jira_email' => '',
    'jira_api_token' => '',
    'accepted_status_id' => nil,
    'allowed_role_ids' => [],
    'default_issue_type' => '',
    'priority_mapping' => '',
    'custom_field_mappings' => ''
  },
           partial: 'settings/redmine_jira_bridge'

  requires_redmine version_or_higher: '5.0.0'

  project_module :jira_bridge do
    permission :trigger_jira_creation, {}, require: :member
    permission :view_jira_link, {}, read: true
  end
end

RedmineJiraBridge.log_startup
