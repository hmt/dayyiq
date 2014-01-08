# encoding: UTF-8
#
# dayyiq
#
# Author:: hmt (https://github.com/hmt)
# Home:: https://github.com/hmt/dayyiq
# Copyright:: Copyright (c) 2013 hmt
# License:: MIT License
#
require 'sinatra/base'
require 'slim'
require 'sass'
require 'active_support/core_ext/date/calculations'
require 'active_support/time'
require 'ri_cal'
require 'date'
require 'open-uri'
require 'tzinfo'
begin
  require "#{File.dirname(__FILE__)}/config"
rescue LoadError
  puts "Please use your own config file. For now we're using config-example.rb"
  require "#{File.dirname(__FILE__)}/config-example"
end

AppRoot = File.expand_path(File.dirname(__FILE__))

class Dayyiq < Sinatra::Base
  configure do
    enable :sessions
    set :session_secret, ENV['dayyiq_secret'] ||= 'super secret'
    set :protection, :except => :session_hijacking
    enable :method_override
    enable :static
    set :public_dir, settings.root + "/public"
    set :views, settings.root + '/views'
    set :slim, :pretty => true
  end

  configure :development do
    require 'sinatra/reloader'
  end

  helpers do
    def partial(template, locals = {})
      slim template, :layout => false, :locals => locals
    end

    def flash
      @flash = session.delete(:flash)
    end
  end

  get '/css/:file.css' do
    halt 404 unless File.exist?("#{settings.views}/#{params[:file]}.scss")
    time = File.stat("#{settings.views}/#{params[:file]}.scss").ctime
    last_modified(time)
    scss params[:file].intern
  end

  get '/' do
    begin
      cal_file = File.open(File.join(AppRoot, Konfig::ICS_FILE))
    rescue
      puts 'You need an ics file to parse'
      raise
    end
    cals = RiCal.parse(cal_file)
    slim :home, :locals => { :title => Konfig::TITLE, :cals => cals }
  end
end
