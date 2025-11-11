class CreateJiraBridgeProjectSettings < ActiveRecord::Migration[6.1]
  def change
    create_table :jira_bridge_project_settings do |t|
      t.references :project, null: false, index: { unique: true }
      t.boolean :enabled, null: false, default: true
      t.string :jira_project_key, limit: 255
      t.string :default_issue_type, limit: 255
      t.timestamps null: false
    end
  end
end
