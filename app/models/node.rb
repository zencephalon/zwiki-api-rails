class Node < ApplicationRecord
  include PgSearch

  before_save :extract_name

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

  def extract_name
    self.name = self.content.split('\n')[0].match(/#+\s*(.*)$/)[1]
  end
end
