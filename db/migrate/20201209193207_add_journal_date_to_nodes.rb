class AddJournalDateToNodes < ActiveRecord::Migration[5.2]
  def change
    add_column :nodes, :journal_date, :datetime
  end
end
