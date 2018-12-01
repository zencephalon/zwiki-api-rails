require File.expand_path('../../config/environment', __FILE__)
require 'json'

f = File.open('archive.json')
content = f.read
j = JSON.parse(content)
u = User.find_by(name: 'zen_public')

j.each do |branch|
  content = "# #{branch['url'].titleize}\n\n" + branch['text']
  u.nodes.create(content: content, short_id: branch['url'])
end
