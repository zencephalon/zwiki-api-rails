require File.expand_path('../../config/environment', __FILE__)

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
#{content}
    </body>
  </html>
HTML
end

Node.all.each do |node|
  filename = "#{node.id}.html"
  File.open(filename, 'w') do |f|
    f.puts template(node.name, node.content)
  end
end