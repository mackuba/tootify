require 'io/console'

require_relative 'bluesky_account'
require_relative 'mastodon_account'

class Tootify
  def initialize
    @bluesky = BlueskyAccount.new
    @mastodon = MastodonAccount.new
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
end
