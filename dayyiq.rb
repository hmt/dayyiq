# encoding: UTF-8
#
# dayyiq
#
# Author:: hmt (https://github.com/hmt)
# Home:: https://github.com/hmt/dayyiq
# Copyright:: Copyright (c) 2013 hmt
# License:: MIT License
#
require 'sinatra'
require 'slim'
require 'sass'
require 'active_support/core_ext/date/calculations'
require 'active_support/time'
require 'ri_cal'
require 'date'
require 'open-uri'
require 'tzinfo'
require 'sinatra/reloader' if development?
begin
  require "#{File.dirname(__FILE__)}/config"
rescue LoadError
  puts "Please use your own config file. For now we're using config-example.rb"
  require "#{File.dirname(__FILE__)}/config-example"
end

configure do
  set :slim, :pretty => true
  enable :sessions
  set :session_secret, ENV['dayyiq_secret'] ||= 'super secret'
  set :protection, :except => :session_hijacking
end

get '/css/:file.css' do
  halt 404 unless File.exist?("views/#{params[:file]}.scss")
  time = File.stat("views/#{params[:file]}.scss").ctime
  last_modified(time)
  scss params[:file].intern
end

get '/' do
  begin
    cal_file = File.open(Konfig::ICS_FILE)
  rescue
    puts 'You need an ics file to parse'
    raise
  end
  cals = RiCal.parse(cal_file)
  slim :home, :locals => { :title => Konfig::TITLE, :cals => cals }
end

