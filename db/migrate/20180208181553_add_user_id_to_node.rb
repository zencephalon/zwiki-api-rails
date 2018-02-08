class AddUserIdToNode < ActiveRecord::Migration[5.0]
  def change
    add_reference :nodes, :user, foreign_key: true, index: true
  end
end
