class AddVersionToQuests < ActiveRecord::Migration[6.1]
  def change
    add_column :quests, :version, :integer
  end
end
