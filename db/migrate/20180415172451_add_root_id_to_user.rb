class AddRootIdToUser < ActiveRecord::Migration[5.0]
  def change
    add_column :users, :root_id, :string
  end
end
