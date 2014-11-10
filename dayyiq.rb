# encoding: UTF-8
#
# dayyiq
#
# Author:: hmt (https://github.com/hmt)
# Home:: https://github.com/hmt/dayyiq
# Copyright:: Copyright (c) 2013 hmt
# License:: MIT License
#
require 'google/api_client'
require 'google/api_client/client_secrets'
require 'google/api_client/auth/file_storage'
require 'sinatra/base'
require 'slim'
require 'sass'
require 'active_support/core_ext/date/calculations'
require 'active_support/time'
require 'date'
require 'rack/perftools_profiler'
require "benchmark"

begin
  require "#{File.dirname(__FILE__)}/config"
rescue LoadError
  puts "Please use your own config file. For now we're using config-example.rb"
  require "#{File.dirname(__FILE__)}/config-example"
end

AppRoot = File.expand_path(File.dirname(__FILE__))

class Calender
  def initialize(cal, time_max, time_min)
    @cal = cal
    @time_max = time_max
    @time_min = time_min
    days = time_max - time_min
    @ary = Array.new(days) {Array.new}
    fill_ary
  end

  def fill_ary
    @cal.each do |e|
      date = e.start.date || e.start.date_time
      date = date.to_date
      @ary[@time_min-date] << e
    end
  end

  def day_events(day)
    date = @time_min-day
    @ary[date]
  end
end

class Dayyiq < Sinatra::Base
  CREDENTIAL_STORE_FILE = "#{$0}-oauth2.json"

  def api_client; settings.api_client; end
  def calendar_api; settings.calendar; end

  def user_credentials
    # Build a per-request oauth credential based on token stored in session
    # which allows us to use a shared API client.
    @authorization ||= (
      auth = api_client.authorization.dup
      auth.redirect_uri = to('/oauth2callback')
      auth.update_token!(session)
      auth
    )
  end

  configure do
    use ::Rack::PerftoolsProfiler, :default_printer => 'gif'
    client = Google::APIClient.new(
      :application_name => 'Dayyiq, a tight Google calendar app',
      :application_version => '2.0.0')
    client.retries = 3

    file_storage = Google::APIClient::FileStorage.new(CREDENTIAL_STORE_FILE)
    if file_storage.authorization.nil?
      client_secrets = Google::APIClient::ClientSecrets.load
      client.authorization = client_secrets.to_authorization
      client.authorization.scope = 'https://www.googleapis.com/auth/calendar'
    else
      client.authorization = file_storage.authorization
    end

    # Since we're saving the API definition to the settings, we're only retrieving
    # it once (on server start) and saving it between requests.
    # If this is still an issue, you could serialize the object and load it on
    # subsequent runs.
    calendar = client.discovered_api('calendar', 'v3')

    set :api_client, client
    set :calendar, calendar

    set :slim, :pretty => true
    enable :sessions
    set :session_secret, ENV['dayyiq_secret'] ||= 'super secret'
    enable :method_override
    set :protection, :except => :session_hijacking
    set :public_dir, settings.root + "/public"
    enable :static
    enable :logging
    set :views, settings.root + '/views'
  end

  configure :development do
    require 'sinatra/reloader'
    register Sinatra::Reloader
  end

  helpers do
    def partial(template, locals = {})
      slim template, :layout => false, :locals => locals
    end

    def flash
      @flash = session.delete(:flash)
    end
  end

  before do
    # Ensure user has authorized the app
    unless user_credentials.access_token || request.path_info =~ /\A\/oauth2/
      redirect to('/oauth2authorize')
    end
  end

  after do
    # Serialize the access/refresh token to the session and credential store.
    session[:access_token] = user_credentials.access_token
    session[:refresh_token] = user_credentials.refresh_token
    session[:expires_in] = user_credentials.expires_in
    session[:issued_at] = user_credentials.issued_at

    file_storage = Google::APIClient::FileStorage.new(CREDENTIAL_STORE_FILE)
    file_storage.write_credentials(user_credentials)
  end

  get '/oauth2authorize' do
    # Request authorization
    redirect user_credentials.authorization_uri.to_s, 303
  end

  get '/oauth2callback' do
    # Exchange token
    user_credentials.code = params[:code] if params[:code]
    user_credentials.fetch_access_token!
    redirect to('/')
  end

  get '/css/:file.css' do
    halt 404 unless File.exist?("#{settings.views}/#{params[:file]}.scss")
    time = File.stat("#{settings.views}/#{params[:file]}.scss").ctime
    last_modified(time)
    scss params[:file].intern
  end

  get '/' do
    #fetch all calendars
    result = api_client.execute(:api_method => calendar_api.calendar_list.list,
                                :authorization => user_credentials)
    cals = result.data.items.map do |i|
      #skip id calendar does not belong to owner or is the "private" primary one
      next if i.primary || i.accessRole != "owner"
      i.summary
    end
    cals.compact!
    cal_ids = result.data.items.map do |i|
      next if i.primary || i.accessRole != "owner"
      i.id
    end
    cal_ids.compact!
    time_min = (Date.today.beginning_of_month)
    time_max = (Date.today.beginning_of_month+12.months)
    #save all users mentioned in calendars in a set
    events_list = cal_ids.map do |i|
      #skip calendar if primary or not owned by user (cannot be changed anyway)
      api_client.execute(:api_method => calendar_api.events.list,
                         :parameters => {
                            'calendarId' => i,
                            'showDeleted' => false,
                            'singleEvents' => true,
                            'timeMin' => time_min.strftime('%Y-%m-%dT%H:%M:%S%:z'),
                            'timeMax' => time_max.strftime('%Y-%m-%dT%H:%M:%S%:z')
                          }
                        )
    end
    #remove skipped entries (=nil)
    events_list.compact!
    calendars = events_list.map { |c| Calender.new(c.data.items, time_max, time_min) }
    slim :home, :locals => { :title => Konfig::TITLE, :cals => cals, :calendars => calendars}
  end
end
