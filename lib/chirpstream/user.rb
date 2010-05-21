require 'em-http'
require 'digest/md5'

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
    
    def with_profile_image(loading_user, cache_dir)
      raise unless loaded?
      
      cached_file = File.join(cache_dir, "#{Digest::MD5.hexdigest(profile_image_url)}#{File.extname(profile_image_url)}")
      
      if File.exist?(cached_file)
        yield cached_file
      else
        http = base.get_connection(loading_user, profile_image_url, :get)
        http.callback do
          if http.response_header.status == 200
            File.open(cached_file, 'w') {|f| f << http.response}
            yield cached_file
          else
            yield nil
          end
        end
      end
      
    end
    
  end
end