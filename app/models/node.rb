require 'short_id'
require 'digest'

LINK_REGEX = /\[([^\[]+)\]\(([^)]+)\)/

class Node < ApplicationRecord
  include PgSearch

  before_save :extract_name
  after_create :set_short_id

  belongs_to :user

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

    hashable = 'ZqcB1SUI4FsjXTlkTWZG' + 'Zencephalon' + count.to_s
    sha = Digest::SHA1.hexdigest hashable
    RestClient.put "https://nanowrimo.org/api/wordcount", {
      hash: sha,
      name: 'Zencephalon',
      wordcount: count
    }
  end

  def word_count
    WordsCounted.count(self.content).token_count
  end

  def set_short_id
    unless self.short_id
      self.short_id = ShortId.int_to_short_id(self.id)
      self.save
    end
  end

  def convert_links_to_short_id
    self.content.scan(LINK_REGEX).each do |match|
      begin
        node = Node.find(match[1])
        self.content = self.content.gsub("](#{match[1]})", "](#{node.short_id})")
      rescue
      end
    end
  end

  def get_links
    links = []
    self.content.scan(LINK_REGEX).each do |match|
      begin
        node = Node.find(match[1])
        links.push(node.id)
      rescue
      end
    end
    return links
  end

  def extract_name
    begin
      self.name = self.content.split('\n')[0].match(/#+\s*(.*)$/)[1]
    rescue
      self.name = 'Untitled'
    end
  end

  def content_without_title
    self.content.start_with?('#') ? self.content.lines[1..-1].join.strip : self.content
  end

  def self.to_export(input, urls)
    content = input

    input.scan(LINK_REGEX).each do |match|
      matched_url = match[1].chomp('!')

      if urls[matched_url]
        content = content.gsub("](#{match[1]})", "](#{urls[matched_url]})")
      end
    end

    input = content

    input.scan(/\{([^{]+)\}\(([^)]+)\)/).each do |match|
      node = Node.find_by(short_id: match[1])
      if node
        content = content.gsub("{#{match[0]}}(#{match[1]})", Node.to_export(node.content_without_title, urls))
      end
    end

    content.gsub!("☐", "* ☐")
    content.gsub!("☑", "* ☑")

    content
  end

  def url(urls)
    counter = 0
    url = "/#{self.name.parameterize}"
    return url unless urls[url]

    while true
      counted_url = "#{url}-#{counter}"
      return counted_url unless urls[counted_url]
      counter += 1
    end
  end
end
