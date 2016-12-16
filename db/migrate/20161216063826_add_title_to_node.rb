class AddTitleToNode < ActiveRecord::Migration[5.0]
  def change
    add_column :nodes, :title, :string
  end
end
