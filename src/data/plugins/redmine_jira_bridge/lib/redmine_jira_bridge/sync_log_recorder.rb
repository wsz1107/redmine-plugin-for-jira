require 'json'

module RedmineJiraBridge
  class SyncLogRecorder
    attr_reader :issue_id, :record

    def initialize(issue)
      @issue_id = extract_issue_id(issue)
    end

    def record_start(payload)
      return unless issue_id

      with_model do |model|
        @record = model.create!(
          issue_id: issue_id,
          status: 'pending',
          request_payload: encode(payload)
        )
      end
    rescue StandardError => e
      log_storage_failure('create', e)
      nil
    end

    def mark_success!(jira_key:, response: nil)
      update_record(
        status: 'success',
        jira_key: jira_key,
        response_body: encode(response),
        details: success_details(jira_key)
      )
    end

    def mark_failure!(message:, response: nil, status: nil)
      update_record(
        status: 'failed',
        response_body: encode(response),
        response_status: status,
        details: message
      )
    end

    def mark_retry!(message:, response: nil, status: nil)
      update_record(
        status: 'retry',
        response_body: encode(response),
        response_status: status,
        details: message
      )
    end

    private

    def with_model
      model = model_class
      return unless model

      yield model
    end

    def model_class
      return nil unless defined?(RedmineJiraBridge::JiraSyncLog)

      RedmineJiraBridge::JiraSyncLog
    rescue NameError
      nil
    end

    def update_record(attributes)
      return unless record

      record.update(attributes)
    rescue StandardError => e
      log_storage_failure('update', e)
      nil
    end

    def encode(payload)
      return nil if payload.nil?
      return payload if payload.is_a?(String)

      JSON.pretty_generate(payload)
    rescue StandardError
      payload.to_s
    end

    def success_details(jira_key)
      key = jira_key.to_s.strip
      return 'Jira issue created successfully' if key.empty?

      "Created Jira issue #{key}"
    end

    def extract_issue_id(issue)
      return issue if issue.is_a?(Integer)
      return issue.id if issue.respond_to?(:id)

      nil
    end

    def log_storage_failure(action, error)
      RedmineJiraBridge.logger.debug("#{LOGGER_PREFIX} sync_log_#{action}_failed issue_id=#{issue_id || 'unknown'} error=#{error.class}: #{error.message}")
    rescue StandardError
      nil
    end
  end
end
