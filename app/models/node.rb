require 'short_id'
require 'digest'

class Node < ApplicationRecord
  include PgSearch

  before_save :extract_name
  after_create :set_short_id

  pg_search_scope :search_for, against: {
    name: 'A',
    content: 'B'
  }, using: {
    tsearch: {
      any_word: true,
      highlight: {
        start_sel: '<b>',
        stop_sel: '</b>'
      },
      prefix: true
    }
  }

  def self.update_word_count
    count = 0
    Node.all.each do |node|
      count += node.word_count
    end

    hashable = 'ZqcB1SUI4FsjXTlkTWZG' + 'Zencephalon' + count
    sha = Digest::SHA1.hexdigest hashable
    RestClient.put "http://nanowrimo.org/api/wordcount", {
      hash: sha,
      name: 'Zencephalon',
      wordcount: count
    }
  end

  def word_count
    WordsCounted.count(self.content)
  end

  def set_short_id
    self.short_id = ShortId.int_to_short_id(self.id)
    self.save
  end

  def convert_links_to_short_id
    self.content.scan(/\[([^\[]+)\]\(([^)]+)\)/).each do |match|
      begin
        node = Node.find(match[1])
        self.content = self.content.gsub("](#{match[1]})", "](#{node.short_id})")
      rescue
      end
    end
  end

  def extract_name
    begin
      self.name = self.content.split('\n')[0].match(/#+\s*(.*)$/)[1]
    rescue
      self.name = 'Untitled'
    end
  end
end
