# Redmine Jira Bridge

Bridge Redmine issues into Jira by automatically creating Jira issues when a Redmine ticket reaches an “Accepted” state. The plugin runs inside the bundled Redmine 5.1 container and keeps a simple audit trail of what it sent to Jira.

## What it can do
- Create a Jira issue via the Jira Cloud REST API when a Redmine issue transitions into a configured Accepted status, performed by a user in an allowed role with the `trigger_jira_creation` permission.
- Use per-project settings to pick the Jira project key and default issue type (otherwise falls back to global defaults and the Redmine project identifier).
- Map Redmine priorities to Jira priorities (JSON mapping), carry over labels/tag lists when present, and optionally pass custom field values when a `custom_field_mappings` JSON is provided.
- Store the Jira key back on the issue (attribute or “Jira key” custom field) and add a journal note linking to Jira.
- Show a Jira sync panel in the issue sidebar (for users with `view_jira_link`) that surfaces the latest request/response status from the `jira_sync_logs` table.

## What it does not do (yet)
- No two-way sync: Jira updates, comments, attachments, status changes, and resolutions are not pulled back into Redmine.
- No continuous updates: after the initial creation, further Redmine edits are not pushed to Jira.
- No batching or webhook handling; each transition enqueues a single `JiraCreateJob`.
- Does not provision Jira projects, issue types, or permissions for you—you must supply a working Jira Cloud project and API token.

## Requirements
- Docker/Compose and Make installed locally.
- Jira Cloud account with an API token for the email address you will configure.
- Redmine roles that include the plugin permissions and are referenced in the plugin’s Allowed roles list.

## Local setup
1. Copy environment defaults and fill in credentials:
   - `cp .env.sample .env`
   - Populate `REDMINE_DB_USERNAME`, `REDMINE_DB_PASSWORD`, `REDMINE_DB_MYSQL`, `REDMINE_SECRET_KEY_BASE`, `MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`.
2. Build and start the stack:
   - `make build`
   - `make up`
3. Run the plugin migrations inside the Redmine container (whenever the plugin changes):
   - `make shell`
   - `bundle exec rake redmine:plugins:migrate RAILS_ENV=production`
4. Restart the container if needed: `make down` then `make up` (or `make rebuild` to force a rebuild).

## Configure the plugin
### Global settings (Administration → Plugins → Redmine Jira Bridge → Configure)
- **Jira base URL**: Jira Cloud site, e.g., `https://your-domain.atlassian.net`.
- **Jira account email** and **Jira API token**: email/API token pair with permission to create issues.
- **Accepted status**: the Redmine status that triggers Jira creation.
- **Allowed roles**: at least one role; users must be in one of these roles *and* hold the `trigger_jira_creation` permission on the project.
- **Default Jira issue type**: e.g., `Task`. Used unless overridden per project.
- **Priority mapping**: JSON object mapping Redmine priority names to Jira priority names, e.g. `{ "Low": "Low", "Normal": "Medium", "High": "High" }`.
- **Custom field mappings (advanced)**: supports a JSON object mapping Jira field keys to Redmine custom field names/IDs (e.g., `{ "customfield_12345": "Customer" }`). This setting exists in the plugin configuration payload even though it is not yet exposed in the UI.

### Project-level settings (Project → Settings → Modules → enable “Jira bridge” → Settings tab “Jira bridge”)
- Enable/disable Jira creation for the project.
- Override Jira project key (defaults to the Redmine project identifier/name).
- Override default Jira issue type for this project.

### Permissions and roles
- Grant roles the plugin permissions under Project → Settings → Members → Roles:
  - `trigger_jira_creation` (required to enqueue Jira creation).
  - `view_jira_link` (allows viewing the sidebar sync panel and Jira link).
- Ensure the same roles are selected in the global **Allowed roles** list; both checks are enforced.

## How it works in use
- When an issue moves into the configured Accepted status, the actor is in an allowed role, the project has the Jira bridge module enabled, and the issue is not already linked to Jira, the plugin enqueues `JiraCreateJob`.
- The job builds a payload with summary, project key, issue type, description (including a Redmine link), priority mapping, labels, and mapped custom fields; then calls Jira’s `/rest/api/3/issue`.
- On success, the Jira key is saved on the issue (or in a “Jira key” custom field if present), and a journal entry is added with a link to Jira.
- On failure or retry, details and request/response bodies are stored in `jira_sync_logs`; the latest status is shown in the issue sidebar.

## How this plugin was developed
- I posted my requirements to ChatGPT and asked it to create tickets for a ticket-based development flow.
- I created a Jira project to hold the development tickets and to serve as a test target for the plugin.
- I installed the Codex extension in VS Code and asked Codex to build the plugin and write the test code.
- I reviewed each ticket’s result; when it looked good, I committed it.
- Finally, I asked Codex to produce this README.
