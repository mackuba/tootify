class AddTwitterIdToPosts < ActiveRecord::Migration[7.2]
  def change
    add_column :posts, :twitter_id, :string
    change_column_null :posts, :mastodon_id, true
  end
end
