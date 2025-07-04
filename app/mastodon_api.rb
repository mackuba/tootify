require 'json'
require 'net/http'
require 'uri'

class MastodonAPI
  CODE_REDIRECT_URI = 'urn:ietf:wg:oauth:2.0:oob'

  class UnauthenticatedError < StandardError
  end

  class UnexpectedResponseError < StandardError
  end

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

  MEDIA_CHECK_INTERVAL = 5.0

  attr_accessor :access_token

  def initialize(host, access_token = nil)
    @host = host
    @root = "https://#{@host}/api/v1"
    @access_token = access_token
  end

  def generate_oauth_login_url(client_id, scopes)
    login_url = URI("https://#{@host}/oauth/authorize")

    login_url.query = URI.encode_www_form(
      client_id: client_id,
      redirect_uri: CODE_REDIRECT_URI,
      response_type: 'code',
      scope: scopes
    )

    login_url
  end

  def complete_oauth_login(client_id, client_secret, code)
    params = {
      client_id: client_id,
      client_secret: client_secret,
      redirect_uri: CODE_REDIRECT_URI,
      grant_type: 'authorization_code',
      code: code
    }

    post_json("https://#{@host}/oauth/token", params)
  end

  def account_info
    raise UnauthenticatedError.new unless @access_token
    get_json("/accounts/verify_credentials")
  end

  def lookup_account(username)
    json = get_json("/accounts/lookup", { acct: username })
    raise UnexpectedResponseError.new unless json.is_a?(Hash) && json['id'].is_a?(String)
    json
  end

  def account_statuses(user_id, params = {})
    get_json("/accounts/#{user_id}/statuses", params)
  end

  def post_status(text, media_ids = nil, parent_id = nil)
    params = { status: text }
    params['media_ids[]'] = media_ids if media_ids
    params['in_reply_to_id'] = parent_id if parent_id

    post_json("/statuses", params)
  end

  def upload_media(data, filename, content_type, alt = nil)
    url = URI("https://#{@host}/api/v2/media")
    headers = { 'Authorization' => "Bearer #{@access_token}" }

    form_data = [
      ['file', data, { :filename => filename, :content_type => content_type }]
    ]

    if alt
      form_data << ['description', alt.force_encoding('ASCII-8BIT')]
    end

    request = Net::HTTP::Post.new(url, headers)
    request.set_form(form_data, 'multipart/form-data')

    response = Net::HTTP.start(url.hostname, url.port, :use_ssl => true) do |http|
      http.request(request)
    end

    json = if response.code.to_i / 100 == 2
      JSON.parse(response.body)
    else
      raise APIError.new(response)
    end

    while json['url'].nil?
      sleep MEDIA_CHECK_INTERVAL
      json = get_media(json['id'])
    end

    json
  end

  def get_media(media_id)
    get_json("/media/#{media_id}")
  end

  def get_json(path, params = {})
    url = URI(path.start_with?('https://') ? path : @root + path)
    url.query = URI.encode_www_form(params) if params

    headers = {}
    headers['Authorization'] = "Bearer #{@access_token}" if @access_token

    response = Net::HTTP.get_response(url, headers)
    status = response.code.to_i

    if status / 100 == 2
      JSON.parse(response.body)
    elsif status / 100 == 3
      get_json(response['Location'])
    else
      raise APIError.new(response)
    end
  end

  def post_json(path, params = {})
    url = URI(path.start_with?('https://') ? path : @root + path)

    headers = {}
    headers['Authorization'] = "Bearer #{@access_token}" if @access_token

    request = Net::HTTP::Post.new(url, headers)
    request.form_data = params

    response = Net::HTTP.start(url.hostname, url.port, :use_ssl => true) do |http|
      http.request(request)
    end

    status = response.code.to_i

    if status / 100 == 2
      JSON.parse(response.body)
    else
      raise APIError.new(response)
    end
  end
end
