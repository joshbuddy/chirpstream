class Chirpstream
  class User < TwitterObject

    ATTRS = [
      :profile_background_tile, :name, :profile_sidebar_border_color, :profile_sidebar_fill_color, :profile_image_url, :location, :created_at,
      :profile_link_color, :url, :contributors_enabled, :favourites_count, :utc_offset, :id, :followers_count, :protected, :lang,
      :profile_text_color, :geo_enabled, :profile_background_color, :time_zone, :notifications, :description, :verified, :profile_background_image_url,
      :statuses_count, :friends_count, :screen_name, :following
    ]
   
    attr_accessor *ATTRS
    
    def loaded?
      name
    end
    
    def user_loadable_id
      id
    end
    
  end
end