require 'active_support'

module RedmineJiraBridge
  module Patches
    module ScopeWarningPatch
      private

      def valid_scope_name?(name)
        super if singleton_defines_method?(name)
      end

      def singleton_defines_method?(name)
        eigen = singleton_class
        name = name.to_sym
        eigen.instance_methods(false).include?(name) ||
          eigen.private_instance_methods(false).include?(name) ||
          eigen.protected_instance_methods(false).include?(name)
      end
    end
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::Scoping::Named::ClassMethods.prepend(
    RedmineJiraBridge::Patches::ScopeWarningPatch
  )
end
