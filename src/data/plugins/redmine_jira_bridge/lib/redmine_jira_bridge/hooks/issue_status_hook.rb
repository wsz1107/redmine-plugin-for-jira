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
        actor_login = actor.respond_to?(:login) ? actor.login : actor.id

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

        roles = project.roles_for_user(actor)
        roles.any? { |role| allowed_role_ids.include?(role.id.to_s) }
      end
    end
  end
end
