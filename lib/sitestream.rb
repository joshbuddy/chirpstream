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

MAX_PER_STREAM = 5
RECONNECT_AFTER = 2

Signal.trap("USR1") do
  puts "Received USR1"
  Sitestream.should_check_stream=true
end

module EventMachine
  class HttpClient
    attr_accessor :chirp_id, :account_ids
  end
end

class Sitestream < Chirpstream
  attr_accessor :accounts
  def initialize(options = nil)
    super(options)
    @connect_url = "http://betastream.twitter.com/2b/site.json"
  end

  def self.should_check_stream=(value)
    @@should_check_stream = value
  end

  def accounts=(accounts)
    @accounts = accounts.uniq
  end

  def dispatch_connect(user)
    return if @dispatched_connect
    @handlers.connect.each{|h| h.call(user)}
    @dispatched_connect = true
  end

  def dispatch_disconnect(user,http)
    @https.delete(http)
    http.account_ids.each do |t|
      @http_accounts.delete(t.to_s) if @http_accounts[t.to_s] and @http_accounts[t.to_s] == http # remove http link
    end
    return if @handlers.disconnect.empty?
    @handlers.disconnect.each{|h| h.call(user)}
  end

  def connect_for_twit_ids(user,twit_ids, force_connect=false)
    @chirp_id ||= 0
    @https ||= []
    @http_accounts ||= {}

    # already included in a stream
    ##		twit_ids.each {|t|
    ##			if @http_accounts.has_key? t.to_s
    ##				puts "#{t} already has a stream!"
    ##			else
    ##				#puts "#{t} doesn not have a stream"
    ##			end
    ##		}
    rejected = twit_ids.reject!{|t| @http_accounts.has_key? t.to_s } unless force_connect
    #puts "rejected: #{rejected}"
    return if twit_ids.length == 0

    @chirp_id += 1

    url = "#{@connect_url}?follow=#{CGI.escape twit_ids.join(',')}"
    http = get_connection(user, url, :get)
    puts "Connecting to #{url} (#{twit_ids.join(',')})"

    # for later reference
    http.chirp_id = @chirp_id
    http.account_ids = twit_ids
    twit_ids.each {|t| @http_accounts[t.to_s] = http }
    @https << http

    parser = Yajl::Parser.new
    parser.on_parse_complete = Proc.new{|parsed_data|

      user = Chirpstream::Connect::User::Simple.new(parsed_data['for_user'])
      stream_id = @http_accounts[user.twitter_id.to_s] ?  @http_accounts[user.twitter_id.to_s].chirp_id : -1
      puts "received info for user #{user.twitter_id} on stream #{stream_id}"

      #puts "#{user.twitter_id} in stream #{@http_accounts[user.twitter_id.to_s].chirp_id}"

      parsed_data = parsed_data['message']

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
    
    http.errback { |e, err|
      dispatch_disconnect(user,http)
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

  def check_stream
    puts "Checking streams"
    @https.each do |http|
      puts "stream #{http.chirp_id} has #{http.account_ids.length} accounts: #{http.account_ids.join(',')}"

      if http.account_ids.length == 1
        http.close_connection
      end
    end
  end
  def connect_missing_accounts
    twit_ids = accounts
    twit_ids.reject!{|t| @http_accounts.has_key? t.to_s } # remove already connected account
    puts "Connecting missing accounts: #{twit_ids.inspect}"

    twit_ids.in_groups_of(MAX_PER_STREAM,false).each do |group|
      connect_for_twit_ids(@user,group)
    end
  end

  def connect_single(user)
    @@should_check_stream = false
    @user = user

    accounts.in_groups_of(MAX_PER_STREAM,false).each do |group|
      connect_for_twit_ids(user,group)
    end

    @check_streams ||= EM.add_periodic_timer(1) {
      if @@should_check_stream
        @@should_check_stream = false
        check_stream
      end
    }
  end
end
