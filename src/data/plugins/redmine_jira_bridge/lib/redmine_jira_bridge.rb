require 'logger'
require 'redmine'

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
  end
end
