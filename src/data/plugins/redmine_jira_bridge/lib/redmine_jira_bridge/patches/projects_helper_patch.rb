require 'logger'
require 'active_support'

module RedmineJiraBridge
  module Patches
    module ProjectsHelperPatch
      def project_settings_tabs
        tabs = super
        return tabs unless project_settings_tab_visible?
        return tabs if tabs.any? { |tab| tab[:name] == 'jira_bridge' }

        tabs + [jira_bridge_tab_definition]
      end

      private

      def project_settings_tab_visible?
        project = @project if defined?(@project)
        return false unless project
        return false unless RedmineJiraBridge.project_module_enabled?(project)
        return false unless defined?(User) && User.respond_to?(:current)

        user = User.current
        user && user.respond_to?(:allowed_to?) && user.allowed_to?(:edit_project, project)
      end

      def jira_bridge_tab_definition
        {
          name: 'jira_bridge',
          action: :edit_project,
          partial: 'projects/settings/jira_bridge',
          label: :label_jira_bridge_tab
        }
      end
    end
  end
end

ActiveSupport.on_load(:action_controller) do
  next unless defined?(ProjectsHelper)
  helper = ProjectsHelper

  unless helper < RedmineJiraBridge::Patches::ProjectsHelperPatch
    helper.prepend(RedmineJiraBridge::Patches::ProjectsHelperPatch)
  end
end
