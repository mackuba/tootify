require 'io/console'
require 'yaml'

require_relative 'bluesky_account'
require_relative 'database'
require_relative 'mastodon_account'
require_relative 'post'

class Tootify
  CONFIG_FILE = File.expand_path(File.join(__dir__, '..', 'config', 'tootify.yml'))

  attr_accessor :check_interval

  def initialize
    @bluesky = BlueskyAccount.new
    @mastodon = MastodonAccount.new
    @config = load_config
    @check_interval = 60

    Database.init
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

      if post = Post.find_by(bluesky_rkey: rkey)
        log "Post #{rkey} was already cross-posted, skipping"
        @bluesky.delete_record_at(like_uri)
        next
      end

      begin
        record = @bluesky.fetch_record(repo, collection, rkey)
      rescue Minisky::ClientErrorResponse => e
        log "Record not found: #{post_uri}"
        @bluesky.delete_record_at(like_uri)
        next
      end

      if reply = record['value']['reply']
        parent_uri = reply['parent']['uri']
        prepo = parent_uri.split('/')[2]

        if prepo != @bluesky.did
          log "Skipping reply to someone else"
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
        parent_rkey = parent_uri.split('/')[4]

        if parent_post = Post.find_by(bluesky_rkey: parent_rkey)
          mastodon_parent_id = parent_post.mastodon_id
        else
          log "Skipping reply to a post that wasn't cross-posted"
          @bluesky.delete_record_at(like_uri)
          next
        end
      end

      response = post_to_mastodon(record, mastodon_parent_id)
      log(response)

      Post.create!(bluesky_rkey: rkey, mastodon_id: response['id'])

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
    log(record)

    text = expand_facets(record)

    if link = link_embed(record)
      append_link(text, link) unless text.include?(link)
    end

    if quote_uri = quoted_post(record)
      repo, collection, rkey = quote_uri.split('/')[2..4]

      if collection == 'app.bsky.feed.post'
        link_to_append = bsky_post_link(repo, rkey)
        instance_info = @mastodon.instance_info

        if instance_info.dig('api_versions', 'mastodon').to_i >= 7
          quoted_record = fetch_record_by_at_uri(quote_uri)

          # TODO: we need to wait for Bridgy to add support for quote_authorizations
          quoted_post_url = quoted_record['bridgyOriginalUrl'] #|| "https://bsky.brid.gy/convert/ap/#{quote_uri}"

          if quoted_post_url && (local_post = @mastodon.search_post_by_url(quoted_post_url))
            quote_policy = local_post.dig('quote_approval', 'current_user')

            if quote_policy == 'automatic' || quote_policy == 'manual'
              quote_id = local_post['id']
            end
          end
        end

        if !quote_id && @config['extract_link_from_quotes']
          quoted_record ||= fetch_record_by_at_uri(quote_uri)
          quote_link = link_embed(quoted_record)

          if quote_link.nil?
            text_links = links_from_facets(quoted_record)
            quote_link = text_links.first if text_links.length == 1
          end

          if quote_link
            link_to_append = quote_link
          end
        end

        append_link(text, link_to_append) unless quote_id || text.include?(link_to_append)
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

    @mastodon.post_status(text, media_ids: media_ids, parent_id: mastodon_parent_id, quoted_status_id: quote_id)
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

  def links_from_facets(record)
    links = []

    if facets = record['facets']
      facets.each do |f|
        if link = f['features'].detect { |ft| ft['$type'] == 'app.bsky.richtext.facet#link' }
          links << link['uri']
        end
      end
    end

    links.reject { |x| x.start_with?('https://bsky.app/hashtag/') }
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
    if link =~ %r{^https://bsky\.app/profile/.+/post/.+}
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

  def log(obj)
    text = obj.is_a?(String) ? obj : obj.inspect
    puts "[#{Time.now}] #{text}"
  end
end
