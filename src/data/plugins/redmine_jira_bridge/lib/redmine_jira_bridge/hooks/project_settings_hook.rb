module RedmineJiraBridge
  module Hooks
    class ProjectSettingsHook < Redmine::Hook::ViewListener
      def view_projects_settings_tabs(context = {})
        project = context[:project]
        tabs = context[:tabs]
        return unless project && tabs

        tabs << {
          name: 'jira_bridge',
          action: :manage_project,
          partial: 'projects/settings/jira_bridge',
          label: 'Jira'
        }
      end
    end
  end
end
