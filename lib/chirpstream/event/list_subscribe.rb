
class Chirpstream
	class ListUserSubscribed < Event
    ATTRS = [ :target, :source, :target_object ]
    attr_accessor *ATTRS
    user_writer :target, :source
    list_writer :target_object
	end
	class ListUserUnsubscribed < ListUserSubscribed
	end
end
