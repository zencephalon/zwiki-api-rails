class AddVersionToNode < ActiveRecord::Migration[5.0]
  def change
    add_column :nodes, :version, :integer, default: 0
  end
end
