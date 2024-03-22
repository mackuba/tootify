require 'mastodon'
require 'yaml'

require_relative 'mastodon_api'

class MastodonAccount
  APP_NAME = "tootify"
  CONFIG_FILE = File.expand_path(File.join(__dir__, '..', 'config', 'mastodon.yml'))
  OAUTH_SCOPES = 'read:accounts read:statuses write:media write:statuses'

  def initialize
    @config = File.exist?(CONFIG_FILE) ? YAML.load(File.read(CONFIG_FILE)) : {}
  end

  def save_config
    File.write(CONFIG_FILE, YAML.dump(@config))
  end

  def oauth_login(handle, email, password)
    instance = handle.split('@').last
    app_response = register_oauth_app(instance, OAUTH_SCOPES)

    api = MastodonAPI.new(instance)

    json = api.oauth_login_with_password(
      app_response.client_id,
      app_response.client_secret,
      email, password, OAUTH_SCOPES
    )

    api.access_token = json['access_token']
    info = api.account_info

    @config['handle'] = handle
    @config['access_token'] = api.access_token
    @config['user_id'] = info['id']
    save_config
  end

  def register_oauth_app(instance, scopes)
    client = Mastodon::REST::Client.new(base_url: "https://#{instance}")
    client.create_app(APP_NAME, 'urn:ietf:wg:oauth:2.0:oob', scopes)
  end
end
