require 'io/console'

require_relative 'bluesky_account'
require_relative 'mastodon_account'

class Tootify
  attr_accessor :check_interval

  def initialize
    @bluesky = BlueskyAccount.new
    @mastodon = MastodonAccount.new
    @check_interval = 60
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

  def watch
    loop do
      sync
      sleep @check_interval
    end
  end

  def post_to_mastodon(record)
    p record

    text = expand_facets(record)

    if link = link_embed(record)
      if !text.include?(link)
        text += ' ' unless text.end_with?(' ')
        text += link
      end
    end

    p @mastodon.post_status(text)
  end

  def expand_facets(record)
    bytes = record['text'].bytes
    offset = 0

    if facets = record['facets']
      facets.sort_by { |f| f['index']['byteStart'] }.each do |f|
        if link = f['features'].detect { |ft| ft['$type'] == 'app.bsky.richtext.facet#link' }
          left = f['index']['byteStart']
          right = f['index']['byteEnd']
          content = link['uri'].bytes
          
          bytes[(left + offset) ... (right + offset)] = content
          offset += content.length - (right - left)
        end
      end
    end

    bytes.pack('C*').force_encoding('UTF-8')
  end

  def link_embed(record)
    record['embed'] && record['embed']['external'] && record['embed']['external']['uri']
  end
end
