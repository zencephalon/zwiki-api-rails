require 'redcarpet'
require 'byebug'

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

   #ToDO create an after_create to give a root_id of the node id you create for this user

  # Generate a unique API key
  def generate_api_key
    loop do
      token = SecureRandom.base64.tr('+/=', 'Qrt')
      break token unless User.exists?(api_key: token)
    end
  end

  def export_nodes
    renderer = Redcarpet::Render::HTML.new(hard_wrap: true, with_toc_data: true)
    markdown = Redcarpet::Markdown.new(renderer, extensions = {})

    urls = {}
    self.nodes.each do |node|
      urls[node.short_id] = node.url
    end
    self.nodes.each do |node|
      filename = self.root_id == node.short_id ? 'index' : node.short_id
      File.open("export/#{filename}.html", 'w') do |f|
        content = node.content
        content.scan(/\[([^\[]+)\]\(([^)]+)\)/).each do |match|
          if urls[match[1]]
            content = content.gsub("](#{match[1]})", "](#{urls[match[1]]}.html)")
          end
        end
        f.puts markdown.render(content)
      end
    end
  end
end
