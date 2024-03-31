require 'minisky'
require 'yaml'

class BlueskyClient
  include Minisky::Requests

  CONFIG_FILE = File.expand_path(File.join(__dir__, '..', 'config', 'bluesky.yml'))

  attr_reader :config

  def initialize
    @config = File.exist?(CONFIG_FILE) ? YAML.load(File.read(CONFIG_FILE)) : {}
    Dir.mkdir('config') unless Dir.exist?('config')
  end

  def host
    @config['host']
  end

  def host=(h)
    @config['host'] = h
  end

  def save_config
    File.write(CONFIG_FILE, YAML.dump(@config))
  end
end
