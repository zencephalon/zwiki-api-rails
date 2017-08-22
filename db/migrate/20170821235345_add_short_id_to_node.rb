class AddShortIdToNode < ActiveRecord::Migration[5.0]
  def change
    add_column :nodes, :short_id, :string

    Node.all.each do |node|
      node.set_short_id
      node.save
    end
  end
end
