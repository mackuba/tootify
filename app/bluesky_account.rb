require 'didkit'
require_relative 'bluesky_client'

class BlueskyAccount
  def initialize
    @sky = BlueskyClient.new
  end

  def did
    @sky.user.did
  end

  def login_with_password(handle, password)
    did = DID.resolve_handle(handle)
    if did.nil?
      puts "Error: couldn't resolve handle #{handle.inspect}"
      exit 1
    end

    pds = did.get_document.pds_endpoint.gsub('https://', '')

    @sky.host = pds
    @sky.user.id = handle
    @sky.user.pass = password

    @sky.log_in
  end

  def fetch_likes
    json = @sky.get_request('com.atproto.repo.listRecords', {
      repo: @sky.user.did,
      collection: 'app.bsky.feed.like',
      limit: 100
    })

    json['records']
  end

  def fetch_record(repo, collection, rkey)
    @sky.get_request('com.atproto.repo.getRecord', { repo: repo, collection: collection, rkey: rkey })
  end

  def fetch_blob(cid)
    @sky.get_request('com.atproto.sync.getBlob', { did: @sky.user.did, cid: cid })
  end

  def delete_record_at(uri)
    repo, collection, rkey = uri.split('/')[2..4]
    @sky.post_request('com.atproto.repo.deleteRecord', { repo: repo, collection: collection, rkey: rkey })
  end
end
