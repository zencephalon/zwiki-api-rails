class ThingsMailer < ApplicationMailer
  # Things' Mail to Things: subject becomes the to-do title, body its notes.
  def task(title, notes = nil)
    mail(
      to: ENV.fetch('THINGS_EMAIL'),
      from: ENV.fetch('GMAIL_USERNAME'),
      subject: title,
      body: notes.to_s,
      content_type: 'text/plain'
    )
  end
end
