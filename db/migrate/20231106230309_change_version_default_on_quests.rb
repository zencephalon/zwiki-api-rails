class ChangeVersionDefaultOnQuests < ActiveRecord::Migration[6.1]
  def up
    change_column_default :quests, :version, from: nil, to: 0
  end
  
  def down
    change_column_default :quests, :version, from: 0, to: nil
  end
end
