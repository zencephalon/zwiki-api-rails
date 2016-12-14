class Node < ApplicationRecord
  include PgSearch

  pg_search_scope :search_for, against: :content, using: {
    tsearch: {
      any_word: true,
      highlight: {
        start_sel: '<b>',
        stop_sel: '</b>'
      },
      prefix: true
    }
  }
end
