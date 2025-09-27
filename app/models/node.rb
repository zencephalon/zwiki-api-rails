require 'short_id'
require 'digest'
require 'chronic'

LINK_REGEX = /\[([^\[]+)\]\(([^)]+)\)/
INCLUDE_REGEX = /\{([^{]+)\}\(([^)]+)\)/
URL_SAFETY_REGEX = /[&$\+,:;=\?@#\s<>\[\]\{\}[\/]|\\\^%]+/
PRIVACY_FOLD_REGEX = /₴.*₴/
# DATE_REGEX matches format Fri Nov 25 2022
DATE_REGEX = /(Mon|Tue|Wed|Thu|Fri|Sat|Sun) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{1,2}) (\d{4})/

class Node < ApplicationRecord
  include PgSearch::Model

  validates :short_id, uniqueness: true

  before_save :extract_name, :extract_journal_date, :set_slug, :tag_links
  after_create :set_short_id
  after_save :revalidate_cache

  belongs_to :user

  acts_as_taggable_on :links
  acts_as_taggable_tenant :user_id

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

  def self.dedupe
    # find all models and group them on keys which should be common
    grouped = all.group_by{|model| model.short_id }
    grouped.values.each do |duplicates|
      first_one = duplicates.max_by{|model| model.content.length}
      duplicates.filter {|m| m.id != first_one.id}.each(&:destroy)
    end
  end

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

  def is_day_entry
    self.name.match(DATE_REGEX)
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

  def tag_links
    self.link_list = self.get_links.join(",")
  end

  def get_links
    links = []
    self.content.scan(LINK_REGEX).each do |text, short_id|
      next if short_id.starts_with?('http')

      matched_url = short_id.chomp('!')
      links.push(matched_url)
    end
    # puts "found links #{node_names.to_s} in #{self.name}"
    return links
  end

  def extract_name
    begin
      self.name = self.content.split('\n')[0].match(/#+\s*(.*)$/)[1]
    rescue
      self.name = Time.now.to_s
    end
  end

  def set_slug
    return if self.is_private

    slug = self.name.gsub(URL_SAFETY_REGEX, '-').downcase

    return if slug == self.slug && !self.slug.empty?

    if Node.find_by(slug: slug)
      slug += "-#{self.short_id}"
    end

    self.slug = slug
  end

  def extract_journal_date
    begin
      self.journal_date = Chronic.parse(self.name)
    rescue
    end
  end

  def content_without_title
    self.content.start_with?('#') ? self.content.lines[1..-1].join.strip : self.content
  end

  def append(text)
    unless self.content.match(text)
      self.content = "#{self.content}#{text}"
      self.version += 1
    end
  end

  def next_json
    return {
      content: self.to_export,
      name: self.name,
      slug: self.slug,
      created_at: self.created_at,
      updated_at: self.updated_at,
      backlinks: Node.tagged_with(self.short_id).where(is_private: false).pluck(:slug, :name)
    }
  end

  def to_export
    Node.to_export(self.content)
  end

  def self.to_export(input)
    # split over the privacy fold first
    input = input.split(PRIVACY_FOLD_REGEX).first
    content = input

    input.scan(LINK_REGEX).each do |text, short_id|
      next if short_id.starts_with?('http')

      matched_url = short_id.chomp('!')
      linked_node = Node.find_by(short_id: matched_url)

      if !linked_node || linked_node.is_private
        content = content.gsub("[#{text}](#{short_id})", text)
      else
        content = content.gsub("](#{short_id})", "](/#{linked_node.slug})")
      end
    end

    input = content

    input.scan(INCLUDE_REGEX).each do |text, short_id|
      node = Node.find_by(short_id: short_id)
      if node
        content = content.gsub("{#{text}}(#{short_id})", Node.to_export(node.content_without_title))
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

  private

  def revalidate_cache
    return if self.slug.blank? || ENV['REVALIDATION_TOKEN'].blank?

    Thread.new do
      begin
        Rails.logger.info "Revalidating cache for node #{self.slug}"
        RestClient.post(
          "https://zencephalon.com/api/revalidate",
          { slug: self.slug }.to_json,
          {
            content_type: :json,
            accept: :json,
            authorization: "Bearer #{ENV['REVALIDATION_TOKEN']}"
          }
        )
      rescue => e
        Rails.logger.warn "Cache revalidation failed for node #{self.slug}: #{e.message}"
      end
    end
  end
end
