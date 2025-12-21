namespace :vault do
  desc "Export all nodes for User.find(1) to ~/zwiki"
  task export: :environment do
    user = User.find(1)
    vault_path = File.expand_path('~/zwiki')

    puts "Exporting nodes for #{user.name} to #{vault_path}..."

    exporter = VaultExporter.new(user, vault_path)
    count = exporter.export

    puts "Exported #{count} nodes to #{vault_path}"
  end

  desc "Sync all nodes for User.find(1) from ~/zwiki"
  task sync: :environment do
    user = User.find(1)
    vault_path = File.expand_path('~/zwiki')

    puts "Syncing nodes for #{user.name} from #{vault_path}..."

    importer = VaultImporter.new(user, vault_path)
    result = importer.import(mode: :sync)

    puts "Sync complete:"
    puts "  Created: #{result[:created]}"
    puts "  Updated: #{result[:updated]}"
    puts "  Skipped: #{result[:skipped]}"
  end
end
