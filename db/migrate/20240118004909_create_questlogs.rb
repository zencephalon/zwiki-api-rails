class CreateQuestlogs < ActiveRecord::Migration[6.1]
  def change
    create_table :questlogs do |t|
      t.references :user, foreign_key: true
      t.string :description
      t.boolean :private

      t.timestamps
    end
  end
end
