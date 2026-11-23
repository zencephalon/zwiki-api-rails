require 'short_id'
require 'digest'
require 'chronic'
require 'securerandom'

LINK_REGEX = /\[([^\[]+)\]\(([^)]+)\)/
INCLUDE_REGEX = /\{([^{]+)\}\(([^)]+)\)/
URL_SAFETY_REGEX = /[&$\+,:;=\?@#\s<>\[\]\{\}[\/]|\\\^%]+/
PRIVACY_FOLD_REGEX = /₴.*₴/
# Short_id alphabet characters that break acts-as-taggable's case-insensitive
# lookup (locale-dependent case folding), corrupting any node linked from them.
PROBLEMATIC_SHORT_ID_CHARS = %w[İ].freeze
GLOSSARY_SUFFIX = 'Glossary'.freeze
# DATE_REGEX matches format Fri Nov 25 2022
DATE_REGEX = /(Mon|Tue|Wed|Thu|Fri|Sat|Sun) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{1,2}) (\d{4})/

class Node < ApplicationRecord
  include PgSearch::Model

  validates :short_id, uniqueness: true

  before_save :extract_name, :extract_journal_date, :set_slug, :tag_links, :tag_inclusions
  after_create :set_short_id
  after_commit :revalidate_cache, on: [:create, :update]

  belongs_to :user

  acts_as_taggable_on :links, :inclusions
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

  def is_day_entry
    self.name.match(DATE_REGEX)
  end

  # Zencephalon auto-links terms defined by any node named "… Glossary".
  # Privacy stays out of it, so turning a public glossary private still
  # clears the terms it used to publish.
  def is_glossary?
    self.name.to_s.strip.end_with?(GLOSSARY_SUFFIX)
  end

  def word_count
    WordsCounted.count(self.content).token_count
  end

  def set_short_id
    unless self.short_id
      candidate = ShortId.int_to_short_id(self.id)
      # Some alphabet characters (Turkish dotted-I, İ) break acts-as-taggable's
      # case-insensitive tag lookup, so any node linked from such a short_id
      # fails to save. Fall back to a safe ASCII short_id in that case.
      candidate = generate_safe_short_id if PROBLEMATIC_SHORT_ID_CHARS.any? { |c| candidate.include?(c) }
      self.short_id = candidate
      self.save
    end
  end

  def generate_safe_short_id
    loop do
      candidate = SecureRandom.alphanumeric(6)
      return candidate unless Node.exists?(short_id: candidate)
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
    self.link_list = self.get_links.reject(&:blank?).join(",")
  end

  def tag_inclusions
    self.inclusion_list = self.get_inclusions.reject(&:blank?).join(",")
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

  def get_inclusions
    inclusions = []
    self.content.scan(INCLUDE_REGEX).each do |text, short_id|
      inclusions.push(short_id)
    end
    inclusions
  end

  def extract_name
    first_line = self.content.to_s.lines.first&.chomp
    match = first_line&.match(/\A#+\s*(.+)\z/)
    extracted = match && match[1].strip
    self.name = extracted.present? ? extracted : Time.now.to_s
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

  def fill_default_content
    return if self.content

    self.content = "# #{self.name}\n\n"
    if is_day_entry
      day_template = self.user.nodes.find_by(name: '__journal_template__')
      self.content += day_template.content_without_title if day_template
    end
  end

  def content_without_title
    self.content.start_with?('#') ? self.content.lines[1..-1].join.strip : self.content
  end

  def append(text)
    unless self.content.include?(text)
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
      backlinks: user.nodes.tagged_with(self.short_id, on: :links).where(is_private: false).pluck(:slug, :name)
    }
  end

  def to_export
    Node.to_export(self.content, user_id: self.user_id, visited: Set.new([self.id]))
  end

  def self.to_export(input, user_id: nil, visited: Set.new)
    # split over the privacy fold first
    input = input.to_s.split(PRIVACY_FOLD_REGEX).first.to_s
    content = input
    scope = user_id ? Node.where(user_id: user_id) : Node.all

    input.scan(LINK_REGEX).each do |text, short_id|
      next if short_id.starts_with?('http')

      matched_url = short_id.chomp('!')
      linked_node = scope.find_by(short_id: matched_url)

      if !linked_node || linked_node.is_private
        content = content.gsub("[#{text}](#{short_id})", text)
      else
        content = content.gsub("](#{short_id})", "](/#{linked_node.slug})")
      end
    end

    input = content

    input.scan(INCLUDE_REGEX).each do |text, short_id|
      node = scope.find_by(short_id: short_id)
      if !node || visited.include?(node.id)
        content = content.gsub("{#{text}}(#{short_id})", "")
      else
        expanded = Node.to_export(
          node.content_without_title,
          user_id: user_id || node.user_id,
          visited: visited + [node.id]
        )
        content = content.gsub("{#{text}}(#{short_id})") { expanded }
      end
    end

    content = content.gsub("☐", "* ☐").gsub("☑", "* ☑")

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

  def collect_affected_nodes(max_depth: 10)
    affected = Set.new
    visited = Set.new
    queue = [[self, 0]]

    while queue.any?
      current_node, depth = queue.shift
      next if visited.include?(current_node.id)

      visited.add(current_node.id)

      # Only look for includers if we haven't reached max depth
      next if depth >= max_depth

      includers = user.nodes.tagged_with(current_node.short_id, on: :inclusions)
      includers.each do |includer|
        unless visited.include?(includer.id)
          affected.add(includer)
          queue.push([includer, depth + 1])
        end
      end
    end

    affected
  end

  private

  def revalidate_cache
    return if ENV['REVALIDATION_TOKEN'].blank?

    if is_glossary? && (!self.is_private || saved_change_to_is_private?)
      # Glossary terms link from anywhere, so an edit changes every page.
      payload = { all: true }
      description = "every page (glossary edit)"
    else
      slugs_to_revalidate = Set.new
      if !self.is_private || saved_change_to_is_private?
        slugs_to_revalidate.add(self.slug) if self.slug.present?
        if saved_change_to_slug? && slug_before_last_save.present?
          slugs_to_revalidate.add(slug_before_last_save)
        end
      end

      collect_affected_nodes.each do |node|
        slugs_to_revalidate.add(node.slug) if !node.is_private && node.slug.present?
      end

      return if slugs_to_revalidate.empty?

      paths = slugs_to_revalidate.map { |slug| "/#{slug}" } + [
        "/",
        "/z/archive/updated",
        "/z/archive/created",
        "/z/archive/name",
        "/sitemap.xml"
      ]
      payload = { paths: paths }
      description = "#{slugs_to_revalidate.length} nodes: #{slugs_to_revalidate.to_a.join(', ')}"
    end

    Rails.logger.info "Revalidating cache for #{description}"

    Thread.new do
      begin
        RestClient::Request.execute(
          method: :post,
          url: "https://www.zencephalon.com/api/revalidate",
          payload: payload.to_json,
          headers: {
            content_type: :json,
            accept: :json,
            authorization: "Bearer #{ENV['REVALIDATION_TOKEN']}"
          },
          max_redirects: 3,
          timeout: 10
        )
        Rails.logger.info "Cache revalidation succeeded for #{payload}"
      rescue => e
        Rails.logger.warn "Cache revalidation failed for #{payload}: #{e.message}"
      end
    end
  end
end
