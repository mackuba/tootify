require 'didkit'
require_relative 'bluesky_client'

class BlueskyAccount
  def login_with_password(handle, password)
    did = DID.resolve_handle(handle)
    if did.nil?
      puts "Error: couldn't resolve handle #{handle.inspect}"
      exit 1
    end

    pds = did.get_document.pds_endpoint.gsub('https://', '')

    sky = BlueskyClient.new
    sky.host = pds
    sky.user.id = handle
    sky.user.pass = password
    sky.log_in
  end
end
