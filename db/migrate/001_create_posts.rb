class CreatePosts < ActiveRecord::Migration[7.2]
  def change
    create_table :posts do |t|
      t.string :bluesky_rkey, null: false
      t.string :mastodon_id, null: false
    end

    add_index :posts, :bluesky_rkey, unique: true
  end
end
