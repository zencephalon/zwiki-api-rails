class AddPrivateToNode < ActiveRecord::Migration[5.0]
  def change
    add_column :nodes, :is_private, :boolean, default: true
  end
end
