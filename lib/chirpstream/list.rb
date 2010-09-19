class Chirpstream
	class List < TwitterObject
		ATTRS = [:slug, :name, :uri, :subscriber_count, :mode, :member_count, :id, :full_name, :description]
		attr_accessor *ATTRS
	end
end
