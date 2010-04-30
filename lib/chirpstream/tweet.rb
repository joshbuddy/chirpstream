class Chirpstream
  class Tweet < TwitterObject
    
    ATTRS = [:coordinates, :favorited, :created_at, :truncated, :contributors, :text, :id, :geo, :in_reply_to_user_id, :place, :source, :in_reply_to_screen_name, :in_reply_to_status_id, :user]
  
    attr_accessor *ATTRS
    user_writer :user
  
    def tweet_loadable_id
      id
    end
    
    def loaded?
      !text.nil?
    end
  end
end