require 'active_record'

class Post < ActiveRecord::Base
  validates_presence_of :mastodon_id, :bluesky_rkey

  validates_length_of :mastodon_id, maximum: 50
  validates_length_of :bluesky_rkey, is: 13

  validates_uniqueness_of :bluesky_rkey
end
