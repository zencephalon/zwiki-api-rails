class AddPublicRootIdToUser < ActiveRecord::Migration[5.2]
  def change
    add_column :users, :public_root_id, :string
  end
end
