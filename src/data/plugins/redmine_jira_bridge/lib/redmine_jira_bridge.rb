require 'json'
require 'logger'
require 'redmine'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/object/try'

require_relative 'redmine_jira_bridge/version'
require_relative 'redmine_jira_bridge/jira_client'
require_relative 'redmine_jira_bridge/jira_payload_builder'
require_relative 'redmine_jira_bridge/jira_create_job'

module RedmineJiraBridge
  LOGGER_PREFIX = '[redmine_jira_bridge]'.freeze

  class << self
    def logger
      return Rails.logger if defined?(Rails) && Rails.logger

      @logger ||= Logger.new($stdout)
    end

    def log_startup
      logger.info("#{LOGGER_PREFIX} Plugin initialized")
    end

    def configuration
      Setting.plugin_redmine_jira_bridge || {}
    rescue StandardError
      {}
    end

    def accepted_status_id
      value = configuration['accepted_status_id']
      value.present? ? value.to_s : nil
    end

    def allowed_role_ids
      raw = configuration['allowed_role_ids']
      values =
        case raw
        when String
          raw.split(/[\s,]+/)
        else
          Array(raw)
        end

      values.map(&:to_s).reject(&:blank?)
    end

    def jira_base_url
      normalize_string(configuration['jira_base_url'])
    end

    def jira_email
      normalize_string(configuration['jira_email'])
    end

    def jira_api_token
      normalize_string(configuration['jira_api_token'])
    end

    def default_issue_type
      normalize_string(configuration['default_issue_type'])
    end

    def priority_mapping
      parse_simple_mapping(configuration['priority_mapping'], 'priority mapping')
    end

    def custom_field_mappings
      raw = configuration['custom_field_mappings']
      data = parse_json_structure(raw, 'custom field mappings')

      case data
      when Hash
        data.each_with_object({}) do |(jira_key, redmine_identifier), memo|
          jira = normalize_string(jira_key)
          redmine = normalize_string(redmine_identifier)
          memo[jira] = redmine if jira && redmine
        end
      when Array
        data.each_with_object({}) do |entry, memo|
          next unless entry.is_a?(Hash)

          jira = normalize_string(entry['jira'] || entry['jira_field'] || entry['jiraField'])
          redmine = normalize_string(entry['redmine'] || entry['redmine_field'] || entry['redmineField'])
          memo[jira] = redmine if jira && redmine
        end
      else
        {}
      end
    end

    def project_configuration(project)
      base = {
        enabled: true,
        jira_project_key: project_identifier(project),
        default_issue_type: default_issue_type
      }

      record = project_setting_record(project)
      return base unless record

      base[:enabled] = record.enabled?
      base[:jira_project_key] = record.jira_project_key if record.jira_project_key.present?
      base[:default_issue_type] = record.default_issue_type if record.default_issue_type.present?

      base
    end

    def project_enabled?(project)
      project_configuration(project)[:enabled]
    end

    def project_setting(project)
      project_setting_record(project)
    end

    def issue_has_jira_key?(issue)
      issue_jira_key(issue).present?
    end

    def issue_jira_key(issue)
      return nil unless issue

      %i[jira_bridge_jira_key jira_issue_key jira_key].each do |attr|
        next unless issue.respond_to?(attr)

        value = issue.public_send(attr)
        return value if value.present?
      end

      Array(issue.try(:custom_field_values)).each do |cf_value|
        cf_name = cf_value.try(:custom_field).try(:name).to_s
        next unless cf_name.present?
        next unless cf_name.casecmp('jira key').zero? || cf_name.casecmp('jira issue key').zero?

        value = cf_value.try(:value)
        return value if value.present?
      end

      nil
    end

    private

    def project_setting_record(project)
      return nil unless defined?(RedmineJiraBridge::ProjectSetting)
      return nil unless project.respond_to?(:id) && project.id

      RedmineJiraBridge::ProjectSetting.for(project)
    rescue StandardError => e
      logger.warn("#{LOGGER_PREFIX} Failed to load project setting for project #{project&.id}: #{e.class}: #{e.message}")
      nil
    end

    def project_identifier(project)
      return nil unless project

      value =
        if project.respond_to?(:identifier)
          project.identifier
        elsif project.respond_to?(:name)
          project.name
        end

      normalize_string(value)
    end

    def normalize_string(value)
      return nil if value.nil?

      str = value.to_s.strip
      str.present? ? str : nil
    end

    def parse_simple_mapping(raw, label)
      data = parse_json_structure(raw, label)
      return {} unless data.is_a?(Hash)

      data.each_with_object({}) do |(key, value), memo|
        normalized_key = normalize_string(key)
        normalized_value = normalize_string(value)
        memo[normalized_key] = normalized_value if normalized_key && normalized_value
      end
    end

    def parse_json_structure(raw, label)
      return raw if raw.is_a?(Hash) || raw.is_a?(Array)

      str = normalize_string(raw)
      return {} if str.nil?

      JSON.parse(str)
    rescue JSON::ParserError => e
      logger.warn("#{LOGGER_PREFIX} Failed to parse #{label}: #{e.message}")
      {}
    end
  end
end

require_relative 'redmine_jira_bridge/settings_validator'
require_relative 'redmine_jira_bridge/patches/scope_warning_patch'
require_relative 'redmine_jira_bridge/hooks/issue_status_hook'
require_relative 'redmine_jira_bridge/hooks/project_settings_hook'
