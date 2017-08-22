class ConvertLinks < ActiveRecord::Migration[5.0]
  def change
    Node.all.each do |node|
      node.convert_links_to_short_id
      node.save
    end
  end
end
