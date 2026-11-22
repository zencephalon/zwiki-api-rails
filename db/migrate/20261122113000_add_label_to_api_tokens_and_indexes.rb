class AddLabelToApiTokensAndIndexes < ActiveRecord::Migration[6.1]
  def change
    add_column :api_tokens, :label, :string
    add_index :users, :api_key
    add_index :users, :name
    add_index :nodes, [:user_id, :name]
  end
end
