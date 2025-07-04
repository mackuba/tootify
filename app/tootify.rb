require 'io/console'
require 'yaml'

require_relative 'bluesky_account'
require_relative 'mastodon_account'
require_relative 'post_history'

class Tootify
  CONFIG_FILE = File.expand_path(File.join(__dir__, '..', 'config', 'tootify.yml'))

  attr_accessor :check_interval

  def initialize
    @bluesky = BlueskyAccount.new
    @mastodon = MastodonAccount.new
    @history = PostHistory.new
    @config = load_config
    @check_interval = 60
  end

  def load_config
    if File.exist?(CONFIG_FILE)
      YAML.load(File.read(CONFIG_FILE))
    else
      {}
    end
  end 

  def login_to_bluesky(handle)
    handle = handle.gsub(/^@/, '')

    print "App password: "
    password = STDIN.noecho(&:gets).chomp
    puts

    @bluesky.login_with_password(handle, password)
  end

  def login_to_mastodon(handle)
    @mastodon.oauth_login(handle)
  end

  def sync
    begin
      likes = @bluesky.fetch_likes
    rescue Minisky::ExpiredTokenError => e
      @bluesky.log_in
      likes = @bluesky.fetch_likes
    end

    records = []

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

      if reply = record['value']['reply']
        parent_uri = reply['parent']['uri']
        prepo = parent_uri.split('/')[2]

        if prepo != @bluesky.did
          puts "Skipping reply to someone else"
          @bluesky.delete_record_at(like_uri)
          next
        else
          # self-reply, we'll try to cross-post it
        end
      end

      records << [record['value'], rkey, like_uri]
    end

    records.sort_by { |x| x[0]['createdAt'] }.each do |record, rkey, like_uri|
      mastodon_parent_id = nil

      if reply = record['reply']
        parent_uri = reply['parent']['uri']
        prkey = parent_uri.split('/')[4]

        if parent_id = @history[prkey]
          mastodon_parent_id = parent_id
        else
          puts "Skipping reply to a post that wasn't cross-posted"
          @bluesky.delete_record_at(like_uri)
          next
        end
      end

      response = post_to_mastodon(record, mastodon_parent_id)
      p response

      @history.add(rkey, response['id'])
      @bluesky.delete_record_at(like_uri)
    end
  end

  def watch
    loop do
      sync
      sleep @check_interval
    end
  end

  def post_to_mastodon(record, mastodon_parent_id = nil)
    p record

    text = expand_facets(record)

    if link = link_embed(record)
      append_link(text, link) unless text.include?(link)
    end

    if quote_uri = quoted_post(record)
      repo, collection, rkey = quote_uri.split('/')[2..4]

      if collection == 'app.bsky.feed.post'
        link_to_append = bsky_post_link(repo, rkey)

        if @config['extract_link_from_quotes']
          quoted_record = fetch_record_by_at_uri(quote_uri)

          if link_from_quote = link_embed(quoted_record)
            link_to_append = link_from_quote
          end
        end

        append_link(text, link_to_append) unless text.include?(link_to_append)
      end
    end

    if images = attached_images(record)
      media_ids = []

      images.each do |embed|
        alt = embed['alt']
        cid = embed['image']['ref']['$link']
        mime = embed['image']['mimeType']

        if alt && alt.length > @mastodon.max_alt_length
          alt = alt[0...@mastodon.max_alt_length - 3] + "(…)"
        end

        data = @bluesky.fetch_blob(cid)

        uploaded_media = @mastodon.upload_media(data, cid, mime, alt)
        media_ids << uploaded_media['id']
      end
    elsif embed = attached_video(record)
      alt = embed['alt']
      cid = embed['video']['ref']['$link']
      mime = embed['video']['mimeType']

      if alt && alt.length > @mastodon.max_alt_length
        alt = alt[0...@mastodon.max_alt_length - 3] + "(…)"
      end

      data = @bluesky.fetch_blob(cid)

      uploaded_media = @mastodon.upload_media(data, cid, mime, alt)
      media_ids = [uploaded_media['id']]
    end

    if tags = record['tags']
      text += "\n\n" + tags.map { |t| '#' + t.gsub(' ', '') }.join(' ')
    end

    @mastodon.post_status(text, media_ids, mastodon_parent_id)
  end

  def fetch_record_by_at_uri(quote_uri)
    repo, collection, rkey = quote_uri.split('/')[2..4]
    pds = DID.new(repo).get_document.pds_endpoint
    sky = Minisky.new(pds, nil)
    resp = sky.get_request('com.atproto.repo.getRecord', { repo: repo, collection: collection, rkey: rkey })
    resp['value']
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
        if embed['media']['$type'] == 'app.bsky.embed.images'
          embed['media']['images']
        else
          nil
        end
      else
        nil
      end
    end
  end

  def attached_video(record)
    if embed = record['embed']
      case embed['$type']
      when 'app.bsky.embed.video'
        embed
      when 'app.bsky.embed.recordWithMedia'
        if embed['media']['$type'] == 'app.bsky.embed.video'
          embed['media']
        else
          nil
        end
      else
        nil
      end
    end
  end

  def append_link(text, link)
    if link =~ /^https:\/\/bsky\.app\/profile\/.+\/post\/.+/
      text << "\n" unless text.end_with?("\n")
      text << "\n"
      text << "RE: " + link
    else
      text << ' ' unless text.end_with?(' ')
      text << link
    end
  end

  def bsky_post_link(repo, rkey)
    "https://bsky.app/profile/#{repo}/post/#{rkey}"
  end
end
