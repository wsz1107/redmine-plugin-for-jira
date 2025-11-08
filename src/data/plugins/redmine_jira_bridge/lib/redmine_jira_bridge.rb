require 'logger'
require 'redmine'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/object/try'

require_relative 'redmine_jira_bridge/version'

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

    def issue_has_jira_key?(issue)
      return false unless issue

      %i[jira_bridge_jira_key jira_issue_key jira_key].each do |attr|
        next unless issue.respond_to?(attr)

        value = issue.public_send(attr)
        return true if value.present?
      end

      Array(issue.try(:custom_field_values)).any? do |cf_value|
        cf_name = cf_value.try(:custom_field).try(:name).to_s
        next false unless cf_name.present?

        (cf_name.casecmp('jira key').zero? || cf_name.casecmp('jira issue key').zero?) &&
          cf_value.value.present?
      end
    end
  end
end

require_relative 'redmine_jira_bridge/hooks/issue_status_hook'
