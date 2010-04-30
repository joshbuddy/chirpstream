class Chirpstream
  class Follow < Event
    ATTRS = [ :target, :source ]
    attr_accessor *ATTRS
    user_writer :target, :source
  end
end
