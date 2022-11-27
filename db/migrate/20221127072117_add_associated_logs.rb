class AddAssociatedLogs < ActiveRecord::Migration[6.1]
  def change
    create_table :associated_logs do |t|
      t.belongs_to :status, foreign_key: { on_delete: :cascade }
      t.belongs_to :account, foreign_key: { on_delete: :cascade }
      t.timestamps
      t.string :label, null: false
      t.json :data
    end
  end
end
