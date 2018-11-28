require File.expand_path('../../config/environment', __FILE__)
require 'github/markup'

style_file = File.expand_path('../style.css', __FILE__)
js_file = File.expand_path('../zwik.js', __FILE__)
favicon = File.expand_path('../favicon.ico', __FILE__)
logo = File.expand_path('../zenchinese.png', __FILE__)

`cp #{style_file} export/`
`cp #{js_file} export/`
`cp #{favicon} export/`
`cp #{logo} export/`

User.find_by(name: 'zen_public').export_nodes