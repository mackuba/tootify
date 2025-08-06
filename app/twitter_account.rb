require 'yaml'
require_relative 'twitter_api'

class TwitterAccount
  CONFIG_FILE = File.expand_path(File.join(__dir__, '..', 'config', 'twitter.yml'))

  def initialize
    @config = File.exist?(CONFIG_FILE) ? YAML.load(File.read(CONFIG_FILE)) : {}
  end

  def save_config
    File.write(CONFIG_FILE, YAML.dump(@config))
  end

  def login(handle)
    puts "To use Tootify with Twitter, you need to provide your Twitter API v2 keys."
    puts "You can get these by applying for a developer account at https://developer.twitter.com/"
    puts
    print "Enter your API Key: "
    @config['consumer_key'] = STDIN.gets.chomp
    print "Enter your API Key Secret: "
    @config['consumer_secret'] = STDIN.gets.chomp
    print "Enter your Access Token: "
    @config['access_token'] = STDIN.gets.chomp
    print "Enter your Access Token Secret: "
    @config['access_token_secret'] = STDIN.gets.chomp
    @config['handle'] = handle

    save_config
    puts "Twitter credentials saved to #{CONFIG_FILE}"
  end

  def post_status(text, media_ids = nil, parent_id = nil)
    api = TwitterAPI.new(@config['consumer_key'], @config['consumer_secret'], @config['access_token'], @config['access_token_secret'])
    api.post_tweet(text, media_ids)
  end

  def upload_media(data, filename, content_type, alt = nil)
    api = TwitterAPI.new(@config['consumer_key'], @config['consumer_secret'], @config['access_token'], @config['access_token_secret'])
    api.upload_media(data, filename, content_type, alt)
  end

  def max_alt_length
    1000
  end
end
