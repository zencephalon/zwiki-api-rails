class AddIndexesToNode < ActiveRecord::Migration[5.2]
  def change
    add_index(:nodes, :short_id)
    add_index(:nodes, :slug)
  end
end
