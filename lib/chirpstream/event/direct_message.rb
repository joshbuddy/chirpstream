class Chirpstream
  class DirectMessage < TwitterObject
    
		ATTRS = [:coordinates, :recipient, :sender, :sender_screen_name, :text, :id, :recipient_id, :sender_id]
  
    attr_accessor *ATTRS
    user_writer :sender
    user_writer :recipient
  
		def initialize(base, data = nil)
			@base = base
			from_json(data['direct_message']) if data and data['direct_message']
			yield self if block_given?
		end
  
    def tweet_loadable_id
      id
    end
    
    def loaded?
      !text.nil?
    end
  end
end
