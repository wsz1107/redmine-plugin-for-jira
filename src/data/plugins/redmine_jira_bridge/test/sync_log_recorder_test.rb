require 'minitest/autorun'
require 'ostruct'

module RedmineJiraBridge
  remove_const(:JiraSyncLog) if const_defined?(:JiraSyncLog)

  class JiraSyncLog
    attr_reader :attributes, :updates

    class << self
      attr_accessor :created_records

      def reset!
        self.created_records = []
      end
    end

    def self.create!(attrs)
      record = new(attrs)
      self.created_records ||= []
      self.created_records << record
      record
    end

    def initialize(attrs)
      @attributes = attrs.dup
      @updates = []
    end

    def update(attrs)
      @updates << attrs
      @attributes.merge!(attrs)
      true
    end
  end
end

require_relative '../lib/redmine_jira_bridge/sync_log_recorder'

module RedmineJiraBridge
  class SyncLogRecorderTest < Minitest::Test
    def setup
      JiraSyncLog.reset!
    end

    def test_record_start_persists_payload_as_json
      issue = OpenStruct.new(id: 42)
      recorder = SyncLogRecorder.new(issue)
      recorder.record_start('{"fields":{"summary":"Spec"}}')

      assert_equal 1, JiraSyncLog.created_records.size
      record = JiraSyncLog.created_records.first
      assert_equal 42, record.attributes[:issue_id]
      assert_equal 'pending', record.attributes[:status]
      assert_equal '{"fields":{"summary":"Spec"}}', record.attributes[:request_payload]
    end

    def test_mark_success_updates_existing_record
      issue = OpenStruct.new(id: 7)
      recorder = SyncLogRecorder.new(issue)
      recorder.record_start({ 'fields' => { 'summary' => 'Spec' } })

      recorder.mark_success!(jira_key: 'JRI-1', response: { 'id' => '100' })

      record = JiraSyncLog.created_records.first
      refute_nil record
      assert_includes record.updates.last[:details], 'JRI-1'
      assert_equal 'success', record.updates.last[:status]
      assert_includes record.updates.last[:response_body], '"id": "100"'
    end

    def test_mark_failure_sets_status_and_message
      issue = 5
      recorder = SyncLogRecorder.new(issue)
      recorder.record_start({})
      recorder.mark_failure!(message: 'Network timeout', status: 503)

      record = JiraSyncLog.created_records.first
      assert_equal 'failed', record.updates.last[:status]
      assert_equal 503, record.updates.last[:response_status]
      assert_equal 'Network timeout', record.updates.last[:details]
    end

    def test_handles_missing_issue_id
      recorder = SyncLogRecorder.new(nil)
      recorder.record_start({})
      assert_equal [], RedmineJiraBridge::JiraSyncLog.created_records
    end
  end
end
