class Chirpstream
  class Delete < Event
    ATTRS = [:id, :user_id]
    attr_accessor *ATTRS
    user_writer :user_id
  end
end