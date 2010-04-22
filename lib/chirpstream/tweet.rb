class Chirpstream
  class Tweet
    
    URL = "http://api.twitter.com/1/statuses/show/%s.json"

    attr_reader :id, :data
    
    def initialize(base, id)
      @base = base
      @id = id
    end
    
    def load
      unless loaded?
        http = EM::HttpRequest.new(URL % id).get(:head => {'authorization' => [@base.username, @base.password]})
        http.callback {
          if http.response_header.status == 200
            @data = JSON.parse(http.response)
            yield self
          end
        }
      end
    end
    
    def loaded?
      @data
    end
  end
end