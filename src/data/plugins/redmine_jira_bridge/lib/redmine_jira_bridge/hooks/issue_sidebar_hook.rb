module RedmineJiraBridge
  module Hooks
    class IssueSidebarHook < Redmine::Hook::ViewListener
      render_on :view_issues_sidebar_issues_bottom,
                partial: 'redmine_jira_bridge/issue_sync_status'
    end
  end
end
