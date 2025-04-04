class PostHistory
  HISTORY_FILE = File.expand_path(File.join(__dir__, '..', 'config', 'history.csv'))

  def initialize
    if File.exist?(HISTORY_FILE)
      @id_map = File.read(HISTORY_FILE).lines.map { |l| l.strip.split(',') }.then { |pairs| Hash[pairs] }
    else
      @id_map = {}
    end
  end

  def [](bluesky_rkey)
    @id_map[bluesky_rkey]
  end

  def add(bluesky_rkey, mastodon_id)
    @id_map[bluesky_rkey] = mastodon_id

    File.open(HISTORY_FILE, 'a') do |f|
      f.puts("#{bluesky_rkey},#{mastodon_id}")
    end
  end
end
