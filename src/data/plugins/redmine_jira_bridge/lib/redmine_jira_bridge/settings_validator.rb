require 'uri'
require 'active_support/core_ext/object/blank'

module RedmineJiraBridge
  class SettingsValidator
    attr_reader :settings, :errors

    def initialize(settings)
      @settings = (settings || {}).dup
      @errors = []
      validate
    end

    def valid?
      errors.empty?
    end

    private

    def validate
      validate_jira_base_url
      validate_jira_email
      validate_jira_api_token
      validate_accepted_status
      validate_allowed_roles
      validate_default_issue_type
    end

    def validate_jira_base_url
      value = normalize(settings['jira_base_url'])
      if value.blank?
        errors << 'Jira base URL cannot be blank.'
      elsif value !~ %r{\Ahttps?://}i
        errors << 'Jira base URL must start with http:// or https://.'
      end
    end

    def validate_jira_email
      value = normalize(settings['jira_email'])
      if value.blank?
        errors << 'Jira account email cannot be blank.'
      elsif defined?(URI::MailTo::EMAIL_REGEXP) && value !~ URI::MailTo::EMAIL_REGEXP
        errors << 'Jira account email looks invalid.'
      end
    end

    def validate_jira_api_token
      value = normalize(settings['jira_api_token'])
      errors << 'Jira API token cannot be blank.' if value.blank?
    end

    def validate_accepted_status
      value = normalize(settings['accepted_status_id'])
      if value.blank?
        errors << 'Select an Accepted status.'
        return
      end

      return unless defined?(IssueStatus)

      errors << 'Selected Accepted status does not exist.' unless IssueStatus.where(id: value).exists?
    end

    def validate_allowed_roles
      ids = Array(settings['allowed_role_ids']).map { |v| normalize(v) }.compact
      if ids.empty?
        errors << 'Choose at least one allowed role.'
        return
      end

      return unless defined?(Role)

      missing = ids - Role.where(id: ids).pluck(:id).map(&:to_s)
      errors << "Unknown roles selected: #{missing.join(', ')}." if missing.any?
    end

    def validate_default_issue_type
      value = normalize(settings['default_issue_type'])
      errors << 'Default Jira issue type cannot be blank.' if value.blank?
    end

    def normalize(value)
      return nil if value.nil?

      value.to_s.strip.presence
    end
  end
end
