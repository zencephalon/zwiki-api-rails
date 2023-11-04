class CreateQuests < ActiveRecord::Migration[6.1]
  def change
    create_table :quests do |t|
      t.references :user, foreign_key: true
      t.json :blob

      t.timestamps
    end
  end
end
