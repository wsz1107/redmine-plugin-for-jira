module RedmineJiraBridge
  module Version
    STRING = '0.1.0'.freeze

    def self.to_s
      STRING
    end
  end

  VERSION = Version::STRING
end
