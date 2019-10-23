require File.expand_path('../../config/environment', __FILE__)

User.find_by(name: 'zen').export_nodes
