require 'logger'
require 'stringio'

module RedmineJiraBridge
end unless defined?(RedmineJiraBridge)

module RedmineJiraBridge
  LOGGER_PREFIX = '[test_redmine_jira_bridge]'.freeze unless const_defined?(:LOGGER_PREFIX)

  class << self
    attr_writer :logger_instance
    attr_accessor :jira_base_url_value,
                  :jira_email_value,
                  :jira_api_token_value,
                  :project_configuration_provider,
                  :accepted_status_id_value,
                  :allowed_role_ids_value,
                  :test_priority_mapping,
                  :test_custom_field_mappings,
                  :test_default_issue_type
  end

  def self.reset_test_state!
    self.logger_instance = nil
    self.jira_base_url_value = nil
    self.jira_email_value = nil
    self.jira_api_token_value = nil
    self.project_configuration_provider = nil
    self.accepted_status_id_value = nil
    self.allowed_role_ids_value = nil
    self.test_priority_mapping = nil
    self.test_custom_field_mappings = nil
    self.test_default_issue_type = nil
  end

  def self.logger
    @logger_instance ||= Logger.new(StringIO.new)
  end

  def self.accepted_status_id
    value = accepted_status_id_value
    value.nil? ? nil : value.to_s
  end

  def self.allowed_role_ids
    Array(allowed_role_ids_value).map(&:to_s).reject { |entry| entry.nil? || entry.strip.empty? }
  end

  def self.priority_mapping
    test_priority_mapping || {}
  end

  def self.custom_field_mappings
    test_custom_field_mappings || {}
  end

  def self.default_issue_type
    test_default_issue_type || 'Task'
  end

  def self.jira_base_url
    jira_base_url_value
  end

  def self.jira_email
    jira_email_value
  end

  def self.jira_api_token
    jira_api_token_value
  end

  def self.jira_issue_url(jira_key)
    return nil if jira_base_url_value.to_s.strip.empty? || jira_key.to_s.strip.empty?

    "#{jira_base_url_value.chomp('/')}/browse/#{jira_key}"
  end

  def self.issue_jira_key(issue)
    return nil unless issue

    value = issue.respond_to?(:jira_bridge_jira_key) ? issue.jira_bridge_jira_key : nil
    value.to_s.strip.empty? ? nil : value
  end

  def self.issue_has_jira_key?(issue)
    issue_jira_key(issue).to_s.strip != ''
  end

  def self.project_configuration(project)
    provider = project_configuration_provider
    return provider.call(project) if provider.respond_to?(:call)
    return provider if provider.is_a?(Hash)

    {
      enabled: true,
      jira_project_key: project.respond_to?(:identifier) ? project.identifier : nil,
      default_issue_type: default_issue_type
    }
  end

  def self.project_enabled?(project)
    config = project_configuration(project)
    config.key?(:enabled) ? !!config[:enabled] : true
  end

  def self.project_module_enabled?(project)
    return true unless project.respond_to?(:module_enabled?)

    project.module_enabled?(:jira_bridge)
  rescue StandardError
    false
  end

  def self.latest_sync_log(_issue)
    nil
  end
end
