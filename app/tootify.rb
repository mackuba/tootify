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
      append_link(text, link) unless text.include?(link)
    end

    if quote_uri = quoted_post(record)
      repo, collection, rkey = quote_uri.split('/')[2..4]

      if collection == 'app.bsky.feed.post'
        bsky_url = bsky_post_link(repo, rkey)
        append_link(text, bsky_url) unless text.include?(bsky_url)
      end
    end

    if images = attached_images(record)
      media_ids = []

      images.each do |image|
        alt = image['alt']
        cid = image['image']['ref']['$link']
        mime = image['image']['mimeType']

        data = @bluesky.fetch_blob(cid)

        uploaded_media = @mastodon.upload_media(data, cid, mime, alt)
        media_ids << uploaded_media['id']
      end
    end

    p @mastodon.post_status(text, media_ids)
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
    if embed = record['embed']
      case embed['$type']
      when 'app.bsky.embed.external'
        embed['external']['uri']
      when 'app.bsky.embed.recordWithMedia'
        embed['media']['external'] && embed['media']['external']['uri']
      else
        nil
      end
    end
  end

  def quoted_post(record)
    if embed = record['embed']
      case embed['$type']
      when 'app.bsky.embed.record'
        embed['record']['uri']
      when 'app.bsky.embed.recordWithMedia'
        embed['record']['record']['uri']
      else
        nil
      end
    end
  end

  def attached_images(record)
    if embed = record['embed']
      case embed['$type']
      when 'app.bsky.embed.images'
        embed['images']
      when 'app.bsky.embed.recordWithMedia'
        embed['media']['images']
      else
        nil
      end
    end
  end

  def append_link(text, link)
    text << ' ' unless text.end_with?(' ')
    text << link
  end

  def bsky_post_link(repo, rkey)
    "https://bsky.app/profile/#{repo}/post/#{rkey}"
  end
end
