module RedmineJiraBridge
  class ProjectSettingsController < ::ApplicationController
    before_action :find_project
    before_action :authorize_manage_project!

    helper :projects

    def update
      setting = find_or_initialize_setting
      apply_attributes(setting)

      if setting.save
        flash[:notice] = l(:notice_successful_update)
      else
        flash[:error] = setting.errors.full_messages
      end

      redirect_to settings_project_path(@project, tab: 'jira_bridge')
    end

    private

    def find_project
      @project = Project.find(params[:project_id])
    rescue ActiveRecord::RecordNotFound
      render_404
    end

    def authorize_manage_project!
      return if User.current.allowed_to?(:manage_project, @project)

      render_403
    end

    def find_or_initialize_setting
      RedmineJiraBridge::ProjectSetting.for(@project) ||
        RedmineJiraBridge::ProjectSetting.new(project: @project)
    end

    def apply_attributes(setting)
      attrs = project_setting_params

      setting.enabled = attrs[:enabled]
      setting.jira_project_key = blank_to_nil(attrs[:jira_project_key])
      setting.default_issue_type = blank_to_nil(attrs[:default_issue_type])
    end

    def blank_to_nil(value)
      str = value.to_s.strip
      str.empty? ? nil : str
    end

    def project_setting_params
      params.require(:jira_bridge)
            .permit(:enabled, :jira_project_key, :default_issue_type)
            .tap do |permitted|
              permitted[:enabled] = cast_boolean(permitted[:enabled])
            end
    end

    def cast_boolean(value)
      return false if value.nil?

      !%w[0 false].include?(value.to_s.strip.downcase)
    end
  end
end
