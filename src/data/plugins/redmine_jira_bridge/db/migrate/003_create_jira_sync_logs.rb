class CreateJiraSyncLogs < ActiveRecord::Migration[6.1]
  def change
    create_table :jira_sync_logs do |t|
      t.references :issue, null: false, index: true
      t.string :status, null: false
      t.string :jira_key
      t.integer :response_status
      t.text :request_payload
      t.text :response_body
      t.text :details
      t.timestamps null: false
    end

    add_index :jira_sync_logs, :created_at
  end
end
