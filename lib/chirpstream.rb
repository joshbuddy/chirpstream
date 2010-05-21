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
require 'chirpstream/tweet'
require 'chirpstream/connect'

class Chirpstream
  
  include Connect

  attr_reader :handlers
  
  Handlers = Struct.new(:friend, :tweet, :follow, :favorite, :unfavorite, :retweet, :delete, :reconnect, :connect, :direct_message)

  attr_reader :consumer_token, :consumer_secret, :fill_in

  def initialize(options = nil)
    @consumer_token = options && options[:consumer_token]
    @consumer_secret = options && options[:consumer_secret]
    @fill_in = options && options[:fill_in]
    @connect_url = "http://chirpstream.twitter.com/2b/user.json"
    @handlers = Handlers.new([], [], [], [], [], [], [], [], [], [])
  end

  def on_friend(&block)
    @handlers.friend << block
  end
  
  def on_tweet(&block)
    @handlers.tweet << block
  end
  
  def on_follow(&block)
    @handlers.follow << block
  end
  
  def on_favorite(&block)
    @handlers.favorite << block
  end
  
  def on_unfavorite(&block)
    @handlers.unfavorite << block
  end
  
  def on_retweet(&block)
    @handlers.retweet << block
  end
  
  def on_direct_message(&block)
    @handlers.direct_message << block
  end

  def on_delete(&block)
    @handlers.delete << block
  end
  
  def on_reconnect(&block)
    @handlers.reconnect << block
  end
  
  def on_connect(&block)
    @handlers.connect << block
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
  
  def dispatch_tweet(user, data)
    unless @handlers.tweet.empty?
      tweet = Tweet.new(self, data)
      @fill_in ? tweet.load_all(user) { |f|
        @handlers.tweet.each{|h| h.call(f, user)}
      } : @handlers.tweet.each{|h| h.call(tweet, user)}
    end
  end
  
  def dispatch_follow(user, data)
    unless @handlers.follow.empty?
      follow = Follow.new(self, data)
      @fill_in ? follow.load_all(user) { |f|
        @handlers.follow.each{|h| h.call(f, user)}
      } : @handlers.follow.each{|h| h.call(follow, user)}
    end
  end
  
  def dispatch_direct_message(user, data)
    unless @handlers.direct_message.empty?
      dm = DirectMessage.new(self, data)
      @fill_in ? dm.load_all(user) { |f|
        @handlers.direct_message.each{|h| h.call(f, user)}
      } : @handlers.direct_message.each{|h| h.call(dm, user)}
    end
  end

  def dispatch_favorite(user, data)
    unless @handlers.favorite.empty?
      favorite = Favorite.new(self, data)
      @fill_in ? favorite.load_all(user) { |f|
        @handlers.favorite.each{|h| h.call(f, user)}
      } : @handlers.favorite.each{|h| h.call(favorite, user)}
    end
  end
  
  def dispatch_unfavorite(user, data)
    unless @handlers.unfavorite.empty?
      unfavorite = Unfavorite.new(self, data)
      @fill_in ? unfavorite.load_all(user) { |f|
        @handlers.unfavorite.each{|h| h.call(f, user)}
      } : @handlers.unfavorite.each{|h| h.call(unfavorite, user)}
    end
  end
  
  def dispatch_retweet(user, data)
    unless @handlers.retweet.empty?
      retweet = Retweet.new(self, data)
      @fill_in ? retweet.load_all(user) { |f|
        @handlers.retweet.each{|h| h.call(f, user)}
      } : @handlers.retweet.each{|h| h.call(retweet, user)}
    end
  end
    
  def dispatch_delete(user, data)
    unless @handlers.delete.empty?
      delete = Delete.new(self, data)
      @fill_in ? delete.load_all(user) { |f|
        @handlers.delete.each{|h| h.call(f, user)}
      } : @handlers.delete.each{|h| h.call(delete, user)}
    end
  end
  
  def dispatch_reconnect(user)
    return if @handlers.reconnect.empty?
    @handlers.reconnect.each{|h| h.call(user)}
  end
  
  def dispatch_connect(user)
    while h = @handlers.connect.shift
      h.call(user)
    end
  end
  
  def data_handler(user)
    Proc.new{|parsed_data|
      if parsed_data['direct_message']
        dispatch_direct_message(user, parsed_data)
      elsif parsed_data['friends']
        dispatch_friend(user, parsed_data)
      elsif parsed_data['text']
        dispatch_tweet(user, parsed_data)
      elsif parsed_data['event']
        case parsed_data['event']
        when 'follow'
          dispatch_follow(user, parsed_data)
        when 'favorite'
          dispatch_favorite(user, parsed_data)
        when 'unfavorite'
          dispatch_unfavorite(user, parsed_data)
        when 'retweet'
          dispatch_retweet(user, parsed_data)
        else
          puts "weird event"
          pp parsed_data
        end
      elsif parsed_data['delete']
        dispatch_delete(user, parsed_data)
      else
        puts "i didn't know what to do with this!"
        pp parsed_data
      end
    }
  end
  
  def connect(*users)
    unless EM.reactor_running?
      EM.run { connect(*users) }
    else
      users.each do |user, index|
        connect_single(user)
      end
    end
  end

  def connect_single(user)
    parser = Yajl::Parser.new
    parser.on_parse_complete = data_handler(user)
    http = get_connection(user, @connect_url, :get)
    http.errback { |e, err|
      dispatch_reconnect(user)
      connect
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
