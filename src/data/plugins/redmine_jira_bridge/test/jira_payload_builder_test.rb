require 'minitest/autorun'
require 'ostruct'

require_relative '../lib/redmine_jira_bridge/jira_payload_builder'

unless RedmineJiraBridge.respond_to?(:priority_mapping)
  module RedmineJiraBridge
    class << self
      attr_accessor :test_priority_mapping, :test_custom_field_mappings, :test_default_issue_type
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
  end
end

unless defined?(Setting)
  class Setting
    class << self
      attr_accessor :host_name_value, :protocol_value, :relative_url_root_value

      def host_name
        host_name_value
      end

      def protocol
        protocol_value
      end

      def relative_url_root
        relative_url_root_value
      end

      def [](key)
        storage[key.to_s]
      end

      def []=(key, value)
        storage[key.to_s] = value
      end

      private

      def storage
        @storage ||= {}
      end
    end
  end
end

module RedmineJiraBridge
  class JiraPayloadBuilderTest < Minitest::Test
    CustomField = Struct.new(:id, :name)
    CustomValue = Struct.new(:custom_field, :value)

    def setup
      Setting.host_name_value = 'redmine.local'
      Setting.protocol_value = 'https'
      Setting.relative_url_root_value = ''
    end

    def test_build_maps_core_fields_and_appends_issue_link
      issue = issue_stub(subject: 'Translate spec', description: 'Line 1', priority: priority_stub('High'))

      payload = with_default_dependencies do
        JiraPayloadBuilder.new(issue, project_key: 'JRI', issue_type: 'Task').build
      end

      assert_equal 'JRI', payload['fields']['project']['key']
      assert_equal 'Task', payload['fields']['issuetype']['name']
      assert_equal 'Translate spec', payload['fields']['summary']
      assert_includes payload['fields']['description'], 'Line 1'
      assert_includes payload['fields']['description'], 'https://redmine.local/issues/42'
    end

    def test_priority_mapping_is_applied_case_insensitively
      issue = issue_stub(subject: 'Translate spec', description: 'Line 1', priority: priority_stub('high'))

      payload = with_mappings(priority: { 'High' => 'Highest' }) do
        JiraPayloadBuilder.new(issue, project_key: 'JRI', issue_type: 'Task').build
      end

      assert_equal 'Highest', payload['fields']['priority']['name']
    end

    def test_custom_field_mapping_uses_values_from_redmine_issue
      customer_cf = CustomField.new(7, 'Customer')
      environment_cf = CustomField.new(9, 'Environment')

      issue = issue_stub(
        subject: 'Translate spec',
        description: 'Line 1',
        custom_field_values: [
          CustomValue.new(customer_cf, 'ACME'),
          CustomValue.new(environment_cf, %w[Staging Sandbox])
        ]
      )

      mapping = {
        'customfield_100' => 'Customer',
        'customfield_200' => '9'
      }

      payload = with_mappings(custom_fields: mapping) do
        JiraPayloadBuilder.new(issue, project_key: 'JRI', issue_type: 'Task').build
      end

      assert_equal 'ACME', payload['fields']['customfield_100']
      assert_equal %w[Staging Sandbox], payload['fields']['customfield_200']
    end

    def test_labels_fall_back_to_issue_tag_list
      issue = issue_stub(subject: 'Translate spec', description: 'Line 1')
      issue.tag_list = %w[redmine jira]

      payload = with_default_dependencies do
        JiraPayloadBuilder.new(issue, project_key: 'JRI', issue_type: 'Task').build
      end

      assert_equal %w[redmine jira], payload['fields']['labels']
    end

    def test_validation_errors_when_required_fields_missing
      issue = issue_stub(subject: '  ', description: 'Line 1')

      error = assert_raises(JiraPayloadBuilder::ValidationError) do
        with_default_dependencies do
          JiraPayloadBuilder.new(issue, project_key: '  ').build
        end
      end

      assert_match(/summary is required/i, error.message)
    end

    def test_validation_error_when_project_key_missing_and_issue_has_no_project
      issue = issue_stub(subject: 'Translate spec', description: 'Line 1', project: nil)

      error = assert_raises(JiraPayloadBuilder::ValidationError) do
        with_default_dependencies do
          JiraPayloadBuilder.new(issue, project_key: '  ').build
        end
      end

      assert_match(/project key is required/i, error.message)
    end

    private

    def issue_stub(subject:, description:, priority: nil, custom_field_values: [], project: :default)
      project = OpenStruct.new(identifier: 'JRI') if project == :default
      OpenStruct.new(
        id: 42,
        subject: subject,
        description: description,
        project: project,
        priority: priority,
        custom_field_values: custom_field_values
      )
    end

    def priority_stub(name)
      OpenStruct.new(name: name)
    end

    def with_default_dependencies
      with_mappings(priority: {}, custom_fields: {}, default_type: 'Task') do
        yield
      end
    end

    def with_mappings(priority: {}, custom_fields: {}, default_type: 'Task')
      previous_priority = RedmineJiraBridge.test_priority_mapping
      previous_custom = RedmineJiraBridge.test_custom_field_mappings
      previous_default = RedmineJiraBridge.test_default_issue_type

      RedmineJiraBridge.test_priority_mapping = priority
      RedmineJiraBridge.test_custom_field_mappings = custom_fields
      RedmineJiraBridge.test_default_issue_type = default_type

      yield
    ensure
      RedmineJiraBridge.test_priority_mapping = previous_priority
      RedmineJiraBridge.test_custom_field_mappings = previous_custom
      RedmineJiraBridge.test_default_issue_type = previous_default
    end
  end
end
