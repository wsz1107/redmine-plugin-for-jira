require 'active_support/core_ext/object/try'

module RedmineJiraBridge
  module Hooks
    class IssueStatusHook < Redmine::Hook::Listener
      def controller_issues_edit_after_save(context = {})
        issue = context[:issue]
        journal = context[:journal]
        return unless issue && journal

        accepted_status_id = RedmineJiraBridge.accepted_status_id
        if accepted_status_id.blank?
          RedmineJiraBridge.logger.debug("#{RedmineJiraBridge::LOGGER_PREFIX} Skipping status hook, accepted status id is not configured")
          return
        end

        unless status_transition_to_target?(journal, accepted_status_id)
          RedmineJiraBridge.logger.debug("#{RedmineJiraBridge::LOGGER_PREFIX} No accepted status transition detected for issue ##{issue.id}")
          return
        end

        if RedmineJiraBridge.issue_has_jira_key?(issue)
          RedmineJiraBridge.logger.debug("#{RedmineJiraBridge::LOGGER_PREFIX} Issue ##{issue.id} already has a Jira key, skipping trigger")
          return
        end

        actor = journal.user || User.current
        unless actor_allowed_for_issue?(issue, actor)
          RedmineJiraBridge.logger.debug("#{RedmineJiraBridge::LOGGER_PREFIX} User #{actor&.login || 'unknown'} is not permitted to trigger Jira creation for issue ##{issue.id}")
          return
        end

        project = issue.project
        unless project && RedmineJiraBridge.project_enabled?(project)
          RedmineJiraBridge.logger.debug("#{RedmineJiraBridge::LOGGER_PREFIX} Project #{project&.identifier || project&.id || 'unknown'} is not enabled for Jira sync; skipping issue ##{issue.id}")
          return
        end

        RedmineJiraBridge.logger.info("#{RedmineJiraBridge::LOGGER_PREFIX} Accepted transition detected for issue ##{issue.id} by #{actor.login}")
        RedmineJiraBridge::JiraCreateJob.perform_later(issue.id)
        RedmineJiraBridge.logger.info("#{RedmineJiraBridge::LOGGER_PREFIX} Enqueued JiraCreateJob for issue ##{issue.id}")
      end

      private

      def status_transition_to_target?(journal, target_status_id)
        Array(journal.details).any? do |detail|
          next false unless detail.property == 'attr' && detail.prop_key == 'status_id'

          detail.value.to_s == target_status_id.to_s &&
            detail.value.to_s != detail.old_value.to_s
        end
      end

      def actor_allowed_for_issue?(issue, actor)
        return false unless issue && actor

        project = issue.project
        actor_login = actor.respond_to?(:login) ? actor.login : actor.try(:id)

        unless project
          RedmineJiraBridge.logger.debug("#{RedmineJiraBridge::LOGGER_PREFIX} Missing project for issue ##{issue.id}; cannot authorize #{actor_login || 'unknown'}")
          return false
        end

        unless actor.respond_to?(:allowed_to?) && actor.allowed_to?(:trigger_jira_creation, project)
          RedmineJiraBridge.logger.debug("#{RedmineJiraBridge::LOGGER_PREFIX} User #{actor_login || 'unknown'} lacks :trigger_jira_creation permission on project #{project.identifier || project.id}")
          return false
        end

        allowed_role_ids = RedmineJiraBridge.allowed_role_ids
        if allowed_role_ids.empty?
          RedmineJiraBridge.logger.debug("#{RedmineJiraBridge::LOGGER_PREFIX} Allowed role list is empty; skipping Jira trigger for issue ##{issue.id}")
          return false
        end

        roles = project_roles_for_actor(project, actor)
        if roles.empty?
          RedmineJiraBridge.logger.debug("#{RedmineJiraBridge::LOGGER_PREFIX} Unable to determine roles for #{actor_login || 'unknown'} on project #{project_identifier(project)}")
          return false
        end

        roles.any? { |role| allowed_role_ids.include?(role.id.to_s) }
      end

      def project_roles_for_actor(project, actor)
        return [] unless project && actor

        if project.respond_to?(:roles_for_user)
          safe_role_lookup(project, actor) { project.roles_for_user(actor) }
        elsif actor.respond_to?(:roles_for_project)
          safe_role_lookup(project, actor) { actor.roles_for_project(project) }
        else
          membership_roles_for_actor(project, actor)
        end
      end

      def safe_role_lookup(project, actor)
        Array(yield).compact
      rescue StandardError => e
        RedmineJiraBridge.logger.warn("#{RedmineJiraBridge::LOGGER_PREFIX} Failed to load roles for #{actor.try(:login) || actor.try(:id) || 'unknown'} on project #{project_identifier(project)}: #{e.class}: #{e.message}")
        []
      end

      def membership_roles_for_actor(project, actor)
        return [] unless project.respond_to?(:memberships)

        membership_scope = project.memberships
        principal_id = actor.try(:id) || actor.try(:principal_id)
        return [] unless principal_id

        membership =
          if membership_scope.respond_to?(:where)
            load_membership_record(membership_scope, principal_id)
          else
            Array(membership_scope).find do |member|
              (member.respond_to?(:user_id) && member.user_id == principal_id) ||
                (member.respond_to?(:principal_id) && member.principal_id == principal_id)
            end
          end

        Array(membership&.roles).compact
      rescue StandardError => e
        RedmineJiraBridge.logger.warn("#{RedmineJiraBridge::LOGGER_PREFIX} Failed to load membership roles for #{actor.try(:login) || principal_id || 'unknown'} on project #{project_identifier(project)}: #{e.class}: #{e.message}")
        []
      end

      def load_membership_record(scope, principal_id)
        record = scope.where(user_id: principal_id).includes(:roles).first
        return record if record

        scope.where(principal_id: principal_id).includes(:roles).first
      end

      def project_identifier(project)
        project.try(:identifier) || project.try(:id) || 'unknown'
      end

    end
  end
end
