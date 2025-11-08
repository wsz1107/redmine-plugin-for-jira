require_relative 'lib/redmine_jira_bridge'

Redmine::Plugin.register :redmine_jira_bridge do
  name 'Redmine Jira Bridge'
  author 'Jira Bridge Team'
  description 'Skeleton plugin that will bridge Redmine and Jira.'
  version RedmineJiraBridge::VERSION
  url 'https://example.com/redmine_jira_bridge'
  author_url 'https://example.com'

  requires_redmine version_or_higher: '5.0.0'
end

RedmineJiraBridge.log_startup
