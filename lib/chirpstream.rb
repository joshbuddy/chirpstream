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
require 'chirpstream/event/delete'
require 'chirpstream/user'
require 'chirpstream/tweet'
require 'chirpstream/connect'

class Chirpstream
  
  include Connect

  attr_reader :handlers
  
  Handlers = Struct.new(:friend, :tweet, :follow, :favorite, :retweet, :delete, :reconnect, :direct_message)

  attr_reader :username, :password
  attr_reader :consumer_token, :consumer_secret, :fill_in

  def initialize(options = nil)
    @consumer_token = options && options[:consumer_token]
    @consumer_secret = options && options[:consumer_secret]
    @fill_in = options && options[:fill_in]
    @connect_url = "http://chirpstream.twitter.com/2b/user.json"
    @handlers = Handlers.new([], [], [], [], [], [], [], [])
  end

  def friend(&block)
    @handlers.friend << block
  end
  
  def tweet(&block)
    @handlers.tweet << block
  end
  
  def follow(&block)
    @handlers.follow << block
  end
  
  def favorite(&block)
    @handlers.favorite << block
  end
  
  def retweet(&block)
    @handlers.retweet << block
  end
  
  def direct_message(&block)
    @handlers.direct_message << block
  end

  def delete(&block)
    @handlers.delete << block
  end
  
  def reconnect(&block)
    @handlers.reconnect << block
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
        friend_http = EM::HttpRequest.new("http://api.twitter.com/1/users/lookup.json").post(:body => {'user_id' => friend_ids.join(',')}, :head => {'authorization' => [@username, @password]})
        http.stream { |chunk|
          parser << chunk
        }
      end
    end
  end
  
  def dispatch_tweet(user, data)
    unless @handlers.tweet.empty?
      tweet = Tweet.new(self, data)
      @fill_in ? tweet.load_all { |f|
        @handlers.tweet.each{|h| h.call(f, user)}
      } : @handlers.tweet.each{|h| h.call(tweet, user)}
    end
  end
  
  def dispatch_follow(user, data)
    unless @handlers.follow.empty?
      follow = Follow.new(self, data)
      @fill_in ? follow.load_all { |f|
        @handlers.follow.each{|h| h.call(f, user)}
      } : @handlers.follow.each{|h| h.call(follow, user)}
    end
  end
  
  def dispatch_direct_message(user, data)
    unless @handlers.direct_message.empty?
      dm = DirectMessage.new(self, data)
      @fill_in ? dm.load_all { |f|
        @handlers.direct_message.each{|h| h.call(f, user)}
      } : @handlers.direct_message.each{|h| h.call(dm, user)}
    end
  end

  def dispatch_favorite(user, data)
    unless @handlers.favorite.empty?
      favorite = Favorite.new(self, data)
      @fill_in ? favorite.load_all { |f|
        @handlers.favorite.each{|h| h.call(f, user)}
      } : @handlers.favorite.each{|h| h.call(favorite, user)}
    end
  end
  
  def dispatch_retweet(user, data)
    unless @handlers.retweet.empty?
      retweet = Retweet.new(self, data)
      @fill_in ? retweet.load_all { |f|
        @handlers.retweet.each{|h| h.call(f, user)}
      } : @handlers.retweet.each{|h| h.call(retweet, user)}
    end
  end
    
  def dispatch_delete(user, data)
    unless @handlers.delete.empty?
      delete = Delete.new(self, data)
      @fill_in ? delete.load_all { |f|
        @handlers.delete.each{|h| h.call(f, user)}
      } : @handlers.delete.each{|h| h.call(delete, user)}
    end
  end
  
  def dispatch_reconnect(user)
    return if @handlers.reconnect.empty?
    @handlers.reconnect.each{|h| h.call(user)}
  end
  
  def data_handler(user)
    proc{|parsed_data|
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
      users.each do |user|
        parser = Yajl::Parser.new
        parser.on_parse_complete = data_handler(user)
        http = get_connection(user, @connect_url, :get)
        http.errback { |e, err|
          dispatch_reconnect
          connect
        }
        http.stream { |chunk|
          begin
            parser << chunk
          rescue Yajl::ParseError
            p $!
            puts "bad chunk: #{chunk.inspect}"
          end
        }
      end
    end
  end
end
