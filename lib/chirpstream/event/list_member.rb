
class Chirpstream
	class ListMemberAdded < Event
    ATTRS = [ :target, :source, :target_object ]
    attr_accessor *ATTRS
    user_writer :target, :source
    list_writer :target_object
	end
	class ListMemberRemoved < ListMemberAdded
	end
end
