module RedmineJiraBridge
  class ProjectSetting < ActiveRecord::Base
    self.table_name = 'jira_bridge_project_settings'

    belongs_to :project

    validates :project_id, presence: true, uniqueness: true

    scope :enabled, -> { where(enabled: true) }

    def self.for(project)
      return nil unless project.respond_to?(:id) && project.id

      where(project_id: project.id).first
    end

    def enabled?
      value = read_attribute(:enabled)
      value.nil? ? true : value
    end

    def jira_project_key
      normalize_string(read_attribute(:jira_project_key))
    end

    def default_issue_type
      normalize_string(read_attribute(:default_issue_type))
    end

    private

    def normalize_string(value)
      return nil if value.nil?

      str = value.to_s.strip
      str.empty? ? nil : str
    end
  end
end
