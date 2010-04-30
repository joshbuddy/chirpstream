class Chirpstream
  class Retweet < Event
    ATTRS = [ :target, :source, :target_object ]
    attr_accessor *ATTRS
    user_writer :target, :source
    tweet_writer :target_object
  end
end
