require 'io/console'
require_relative 'mastodon_account'

class Tootify
  def initialize
    @mastodon = MastodonAccount.new
  end

  def login_bluesky
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
