require File.expand_path('../../config/environment', __FILE__)
require 'github/markup'

LINK_REGEX = /\[([^\[]+)\]\(([^)]+)\)/

def template(name, content)
<<HTML
  <!doctype html>
  <html>
    <head>
      <title>#{name}</title>
      <link rel="stylesheet" href="/style.css" type="text/css">
      <script src="https://ajax.googleapis.com/ajax/libs/jquery/3.1.1/jquery.min.js"></script>
      <script src="/zwik.js"></script>
    </head>
    <body>
      <div id="root"></div>
      <article>
#{content}
      </article>
    </body>
  </html>
HTML
end

Node.all.each do |node|
  filename = "#{node.id}.html"
  txt_filename = "#{node.id}.txt"
  content = node.content.gsub(LINK_REGEX) do |match|
    p match
    p $1
    title = Node.find_by(id: $2).name.parameterize
    "[#{$1}](/#{$2}/#{title})"
  end
  html = GitHub::Markup.render('foo.markdown', content)
  File.open(filename, 'w') do |f|
    f.puts template(node.name, html)
  end
  File.open(txt_filename, 'w') do |f|
    f.puts html
  end
end
