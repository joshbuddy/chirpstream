require 'eventmachine'
require 'em-http'
require 'yajl'
require 'pp'
require 'load_path_find'

require 'oauth'
require 'oauth/client/em_http'

$LOAD_PATH.add_current

require 'array'
require 'sitestream'
require 'chirpstream/twitter_object'
require 'chirpstream/event'
require 'chirpstream/event/follow'
require 'chirpstream/event/direct_message'
require 'chirpstream/event/retweet'
require 'chirpstream/event/favorite'
require 'chirpstream/event/unfavorite'
require 'chirpstream/event/delete'
require 'chirpstream/event/list_member'
require 'chirpstream/event/list_subscribe'
require 'chirpstream/user'
require 'chirpstream/friend'
require 'chirpstream/tweet'
require 'chirpstream/connect'
require 'chirpstream/list'

class Chirpstream
  
  include Connect

  attr_reader :handlers
  
  EventHandlerTypes = [:friend, :tweet, :follow, :unfollow, :favorite, :unfavorite, :retweet, :delete, :direct_message, :block, :unblock, :list_member_removed, :list_member_added, :list_user_subscribed, :list_user_unsubscribed, :everything, :user_update, :list_created]
  ConnectionHandlerTypes = [:disconnect, :connect]
  HandlerTypes = ConnectionHandlerTypes + EventHandlerTypes
  
  Handlers = Struct.new(*HandlerTypes)

  attr_reader :consumer_token, :consumer_secret, :fill_in

  def initialize(options = nil)
    @consumer_token = options && options[:consumer_token]
    @consumer_secret = options && options[:consumer_secret]
    @fill_in = options && options[:fill_in]
    @connect_url = "http://chirpstream.twitter.com/2b/user.json"
    @handlers = Handlers.new(*HandlerTypes.map{|h| []})
    @on_connect_called = {}
    @users = []
  end

  HandlerTypes.each do |h|
    module_eval "
    def on_#{h}(&block)
      @handlers.#{h} << block
    end
    "
  end

  EventHandlerTypes.each do |h|
    const_name = h.to_s.split("_").map{|p| p.capitalize}.join
    module_eval "
    def dispatch_#{h}(user, data)
      unless @handlers.#{h}.empty?
        obj = #{const_name}.new(self, data)
        @fill_in ? obj.load_all(user) { |nobj|
          @handlers.#{h}.each{|h| h.call(nobj, user)}
        } : @handlers.#{h}.each{|h| h.call(obj, user)}
      end
    end
    "
  end

  def dispatch_friend(user, data)
    unless @handlers.friend.empty?
      data['friends'].each_slice(100) do |friend_ids|
        parser = Yajl::Parser.new
        parser.on_parse_complete = proc { |friends|
          friends.each do |friend|
            @handlers.friend.each{|h| h.call(friend)}
          end
        }
        friend_http = get_connection(user, "http://api.twitter.com/1/users/lookup.json", :post, :body => {'user_id' => friend_ids.join(',')})
        friend_http.stream { |chunk|
          parser << chunk
        }
      end
    end
  end
  
  def dispatch_disconnect(user)
    return if @handlers.disconnect.empty?
    @handlers.disconnect.each{|h| h.call(user)}
  end
  
  def dispatch_connect(user)
    return if @on_connect_called[user.name]
    @handlers.connect.each{|h| h.call(user)}
    @on_connect_called[user.name] = true
  end
  
  def connect(*users)
    unless EM.reactor_running?
      EM.run { connect(*users) }
    else
      @users.concat(users)
      @user_adder ||= EM.add_periodic_timer(1) {
        users_to_connect = @users.slice!(0, 10)
        if users_to_connect && !users_to_connect.empty?
          users_to_connect.each do |user|
            connect_single(user)
          end
        end
      }
    end
  end

  def connect_single(user)
    parser = Yajl::Parser.new
    parser.on_parse_complete = Proc.new{|parsed_data|
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
    
    puts "connecting to #{@connect_url}"
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
