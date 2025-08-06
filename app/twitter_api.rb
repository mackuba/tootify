require 'json'
require 'net/http'
require 'uri'
require 'simple_oauth'

class TwitterAPI
  class APIError < StandardError
    attr_reader :response

    def initialize(response)
      @response = response
      super("APIError #{response.code}: #{response.body}")
    end

    def status
      response.code.to_i
    end
  end

  def initialize(consumer_key, consumer_secret, access_token, access_token_secret)
    @consumer_key = consumer_key
    @consumer_secret = consumer_secret
    @access_token = access_token
    @access_token_secret = access_token_secret
  end

  def post_tweet(text, media_ids = nil)
    url = 'https://api.twitter.com/2/tweets'
    body = { text: text }
    body[:media] = { media_ids: media_ids } if media_ids
    request(:post, url, body.to_json)
  end

  def upload_media(data, filename, content_type, alt = nil)
    media_id = init_upload(data.size, content_type)
    append_upload(media_id, data)
    finalize_upload(media_id)
    create_media_metadata(media_id, alt) if alt
    media_id
  end

  private

  def init_upload(total_bytes, media_type)
    url = 'https://upload.twitter.com/1.1/media/upload.json'
    params = {
      command: 'INIT',
      total_bytes: total_bytes,
      media_type: media_type
    }
    response = request(:post, url, params)
    response['media_id_string']
  end

  def append_upload(media_id, data)
    url = 'https://upload.twitter.com/1.1/media/upload.json'
    segment_index = 0
    # Twitter recommends 5MB chunks
    data.each_slice(5 * 1024 * 1024) do |chunk|
      params = {
        command: 'APPEND',
        media_id: media_id,
        media: chunk,
        segment_index: segment_index
      }
      request(:post, url, params, multipart: true)
      segment_index += 1
    end
  end

  def finalize_upload(media_id)
    url = 'https://upload.twitter.com/1.1/media/upload.json'
    params = {
      command: 'FINALIZE',
      media_id: media_id
    }
    request(:post, url, params)
  end

  def create_media_metadata(media_id, alt_text)
    url = 'https://api.twitter.com/1.1/media/metadata/create.json'
    body = {
      media_id: media_id,
      alt_text: { text: alt_text }
    }
    request(:post, url, body.to_json)
  end

  def request(method, url, body = nil, multipart: false)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    if multipart
      req = Net::HTTP::Post::Multipart.new(uri.path, body)
    else
      req = case method
            when :post
              Net::HTTP::Post.new(uri.request_uri)
            when :get
              Net::HTTP::Get.new(uri.request_uri)
            end
      req.body = body if body
      req['Content-Type'] = 'application/json' if body
    end

    header = SimpleOAuth::Header.new(method, url, body, {
      consumer_key: @consumer_key,
      consumer_secret: @consumer_secret,
      token: @access_token,
      token_secret: @access_token_secret
    })

    req['Authorization'] = header.to_s

    res = http.request(req)

    unless res.is_a?(Net::HTTPSuccess)
      raise APIError.new(res)
    end

    JSON.parse(res.body) if res.body && !res.body.empty?
  end
end
