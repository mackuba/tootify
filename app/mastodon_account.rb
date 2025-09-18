require 'yaml'
require_relative 'mastodon_api'

class MastodonAccount
  APP_NAME = "Tootify"
  CONFIG_FILE = File.expand_path(File.join(__dir__, '..', 'config', 'mastodon.yml'))

  OAUTH_SCOPES = [
    'read:accounts',
    'read:statuses',
    'read:search',
    'write:media',
    'write:statuses'
  ].join(' ')

  def initialize
    @config = File.exist?(CONFIG_FILE) ? YAML.load(File.read(CONFIG_FILE)) : {}
  end

  def max_alt_length
    1500
  end

  def save_config
    File.write(CONFIG_FILE, YAML.dump(@config))
  end

  def oauth_login(handle)
    instance = handle.split('@').last
    app_response = register_oauth_app(instance)

    api = MastodonAPI.new(instance)

    login_url = api.generate_oauth_login_url(app_response['client_id'], OAUTH_SCOPES)

    puts "Open this URL in your web browser and authorize the app:"
    puts
    puts login_url
    puts
    puts "Then, enter the received code here:"
    puts

    print ">> "
    code = STDIN.gets.chomp

    json = api.complete_oauth_login(app_response['client_id'], app_response['client_secret'], code)

    api.access_token = json['access_token']
    info = api.account_info

    @config['handle'] = handle
    @config['access_token'] = api.access_token
    @config['user_id'] = info['id']
    save_config
  end

  def register_oauth_app(instance)
    api = MastodonAPI.new(instance)
    api.register_oauth_app(APP_NAME, OAUTH_SCOPES)
  end

  def instance_info
    instance = @config['handle'].split('@').last
    api = MastodonAPI.new(instance, @config['access_token'])
    api.instance_info
  end

  def post_status(text, media_ids: nil, parent_id: nil, quoted_status_id: nil)
    instance = @config['handle'].split('@').last
    api = MastodonAPI.new(instance, @config['access_token'])
    api.post_status(text, media_ids: media_ids, parent_id: parent_id, quoted_status_id: quoted_status_id)
  end

  def upload_media(data, filename, content_type, alt = nil)
    instance = @config['handle'].split('@').last
    api = MastodonAPI.new(instance, @config['access_token'])
    api.upload_media(data, filename, content_type, alt)
  end

  def search_post_by_url(url)
    instance = @config['handle'].split('@').last
    api = MastodonAPI.new(instance, @config['access_token'])
    api.search_post_by_url(url)
  end    
end
