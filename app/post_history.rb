require_relative 'database'
require_relative 'post'

class PostHistory
  def initialize
    Database.connect
  end

  def [](bluesky_rkey)
    Post.find_by(bluesky_rkey: bluesky_rkey)&.mastodon_id
  end

  def add(bluesky_rkey, mastodon_id)
    Post.create!(bluesky_rkey: bluesky_rkey, mastodon_id: mastodon_id)
  end
end
