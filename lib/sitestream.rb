require 'eventmachine'
require 'em-http'
require 'yajl'
require 'pp'
require 'load_path_find'

require 'oauth'
require 'oauth/client/em_http'

$LOAD_PATH.add_current

require 'chirpstream'
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

MAX_PER_STREAM = 100
MAX_STREAM_PER_SECOND = 10
RECONNECT_AFTER = 5

Signal.trap("USR1") do
  puts "Received USR1"
  Sitestream.should_check_stream=true
end

module EventMachine
  class HttpClient
    attr_accessor :chirp_id, :account_ids, :should_close, :dispatched_connect, :last_content_at, :should_reconnect
  end
end

class Sitestream < Chirpstream
  attr_accessor :accounts
  def initialize(options = nil)
    super(options)
    @connect_url = "http://betastream.twitter.com/2b/site.json"
  end

  EventHandlerTypes.each do |h|
    const_name = h.to_s.split("_").map{|p| p.capitalize}.join
    module_eval "
    def dispatch_#{h}(user, data, http)
      unless @handlers.#{h}.empty?
        obj = #{const_name}.new(self, data)
        @fill_in ? obj.load_all(user) { |nobj|
          @handlers.#{h}.each{|h| h.call(nobj, user, http)}
        } : @handlers.#{h}.each{|h| h.call(obj, user, http)}
      end
    end
    "
  end


  def self.should_check_stream=(value)
    @@should_check_stream = value
  end

  def accounts=(accounts)
    @accounts = accounts.uniq
  end

  def dispatch_user_update(user,data,http)
    return if @handlers.user_update.empty?
    @handlers.user_update.each{|h| h.call(data,user,http)}
  end

  def dispatch_everything(user,data,http)
    return if @handlers.everything.empty?
    @handlers.everything.each{|h| h.call(data,user,http)}
  end

  def dispatch_connect(user, http)
		# Disconnect already connected http if all reconnect connected
		if @https_force_reconnection.length > 0
			@https_force_reconnection.delete(http)
			if @https_force_reconnection.length == 0
				puts "All reconnection have happened, disconnecting old ones"
				https_to_disconnect = []
				@https.each do |old_http|
					https_to_disconnect << old_http if old_http.should_close
				end
				rejected = @https.reject!{|h| h.should_close}
				puts "Disconnecting #{https_to_disconnect.collect{|t| t.chirp_id}.inspect}"
				https_to_disconnect.each do |h|
					h.close_connection
				end
			end
		end

    return if http.dispatched_connect
    @handlers.connect.each{|h| h.call(user,http)}
    http.dispatched_connect = true
  end

  def dispatch_disconnect(user,http)
		# We remove users as being connected, only if this stream is not a reconnection
		# if not in @https it means it was a reconnection
		if @https.include? http
			puts "dispatch_disconnect (1) #{http.account_ids.count} accounts"
			http.account_ids.each do |t|
				@http_accounts.delete(t.to_s) if @http_accounts[t.to_s] and @http_accounts[t.to_s] == http # remove http link
			end
		end
    @https.delete(http)
    return if @handlers.disconnect.empty?
    @handlers.disconnect.each{|h| h.call(user,http)}
		connect_missing_accounts # this reconnects accounts when we got disconnected
  end

  def connect_for_twit_ids(user,twit_ids, force_connect=false)
    @chirp_id ||= 0				# unique http stream identifier
    @https ||= []					# all http streams
    @http_accounts ||= {} # twitter_id => http
		@https_force_reconnection ||= [] # When we force reconnection

    rejected = twit_ids.reject!{|t| @http_accounts.has_key? t.to_s } unless force_connect
    return if twit_ids.length == 0 # we don't need to connect any

    @chirp_id += 1

    url = "#{@connect_url}?follow=#{CGI.escape twit_ids.join(',')}&with=followings"
    http = get_connection(user, url, :get)
    puts "Connecting stream #{@chirp_id} to #{@connect_url} (#{twit_ids.length})"

    # for later reference
    http.chirp_id = @chirp_id
    http.account_ids = twit_ids
    twit_ids.each {|t| @http_accounts[t.to_s] = http }
    @https << http
		@https_force_reconnection << http if force_connect

    parser = Yajl::Parser.new
    parser.on_parse_complete = Proc.new{|parsed_data|

      user = Chirpstream::Connect::User::Simple.new(parsed_data['for_user'])
      stream_id = @http_accounts[user.twitter_id.to_s] ?  @http_accounts[user.twitter_id.to_s].chirp_id : -1
      #puts "received info for user #{user.twitter_id} on stream #{stream_id}"

      #puts "#{user.twitter_id} in stream #{@http_accounts[user.twitter_id.to_s].chirp_id}"

      parsed_data = parsed_data['message']

			dispatch_everything(user,parsed_data,@http_accounts[user.twitter_id.to_s])
      if parsed_data['direct_message']
        dispatch_direct_message(user, parsed_data, @http_accounts[user.twitter_id.to_s])
      elsif parsed_data['friends']
        dispatch_friend(user, parsed_data, @http_accounts[user.twitter_id.to_s])
      elsif parsed_data['text']
        dispatch_tweet(user, parsed_data, @http_accounts[user.twitter_id.to_s])
      elsif parsed_data['event']
        method_sym = "dispatch_#{parsed_data['event']}".to_sym
        if respond_to?(method_sym)
          send("dispatch_#{parsed_data['event']}".to_sym, user, parsed_data, @http_accounts[user.twitter_id.to_s])
        else
          puts "NO HANDLER FOR #{parsed_data['event']}".foreground(:yellow)
        end
      elsif parsed_data['delete']
        dispatch_delete(user, parsed_data, @http_accounts[user.twitter_id.to_s])
      else
        puts "i didn't know what to do with this!"
        pp parsed_data
      end
    }
    
    http.errback { |e, err|
      dispatch_disconnect(user,http)
    }
    http.stream { |chunk|
			http.last_content_at = Time.now
			#puts "#{http.chirp_id} received #{chunk}"
      dispatch_connect(user,http)
      begin
				#puts "#{http.chirp_id} received #{chunk}"
        parser << chunk
      rescue Yajl::ParseError
				http.should_reconnect = true
        p $!
        puts "bad chunk: #{chunk.inspect}"
				#url = "#{@connect_url}?follow=#{CGI.escape http.twit_ids.join(',')}&with=followings"
				#puts "url called was #{url}"
      end
    }
  end

	def reconnect_unactive_streams
		disconnected_at_least_one = false
		twit_ids_to_reconnect = []
		https_to_disconnect = []
    @https.each_with_index do |http,i|
			if (http.last_content_at and (Time.now - http.last_content_at) > 30) or http.should_reconnect
				puts "Streaming #{http.chirp_id} has inactivity, reconnecting. should_reconnect: #{http.should_reconnect}"
				disconnected_at_least_one = true
				twit_ids_to_reconnect += http.account_ids

				https_to_disconnect << old_http
				http.should_close
				http.close_connection
			end
		end

    twit_ids_to_reconnect.in_groups_of(MAX_PER_STREAM,false).each do |group|
      connect_for_twit_ids(@user,group,true)
    end
	end

  def check_stream
    puts "Checking streams"

		disconnected_at_least_one = false
		twit_ids_to_reconnect = []
    @https.each_with_index do |http,i|
			http.last_content_at ||= Time.now
      puts "stream #{http.chirp_id} has #{http.account_ids.length} last activity #{(Time.now - http.last_content_at).floor}sec ago" # accounts: #{http.account_ids.join(',')}"

      if (http.account_ids.length < MAX_PER_STREAM and ((i+1) < @https.length or disconnected_at_least_one)) or
				(http.last_content_at and (Time.now - http.last_content_at) > 30) or http.should_reconnect
				disconnected_at_least_one = true
        #http.close_connection
				http.should_close = true
				twit_ids_to_reconnect += http.account_ids
      end
    end
    puts "Reconnecting missing accounts: #{twit_ids_to_reconnect.length} accounts" if twit_ids_to_reconnect.length > 0

    twit_ids_to_reconnect.in_groups_of(MAX_PER_STREAM,false).each do |group|
      connect_for_twit_ids(@user,group,true)
    end
  end

  def connect_missing_accounts
    twit_ids ||= accounts
    twit_ids.reject!{|t| @http_accounts.has_key? t.to_s } # remove already connected account

		if twit_ids.length > 0
			puts "Connecting missing accounts: #{twit_ids.length} accounts"
			connect_all_streams(twit_ids,@user)
		end

    #twit_ids.in_groups_of(MAX_PER_STREAM,false).each do |group|
    #  connect_for_twit_ids(@user,group)
    #end
  end

	def connect_all_streams(account_ids,user)
		puts "connect_all_streams for #{account_ids.length} accounts"
		connected = 0
		connected_accounts = []

    account_ids.in_groups_of(MAX_PER_STREAM,false).each do |group|
			if connected > MAX_STREAM_PER_SECOND
				puts "Delaying, too many stream per second, will call #{(account_ids - connected_accounts).length} accounts"
				connected = 0

				EM.add_timer(1) {
					connect_all_streams(account_ids - connected_accounts,user)
				}
				return
			end

			connected_accounts += group
      connect_for_twit_ids(user,group)
			connected += 1
    end
	end

  def connect_single(user)
    @@should_check_stream = false
    @user = user
		connect_all_streams(accounts,user)

    @check_streams ||= EM.add_periodic_timer(1) {
      if @@should_check_stream
        @@should_check_stream = false
        check_stream
      end
    }
  end
end
