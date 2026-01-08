class CreateApiTokens < ActiveRecord::Migration[6.1]
  def change
    create_table :api_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token, null: false
      t.string :token_type, null: false
      t.datetime :expires_at
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :api_tokens, :token, unique: true
  end
end
