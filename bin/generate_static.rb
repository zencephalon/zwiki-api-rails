require File.expand_path('../../config/environment', __FILE__)
require 'github/markup'

LINK_REGEX = /\[([^\[]+)\]\(([^)]+)\)/

def template(name, content)
<<HTML
  <!doctype html>
  <html>
    <head>
      <title>#{name}</title>
    </head>
    <body>
      <div id="root"></div>
      <script src="/static/bundle.js"></script>
      <article>
#{content}
      </article>
    </body>
  </html>
HTML
end

Node.all.each do |node|
  filename = "#{node.id}.html"
  content = node.content.gsub(LINK_REGEX) do |match|
    p match
    p $1
    title = Node.find_by(id: $2).name.parameterize
    "[#{$1}](/#{$2}/#{title})"
  end
  File.open(filename, 'w') do |f|
    f.puts template(node.name, GitHub::Markup.render('foo.markdown', content))
  end
end