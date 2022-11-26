require File.expand_path('../../config/environment', __FILE__)

nodes = []
n = []
links = []

User.find(1).nodes.all.each do |node|
  n.push(node.short_id)
  nodes.push({
    id: node.short_id,
  })

  node.links.each do |link|
    links.push({
      source: node.short_id,
      target: link.name,
    })
  end
end

links.filter! { |link| n.include?(link[:target]) }

File.open('nodes.csv', 'w') do |f|
  f.write(links.map do |l| "#{l[:source]};#{l[:target]}" end.join("\n"))
end