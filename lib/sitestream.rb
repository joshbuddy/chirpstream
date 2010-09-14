require 'eventmachine'
require 'em-http'
require 'yajl'
require 'pp'
require 'load_path_find'

require 'oauth'
require 'oauth/client/em_http'

$LOAD_PATH.add_current

require 'chirpstream/twitter_object'
require 'chirpstream/event'
require 'chirpstream/event/follow'
require 'chirpstream/event/direct_message'
require 'chirpstream/event/retweet'
require 'chirpstream/event/favorite'
require 'chirpstream/event/unfavorite'
require 'chirpstream/event/delete'
require 'chirpstream/user'
require 'chirpstream/friend'
require 'chirpstream/tweet'
require 'chirpstream/connect'

MAX_PER_STREAM = 3
RECONNECT_AFTER = 3

class Sitestream < Chirpstream
	attr_accessor :accounts
  def initialize(options = nil)
		super(options)
    @connect_url = "http://betastream.twitter.com/2b/site.json"
  end
  
  def dispatch_connect(user)
    return if @dispatched_connect
    @handlers.connect.each{|h| h.call(user)}
		@dispatched_connect = true
  end

  def connect_single(user)
    parser = Yajl::Parser.new
    parser.on_parse_complete = Proc.new{|parsed_data|

			user = Chirpstream::Connect::User::Simple.new(parsed_data['for_user'])
			parsed_data = parsed_data['message']

			#puts parsed_data.inspect

      if parsed_data['direct_message']
        dispatch_direct_message(user, parsed_data)
      elsif parsed_data['friends']
        dispatch_friend(user, parsed_data)
      elsif parsed_data['text']
        dispatch_tweet(user, parsed_data)
      elsif parsed_data['event']
        method_sym = "dispatch_#{parsed_data['event']}".to_sym
        if respond_to?(method_sym)
          send("dispatch_#{parsed_data['event']}".to_sym, user, parsed_data)
        else
          puts "no handler for #{parsed_data['event']}"
        end
      elsif parsed_data['delete']
        dispatch_delete(user, parsed_data)
      else
        puts "i didn't know what to do with this!"
        pp parsed_data
      end
    }
    
		@connect_url = "#{@connect_url}?follow=#{CGI.escape accounts.join(',')}"
		puts "Connecting to #{@connect_url}"
    http = get_connection(user, @connect_url, :get)
    http.errback { |e, err|
      dispatch_disconnect(user)
    }
    http.stream { |chunk|
      dispatch_connect(user)
      begin
        parser << chunk
      rescue Yajl::ParseError
        p $!
        puts "bad chunk: #{chunk.inspect}"
      end
    }
  end
end
