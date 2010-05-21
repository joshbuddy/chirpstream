class TwitterObject

  SINGLE_USER_URL = "http://api.twitter.com/1/users/show/%s.json"
  SINGLE_TWEET_URL = "http://api.twitter.com/1/statuses/show/%s.json"

  attr_reader :base

  def initialize(base, data = nil)
    @base = base
    from_json(data) if data
    yield self if block_given?
  end
  
  def self.user_writer(*attrs)
    attrs.each do |attr|
      module_eval "
      def #{attr}=(#{attr})
        @#{attr} = if #{attr}.is_a?(Hash)
          Chirpstream::User.new(base, #{attr})
        else
          Chirpstream::User.new(base) {|u| u.id = #{attr}}
        end
      end
      "
    end
  end
  
  def self.tweet_writer(*attrs)
    attrs.each do |attr|
      module_eval "
      def #{attr}=(#{attr})
        @#{attr} = if #{attr}.is_a?(Hash)
          Chirpstream::Tweet.new(base, #{attr})
        else
          Chirpstream::Tweet.new(base) {|t| t.id = #{attr}}
        end
      end
      "
    end
  end
  
  def from_json(data)
    self.class.attrs.each { |a| self.send(:"#{a}=", data[a.to_s]) }
  end
  
  def self.attrs
    const_get(:ATTRS)
  end
  
  def load_all(user, &block)
    attrs = self.class.attrs
    if respond_to?(:loaded?) && !loaded?
      if respond_to?(:user_loadable_id)
        from_json(get_user_data(user, user_loadable_id)[user_loadable_id])
        load_all(&block)
      elsif respond_to?(:tweet_loadable_id)
        from_json(get_tweet_data(user, tweet_loadable_id)[tweet_loadable_id])
        load_all(&block)
      end
    else
      tweet_ids = {}
      user_ids = {}
      attrs.each do |a|
        obj = send(a)
        if obj.respond_to?(:loaded?) && !obj.loaded?
          if obj.respond_to?(:user_loadable_id)
            user_ids[a] = obj.user_loadable_id
          elsif obj.respond_to?(:tweet_loadable_id)
            tweet_ids[a] = obj.tweet_loadable_id
          end
        end
      end
      get_tweet_data(user, tweet_ids.values) { |tweet_data|
        tweet_ids.each{|k,v| self.send(:"#{k}=", tweet_data[v])}
        user_data = get_user_data(user, user_ids.values) { |user_data|
          user_ids.each{|k,v| self.send(:"#{k}=", user_data[v])}
          yield self
        }
      }
    end
    
  end
  
  def get_tweet_data(user, ids)
    ids = Array(ids).uniq
    data = {}
    if ids.empty?
      yield data
    else
      load_tweet_data(user, ids, data) { yield data }
    end
  end
  
  def load_tweet_data(user, ids, data, &block)
    id = ids.shift
    if (id)
      parser = Yajl::Parser.new
      parser.on_parse_complete = proc { |parsed|
        data[id] = parsed
        load_tweet_data(ids, data, &block)
      }
      http = base.get_connection(user, "http://api.twitter.com/1/statuses/show/%s.json" % id, :get)
      http.stream { |chunk|
        parser << chunk
      }
    else
      yield
    end
  end
  
  def get_user_data(user, ids)
    ids = Array(ids).uniq
    data = {}
    if ids.empty?
      yield data
    else
      load_user_data(user, ids, data) { yield data }
    end
  end
  
  def load_user_data(user, ids, data)
    parser = Yajl::Parser.new
    parser.on_parse_complete = proc { |parsed|
      parsed.each do |user|
        data[user["id"]] = user
      end
      yield
    }
    http = base.get_connection(user, "http://api.twitter.com/1/users/lookup.json", :post, :body => {'user_id' => ids.join(',')})
    http.stream { |chunk|
      parser << chunk
    }
  end
  
end
