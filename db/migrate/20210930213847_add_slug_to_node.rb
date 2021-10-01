class AddSlugToNode < ActiveRecord::Migration[5.2]
  def change
    add_column :nodes, :slug, :string
  end
end
