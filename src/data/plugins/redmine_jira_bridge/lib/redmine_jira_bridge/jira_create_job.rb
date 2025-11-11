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

      payload = build_payload(issue, options || {})
      result = jira_client.create_issue(payload)

      log(:info, 'success',
          issue_id: issue.id,
          attempt: attempt_number,
          jira_key: result['key'],
          jira_id: result['id'])

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
  end
end
