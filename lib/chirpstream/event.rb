class Chirpstream
  
  class Event
    
    attr_reader :data
    
    def initialize(data)
      @data = data
    end
    
    def load_all(&block)
      if unloaded_data = @data.values.find{|d| d.respond_to?(:loaded?) && !d.loaded? }
        unloaded_data.load { load_all(&block) }
      else
        block.call(self)
      end
    end
  end
end