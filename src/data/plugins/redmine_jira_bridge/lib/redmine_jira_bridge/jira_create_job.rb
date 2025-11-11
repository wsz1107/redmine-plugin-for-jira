begin
  require 'active_job'
rescue LoadError
  begin
    require 'active_job/base'
  rescue LoadError
    # ActiveJob is expected to be provided by Redmine/Rails at runtime.
  end
end

unless defined?(ActiveJob::Base)
  module ActiveJob
    class Base
      class << self
        def queue_as(*); end

        def perform_later(*)
          raise NotImplementedError, 'ActiveJob is not available in this environment'
        end
      end

      attr_writer :executions

      def executions
        @executions ||= 0
      end

      def retry_job(*)
        raise NotImplementedError, 'ActiveJob retry is not available in this environment'
      end
    end
  end
end

require_relative 'jira_client'
require_relative 'jira_payload_builder'

module RedmineJiraBridge
  class JiraCreateJob < ActiveJob::Base
    queue_as :default

    MAX_RETRY_ATTEMPTS = 4
    BASE_BACKOFF_SECONDS = 5

    def perform(issue_id, options = {})
      issue = locate_issue(issue_id)
      unless issue
        log(:warn, 'issue_missing', issue_id: issue_id)
        return
      end

      log(:info, 'start', issue_id: issue.id, attempt: attempt_number)

      project_config = RedmineJiraBridge.project_configuration(issue.project)
      unless project_config[:enabled]
        log(:info, 'project_disabled', issue_id: issue.id, project_id: issue.project&.id)
        return
      end

      payload = build_payload(issue, merge_builder_options(project_config, options))
      result = jira_client.create_issue(payload)

      log(:info, 'success',
          issue_id: issue.id,
          attempt: attempt_number,
          jira_key: result['key'],
          jira_id: result['id'])

      jira_key = extract_jira_key(result)
      key_persisted = persist_jira_key(issue, jira_key)
      record_jira_journal(issue, jira_key) if key_persisted

      result
    rescue JiraPayloadBuilder::ValidationError => e
      log(:error, 'payload_validation_failed', issue_id: issue_id, error: e.message)
      raise
    rescue JiraClient::NetworkError => e
      handle_retryable_error('network_error', e, issue_id: issue_id)
    rescue JiraClient::ApiError => e
      if server_error?(e)
        handle_retryable_error('api_error', e, issue_id: issue_id, status: e.status)
      else
        log(:error, 'api_error', issue_id: issue_id, status: e.status, error: e.message)
        raise
      end
    rescue StandardError => e
      log(:error, 'unexpected_error', issue_id: issue_id, error: "#{e.class}: #{e.message}")
      raise
    end

    private

    def locate_issue(issue_or_id)
      return issue_or_id if issue_or_id.respond_to?(:id)

      klass = issue_class
      return nil unless klass

      if klass.respond_to?(:find_by)
        found = klass.find_by(id: issue_or_id)
        return found if found
      end

      return klass.find(issue_or_id) if klass.respond_to?(:find)

      nil
    rescue StandardError => e
      log(:error, 'issue_lookup_failed', issue_id: issue_or_id, error: "#{e.class}: #{e.message}")
      nil
    end

    def issue_class
      defined?(Issue) ? Issue : nil
    end

    def build_payload(issue, options)
      JiraPayloadBuilder.new(issue, options).build
    end

    def jira_client
      @jira_client ||= JiraClient.new(base_url: RedmineJiraBridge.jira_base_url,
                                      email: RedmineJiraBridge.jira_email,
                                      api_token: RedmineJiraBridge.jira_api_token)
    end

    def attempt_number
      executions.to_i + 1
    end

    def retry_available?
      executions.to_i < MAX_RETRY_ATTEMPTS
    end

    def backoff_delay
      BASE_BACKOFF_SECONDS * (2**executions.to_i)
    end

    def handle_retryable_error(event, exception, metadata = {})
      payload = metadata.merge(error: exception.message, attempt: attempt_number)
      if retry_available?
        wait = backoff_delay
        log(:warn, event, payload.merge(wait: wait, action: 'retry'))
        retry_job(wait: wait)
        return
      else
        log(:error, event, payload.merge(action: 'give_up'))
        raise exception
      end
    end

    def server_error?(error)
      error.status.to_i >= 500
    end

    def log(level, event, data = {})
      components = data.map { |key, value| "#{key}=#{format_log_value(value)}" }
      message = "#{LOGGER_PREFIX} job=JiraCreateJob event=#{event}"
      message = "#{message} #{components.join(' ')}" if components.any?
      RedmineJiraBridge.logger.public_send(level, message)
    rescue StandardError
      # Silently ignore logging failures to avoid masking job failures.
      nil
    end

    def format_log_value(value)
      case value
      when NilClass then 'nil'
      else
        value.to_s
      end
    end

    def merge_builder_options(project_config, options)
      config_options = {}

      if project_config && project_config[:jira_project_key].present?
        config_options[:project_key] = project_config[:jira_project_key]
      end

      if project_config && project_config[:default_issue_type].present?
        config_options[:issue_type] = project_config[:default_issue_type]
      end

      config_options.merge(options || {})
    end

    def extract_jira_key(result)
      return nil unless result.respond_to?(:[])

      key = result['key'] || result[:key]
      normalize_string(key)
    end

    def persist_jira_key(issue, jira_key)
      return false if issue.nil? || jira_key.nil?
      return false if RedmineJiraBridge.issue_jira_key(issue).present?

      issue_id = issue_id_for(issue)

      if assign_jira_key_attribute(issue, jira_key)
        log(:info, 'jira_key_persisted', issue_id: issue_id, storage: 'attribute', jira_key: jira_key)
        return true
      end

      if assign_jira_key_custom_field(issue, jira_key)
        log(:info, 'jira_key_persisted', issue_id: issue_id, storage: 'custom_field', jira_key: jira_key)
        return true
      end

      log(:warn, 'jira_key_persist_failed', issue_id: issue_id, jira_key: jira_key, reason: 'no_storage_location')
      false
    end

    def assign_jira_key_attribute(issue, jira_key)
      attr = %i[jira_bridge_jira_key jira_issue_key jira_key].find { |name| issue.respond_to?("#{name}=") }
      return false unless attr

      issue.public_send("#{attr}=", jira_key)
      persist_issue(issue)
    end

    def assign_jira_key_custom_field(issue, jira_key)
      cf_value = find_jira_custom_field_value(issue)
      return false unless cf_value && cf_value.respond_to?(:value=)

      cf_value.value = jira_key
      persist_issue(issue)
    end

    def find_jira_custom_field_value(issue)
      return nil unless issue.respond_to?(:custom_field_values)

      Array(issue.custom_field_values).find do |cf_value|
        cf = cf_value.respond_to?(:custom_field) ? cf_value.custom_field : nil
        name = cf.respond_to?(:name) ? cf.name.to_s : ''
        next false if name.empty?

        name.casecmp('jira key').zero? || name.casecmp('jira issue key').zero?
      end
    end

    def persist_issue(issue)
      return true unless issue.respond_to?(:save)

      issue.save(validate: false)
    rescue ArgumentError
      issue.save
    rescue StandardError => e
      log(:error, 'jira_key_save_failed', issue_id: issue_id_for(issue), error: e.message)
      false
    end

    def record_jira_journal(issue, jira_key)
      return false if issue.nil? || jira_key.nil?
      return false unless issue.respond_to?(:init_journal) && issue.respond_to?(:save)
      return false if journal_entry_exists?(issue, jira_key)

      notes = build_journal_notes(jira_key)
      issue.init_journal(journal_user(issue), notes)
      persist_issue(issue)
    end

    def journal_entry_exists?(issue, jira_key)
      Array(issue.respond_to?(:journals) ? issue.journals : []).any? do |journal|
        journal.respond_to?(:notes) && journal.notes.to_s.include?(jira_key.to_s)
      end
    end

    def build_journal_notes(jira_key)
      url = jira_issue_url(jira_key)
      return "Created Jira issue #{jira_key}" unless url

      "Created Jira issue #{jira_key}: #{url}"
    end

    def jira_issue_url(jira_key)
      base = normalize_string(RedmineJiraBridge.jira_base_url)
      key = normalize_string(jira_key)
      return nil if base.nil? || key.nil?

      "#{base.chomp('/')}/browse/#{key}"
    end

    def journal_user(issue)
      if defined?(User) && User.respond_to?(:current)
        User.current
      elsif issue.respond_to?(:author)
        issue.author
      end
    rescue StandardError
      nil
    end

    def issue_id_for(issue)
      issue.respond_to?(:id) ? issue.id : 'unknown'
    end

    def normalize_string(value)
      return nil if value.nil?

      str = value.to_s.strip
      str.empty? ? nil : str
    end
  end
end
