RedmineApp::Application.routes.draw do
  put 'projects/:project_id/jira_bridge/settings',
      to: 'redmine_jira_bridge/project_settings#update',
      as: :redmine_jira_bridge_project_settings
end
