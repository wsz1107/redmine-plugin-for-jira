require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/object/try'

module RedmineJiraBridge
  class JiraPayloadBuilder
    ValidationError = Class.new(StandardError)

    attr_reader :issue, :options

    def initialize(issue, options = {})
      @issue = issue
      @options = options || {}
    end

    def build
      validate_issue!

      fields = {
        'project' => { 'key' => project_key },
        'summary' => summary,
        'issuetype' => { 'name' => issue_type }
      }

      if (body = build_description).present?
        fields['description'] = body
      end

      if (priority_name = mapped_priority_name).present?
        fields['priority'] = { 'name' => priority_name }
      end

      labels = extract_labels
      fields['labels'] = labels if labels.any?

      build_custom_field_values.each do |jira_key, value|
        fields[jira_key] = value
      end

      { 'fields' => fields }
    end

    private

    def validate_issue!
      raise ValidationError, 'issue must be provided' unless issue
      raise ValidationError, 'project key is required' if project_key.blank?
      raise ValidationError, 'summary is required' if summary.blank?
      raise ValidationError, 'issue type is required' if issue_type.blank?
    end

    def project_key
      @project_key ||= begin
        explicit = option(:project_key) || option(:jira_project_key)
        value = explicit.presence || issue.try(:project).try(:identifier)
        normalize_string(value)
      end
    end

    def summary
      @summary ||= begin
        explicit = option(:summary)
        value = explicit.presence || issue.try(:subject)
        normalize_string(value)
      end
    end

    def issue_type
      @issue_type ||= begin
        explicit = option(:issue_type)
        value = explicit.presence || RedmineJiraBridge.default_issue_type
        normalize_string(value)
      end
    end

    def build_description
      parts = []
      parts << issue_description if issue_description.present?

      if (link = issue_reference_link).present?
        parts << "Redmine issue: #{link}"
      end

      return nil if parts.empty?

      parts.join("\n\n")
    end

    def issue_description
      return @issue_description if defined?(@issue_description)

      explicit = option(:description)
      raw = explicit.nil? ? issue.try(:description) : explicit

      @issue_description =
        if raw.respond_to?(:to_str)
          value = raw.to_str.strip
          value.empty? ? nil : value
        else
          nil
        end
    end

    def issue_reference_link
      explicit = option(:redmine_issue_url)
      return normalize_string(explicit) if explicit.present?

      return nil unless issue.respond_to?(:id)
      return nil unless defined?(Setting)

      host = fetch_setting_value(:host_name)
      return nil if host.blank?

      protocol = fetch_setting_value(:protocol).presence || 'http'
      relative_root = fetch_relative_url_root
      base = "#{protocol}://#{host}"
      base = "#{base}#{relative_root}" if relative_root.present?

      "#{base}/issues/#{issue.id}"
    rescue StandardError
      nil
    end

    def fetch_setting_value(key)
      return nil unless defined?(Setting)

      if Setting.respond_to?(key)
        Setting.public_send(key).to_s
      elsif Setting.respond_to?(:[])
        Setting[key.to_s].to_s
      end
    rescue StandardError
      nil
    end

    def fetch_relative_url_root
      value =
        if defined?(Setting) && Setting.respond_to?(:relative_url_root)
          Setting.relative_url_root
        elsif defined?(Redmine::Configuration)
          Redmine::Configuration['relative_url_root']
        elsif defined?(Rails) && Rails.application.config.respond_to?(:relative_url_root)
          Rails.application.config.relative_url_root
        end

      str = value.to_s.strip
      return '' if str.empty?

      str.start_with?('/') ? str : "/#{str}"
    rescue StandardError
      ''
    end

    def mapped_priority_name
      name = priority_name
      return nil if name.blank?

      mapping = RedmineJiraBridge.priority_mapping
      return mapping[name] if mapping.key?(name)

      downcase_lookup = mapping.each_with_object({}) do |(key, value), memo|
        memo[key.to_s.downcase] = value
      end
      downcase_lookup[name.downcase] || name
    end

    def priority_name
      explicit = option(:priority)
      source = explicit.presence || issue_priority_name
      normalize_string(source)
    end

    def issue_priority_name
      priority = issue.try(:priority)
      if priority.respond_to?(:name)
        priority.name
      elsif priority.respond_to?(:to_s)
        priority.to_s
      end
    end

    def extract_labels
      labels =
        if option_provided?(:labels)
          Array(option(:labels))
        elsif issue.respond_to?(:labels)
          Array(issue.labels)
        elsif issue.respond_to?(:tag_list)
          Array(issue.tag_list)
        else
          []
        end

      labels.map do |value|
        if value.respond_to?(:name)
          value.name
        else
          value
        end
      end.map { |value| normalize_string(value) }.compact.uniq
    end

    def build_custom_field_values
      mapping = RedmineJiraBridge.custom_field_mappings
      return {} if mapping.empty? || !issue.respond_to?(:custom_field_values)

      mapping.each_with_object({}) do |(jira_key, redmine_identifier), memo|
        value = custom_field_value_for(redmine_identifier)
        next if value.blank?

        memo[jira_key] = value
      end
    end

    def custom_field_value_for(identifier)
      return nil if identifier.blank?
      identifier_str = identifier.to_s

      Array(issue.custom_field_values).each do |cf_value|
        cf = cf_value.respond_to?(:custom_field) ? cf_value.custom_field : nil
        name = cf.try(:name).to_s
        id = cf.try(:id).to_s

        next unless identifier_match?(identifier_str, name, id)

        extracted = cf_value.respond_to?(:value) ? cf_value.value : nil
        return normalize_custom_field_value(extracted)
      end

      nil
    end

    def identifier_match?(identifier, name, id)
      return true if name.present? && name.casecmp(identifier).zero?
      return true if id.present? && id == identifier

      false
    end

    def normalize_custom_field_value(value)
      case value
      when Array
        normalized = value.map { |entry| normalize_string(entry) }.compact
        normalized.empty? ? nil : normalized
      else
        normalize_string(value)
      end
    end

    def option(key)
      if options.respond_to?(:key?)
        return options[key] if options.key?(key)
        string_key = key.to_s
        return options[string_key] if options.key?(string_key)
      elsif options.respond_to?(:[])
        value = options[key]
        return value unless value.nil?

        return options[key.to_s]
      end

      nil
    end

    def option_provided?(key)
      return false unless options.respond_to?(:key?)

      options.key?(key) || options.key?(key.to_s)
    end

    def normalize_string(value)
      return nil if value.nil?

      str = value.to_s.strip
      str.empty? ? nil : str
    end
  end
end
