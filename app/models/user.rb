require 'redcarpet'

class User < ApplicationRecord
  has_secure_password

  has_many :nodes

  # Assign an API key on create
  before_create do |user|
    user.api_key = user.generate_api_key
  end

  after_create do |user|
    node = user.nodes.create(
      name: 'Root',
      content: %{# Root

ILUVU, Welcome to Zwiki.

Start creating links to get started.

## Keyboard Shortcuts

Ctrl-space switches between the editor and the search bar

If U start typing a link with [ it will start suggesting ways to complete it. Using Tab will complete the link.

If U want to create a new page U can start typing a link like "[New Page" and then hit ctrl-N for "new" and it'll open your new page and complete the link to it

ctrl-f (focus) will close all pages except the one U have focus on

If U hit tab or shift-tab it'll cycle through the links on the current page

ctrl-Q and ctrl-shift-Q will select paragraphs within a page

ctrl-z will turn a line into a todo item and then toggle the todo between done and not done

To move between panes use ctrl-[hjkl]. h moves left, l moves right, j moves down, and k moves up.

ctrl-shift-d will insert today's date

ctrl-d will enter a timestamp for right now
})
    user.root_id = node.short_id
    user.save
  end

  def public_slugs
    return self.nodes.where(is_private: false).pluck(:slugs)
  end

  # Generate a unique API key
  def generate_api_key
    loop do
      token = SecureRandom.base64.tr('+/=', 'Qrt')
      break token unless User.exists?(api_key: token)
    end
  end

  def make_nodes_public
    seen_nodes = {}
    queue = [self.public_root_id]

    until queue.empty? do
      current = Node.find_by(short_id: queue.pop)
      next unless current
      next if seen_nodes[current.id]

      current.is_private = false
      current.save
      seen_nodes[current.id] = true

      queue.push(*current.get_links)
    end
  end

  # nodes reachable from the root, basically
  def get_public_nodes
    seen_nodes = {}
    queue = [self.public_root_id]

    until queue.empty? do
      current = Node.find_by(short_id: queue.pop)
      next unless current
      next if seen_nodes[current.id]

      seen_nodes[current.id] = current

      queue.push(*current.get_links)
    end

    return seen_nodes.values
  end

  def export_nodes
    urls = {}
    public_nodes = get_public_nodes

    public_nodes.each do |node|
      urls[node.short_id] = node.url(urls)
    end
    urls[self.public_root_id] = 'index'

    public_nodes.each do |node|
      filename = urls[node.short_id]

      File.open("content/#{filename}.md", 'w:UTF-8') do |f|
        f.puts Node.to_export(node.content, urls)
      end
    end
  end
end
