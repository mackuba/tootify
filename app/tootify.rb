require 'io/console'

require_relative 'bluesky_account'
require_relative 'mastodon_account'

class Tootify
  def initialize
    @bluesky = BlueskyAccount.new
    @mastodon = MastodonAccount.new
  end

  def login_bluesky(handle)
    handle = handle.gsub(/^@/, '')

    print "App password: "
    password = STDIN.noecho(&:gets).chomp
    puts

    @bluesky.login_with_password(handle, password)
  end

  def login_mastodon(handle)
    print "Email: "
    email = STDIN.gets.chomp

    print "Password: "
    password = STDIN.noecho(&:gets).chomp
    puts

    @mastodon.oauth_login(handle, email, password)
  end

  def sync
    likes = @bluesky.fetch_likes

    likes.each do |r|
      like_uri = r['uri']
      post_uri = r['value']['subject']['uri']
      repo, collection, rkey = post_uri.split('/')[2..4]
      
      next unless repo == @bluesky.did && collection == 'app.bsky.feed.post'

      begin
        record = @bluesky.fetch_record(repo, collection, rkey)
      rescue Minisky::ClientErrorResponse => e
        puts "Record not found: #{post_uri}"
        @bluesky.delete_record_at(like_uri)
        next
      end

      post_to_mastodon(record['value'])

      @bluesky.delete_record_at(like_uri)
    end
  end

  def post_to_mastodon(record)
    p record
    p @mastodon.post_status(record['text'])
  end
end
