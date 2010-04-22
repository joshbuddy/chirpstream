require 'eventmachine'
require 'em-http'
require 'json'
require 'pp'
require 'load_path_find'

$LOAD_PATH.add_current

require 'chirpstream/event'
require 'chirpstream/event/follow'
require 'chirpstream/event/retweet'
require 'chirpstream/event/favorite'
require 'chirpstream/event/delete'
require 'chirpstream/user'
require 'chirpstream/tweet'

class Chirpstream
  
  attr_reader :handlers
  
  Handlers = Struct.new(:friend, :tweet, :follow, :favorite, :retweet, :delete, :reconnect)

  attr_reader :username, :password

  def initialize(username, password)
    @username = username
    @password = password
    @connect_url = "http://chirpstream.twitter.com/2b/user.json"
    @handlers = Handlers.new([], [], [], [], [], [], [])
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
  
  def delete(&block)
    @handlers.delete << block
  end
  
  def reconnect(&block)
    @handlers.reconnect << block
  end
  
  def dispatch_friend(data)
    unless @handlers.friend.empty?
      data['friends'].each_slice(100) do |friend_ids|
        friend_http = EM::HttpRequest.new("http://api.twitter.com/1/users/lookup.json").post(:body => {'user_id' => friend_ids.join(',')}, :head => {'authorization' => [@username, @password]})
        friend_http.callback do
          friends = JSON.parse(friend_http.response)
          friends.each do |friend|
            @handlers.friend.each{|h| h.call(friend)}
          end
        end
      end
    end
  end
  
  def dispatch_tweet(data)
    unless @handlers.tweet.empty?
      @handlers.tweet.each{|h| h.call(data)}
    end
  end
  
  def dispatch_follow(data)
    unless @handlers.follow.empty?
      data['target'] = User.new(self, data['target']['id'])
      data['source'] = User.new(self, data['source']['id'])
      e = Follow.new(data)
      e.load_all {
        @handlers.follow.each{|h| h.call(e)}
      }
    end
  end
  
  def dispatch_favorite(data)
    return if @handlers.follow.empty?
    data['target'] = User.new(self, data['target']['id'])
    data['source'] = User.new(self, data['source']['id'])
    data['target_object'] = Tweet.new(self, data['target_object']['id'])
    e = Favorite.new(data)
    e.load_all {
      @handlers.favorite.each{|h| h.call(e)}
    }
  end
  
  def dispatch_retweet(data)
    return if @handlers.retweet.empty?
    data['target'] = User.new(self, data['target']['id'])
    data['source'] = User.new(self, data['source']['id'])
    data['target_object'] = Tweet.new(self, data['target_object']['id'])
    e = Retweet.new(data)
    e.load_all {
      @handlers.retweet.each{|h| h.call(e)}
    }
  end
    
  def dispatch_delete(data)
    return if @handlers.delete.empty?
    data['delete']['user_id'] = User.new(self, data['delete']['user_id'])
    e = Delete.new(data)
    e.load_all {
      @handlers.delete.each{|h| h.call(e)}
    }
  end
  
  def dispatch_reconnect
    return if @handlers.reconnect.empty?
    @handlers.reconnect.each{|h| h.call}
  end
  
  def connect
    unless EM.reactor_running?
      EM.run { connect }
    else
      http = EM::HttpRequest.new(@connect_url).get :head => {'authorization' => [@username, @password]}
      http.errback { |e, err|
        dispatch_reconnect
        connect
      }
      http.stream { |chunk| 
        @data << chunk
        begin
          parsed_data = JSON.parse(@data)
          @data = ''
          if parsed_data['friends']
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
        rescue JSON::ParserError
          #puts "need more"
        end
      }
    end
  end
end
