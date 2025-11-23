require 'json'

module RedmineJiraBridge
  class JiraSyncLog < ActiveRecord::Base
    self.table_name = 'jira_sync_logs'

    STATUSES = %w[pending success failed retry].freeze

    validates :issue_id, presence: true
    validates :status, presence: true

    scope :recent_first, -> { order(created_at: :desc) }

    class << self
      def latest_for(issue)
        issue_id = issue_id_for(issue)
        return nil unless issue_id

        where(issue_id: issue_id).recent_first.first
      end

      private

      def issue_id_for(issue)
        return issue if issue.is_a?(Integer)

        issue.respond_to?(:id) ? issue.id : nil
      end
    end

    def request_payload=(value)
      super(coerce_json_payload(value))
    end

    def response_body=(value)
      super(coerce_json_payload(value))
    end

    def status
      super.to_s
    end

    private

    def coerce_json_payload(value)
      return value if value.nil? || value.is_a?(String)

      JSON.pretty_generate(value)
    rescue StandardError
      value.to_s
    end
  end
end
