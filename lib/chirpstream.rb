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

class Chirpstream
  
  attr_reader :handlers
  
  Handlers = Struct.new(:friend, :tweet, :follow, :favorite, :retweet, :delete, :reconnect, :direct_message)

  attr_reader :username, :password
  attr_accessor :consumer_token, :consumer_secret, :access_token, :access_secret

  def initialize(username=nil, password=nil, fill_in = true)
    @fill_in = fill_in
    @username = username
    @password = password
    @connect_url = "http://chirpstream.twitter.com/2b/user.json"
    @handlers = Handlers.new([], [], [], [], [], [], [], [])
    @data = ''
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
  
  def dispatch_friend(data)
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
  
  def dispatch_tweet(data)
    unless @handlers.tweet.empty?
      tweet = Tweet.new(self, data)
      @fill_in ? tweet.load_all { |t|
        @handlers.tweet.each{|h| h.call(tweet)}
      } : @handlers.tweet.each{|h| h.call(tweet)}
    end
  end
  
  def dispatch_follow(data)
    unless @handlers.follow.empty?
      follow = Follow.new(self, data)
      @fill_in ? follow.load_all { |f|
        @handlers.follow.each{|h| h.call(f)}
      } : @handlers.follow.each{|h| h.call(follow)}
    end
  end
  
  def dispatch_direct_message(data)
    unless @handlers.direct_message.empty?
      dm = DirectMessage.new(self, data)
      @fill_in ? dm.load_all { |f|
        @handlers.direct_message.each{|h| h.call(f)}
      } : @handlers.direct_message.each{|h| h.call(dm)}
    end
  end

  def dispatch_favorite(data)
    unless @handlers.favorite.empty?
      favorite = Favorite.new(self, data)
      @fill_in ? favorite.load_all { |f|
        @handlers.favorite.each{|h| h.call(f)}
      } : @handlers.favorite.each{|h| h.call(favorite)}
    end
  end
  
  def dispatch_retweet(data)
    unless @handlers.retweet.empty?
      retweet = Retweet.new(self, data)
      @fill_in ? retweet.load_all { |f|
        @handlers.retweet.each{|h| h.call(f)}
      } : @handlers.retweet.each{|h| h.call(retweet)}
    end
  end
    
  def dispatch_delete(data)
    unless @handlers.delete.empty?
      delete = Delete.new(self, data)
      @fill_in ? delete.load_all { |f|
        @handlers.delete.each{|h| h.call(f)}
      } : @handlers.delete.each{|h| h.call(delete)}
    end
  end
  
  def dispatch_reconnect
    return if @handlers.reconnect.empty?
    @handlers.reconnect.each{|h| h.call}
  end
  
  def handle_tweet(parsed_data)
    if parsed_data['direct_message']
      dispatch_direct_message(parsed_data)
    elsif parsed_data['friends']
      dispatch_friend(parsed_data)
    elsif parsed_data['text']
      dispatch_tweet(parsed_data)
    elsif parsed_data['event']
      case parsed_data['event']
      when 'follow'
        dispatch_follow(parsed_data)
      when 'favorite'
        dispatch_favorite(parsed_data)
      when 'retweet'
        dispatch_retweet(parsed_data)
      else
        puts "weird event"
        pp parsed_data
      end
    elsif parsed_data['delete']
      dispatch_delete(parsed_data)
    else
      puts "i didn't know what to do with this!"
      pp parsed_data
    end
  end
  
  def connect
    unless EM.reactor_running?
      EM.run { connect }
    else
      parser = Yajl::Parser.new
      parser.on_parse_complete = method(:handle_tweet)
      http = EM::HttpRequest.new(@connect_url).get :head => {'authorization' => [@username, @password]}, :timeout => 0
      http.errback { |e, err|
        dispatch_reconnect
        connect
      }
      http.stream { |chunk|
        begin
          parser << chunk
        rescue Yajl::ParseError
          puts "bad chunk: #{chunk.inspect}"
        end
      }
    end
  end

  #
  # Oauth example
  #
  def twitter_oauth_consumer
    @twitter_oauth_consumer ||= OAuth::Consumer.new(consumer_token, consumer_secret, :site => "http://twitter.com")
  end

  def twitter_oauth_access_token
    @twitter_oauth_access_token ||= OAuth::AccessToken.new(twitter_oauth_consumer, access_token, access_secret)
  end

  def connect_oauth
    unless EM.reactor_running?
      EM.run { connect_oauth }
    else
      parser = Yajl::Parser.new
      parser.on_parse_complete = method(:handle_tweet)

      request = EM::HttpRequest.new(@connect_url)
      http = request.get do |client|
        twitter_oauth_consumer.sign!(client, twitter_oauth_access_token)
      end
      http.errback { |e, err|
        dispatch_reconnect
        connect_oauth
      }
      http.stream { |chunk|
        begin
          parser << chunk
        rescue Yajl::ParseError
          puts "bad chunk: #{chunk.inspect}"
        end
      }
    end
  end
end
