require 'rails_helper'

RSpec.describe CaptureProcessor do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(name: 'Capture', email: 'capture@example.com', password: 'password') }

  def router_returning(journal: nil, tasks: [])
    instance_double(CaptureRouter, route: CaptureRouter::Result.new(journal: journal, tasks: tasks))
  end

  around do |example|
    original = ENV.to_h.slice('THINGS_EMAIL', 'GMAIL_USERNAME')
    ENV['THINGS_EMAIL'] = 'inbox@things.example'
    ENV['GMAIL_USERNAME'] = 'me@example.com'
    example.run
  ensure
    %w[THINGS_EMAIL GMAIL_USERNAME].each { |k| original.key?(k) ? ENV[k] = original[k] : ENV.delete(k) }
  end

  before { ActionMailer::Base.deliveries.clear }

  it "creates today's journal node with the template and appends a timestamped entry" do
    user.nodes.create!(content: "# __journal_template__\n\n## Gratitude")

    travel_to Time.zone.parse('2026-10-16 21:14 -04:00') do
      described_class.new(user: user, router: router_returning(journal: "Walked the dog.")).process("x")
    end

    node = user.nodes.find_by!(name: 'Fri Oct 16 2026')
    expect(node.content).to eq("# Fri Oct 16 2026\n\n## Gratitude\n\n9:14:00 PM 🎤: Walked the dog.\n")
  end

  it "appends to an existing journal node and bumps its version" do
    node = user.nodes.create!(content: "# Fri Oct 16 2026\n\nMorning notes.")
    version = node.reload.version

    travel_to Time.zone.parse('2026-10-16 09:05 -04:00') do
      described_class.new(user: user, router: router_returning(journal: "Coffee (oat milk)?")).process("x")
    end

    node.reload
    expect(node.content).to eq("# Fri Oct 16 2026\n\nMorning notes.\n\n9:05:00 AM 🎤: Coffee (oat milk)?\n")
    expect(node.version).to eq(version + 1)
  end

  it "mails each task to Things" do
    tasks = [{ title: "Buy batteries", notes: "AA for the remote" }, { title: "Call mom", notes: nil }]
    described_class.new(user: user, router: router_returning(tasks: tasks)).process("x")

    mails = ActionMailer::Base.deliveries
    expect(mails.map(&:subject)).to eq(["Buy batteries", "Call mom"])
    expect(mails.first.to).to eq(['inbox@things.example'])
    expect(mails.first.body.to_s).to eq("AA for the remote")
  end
end
