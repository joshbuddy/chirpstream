begin
  require 'jeweler'
  Jeweler::Tasks.new do |s|
    s.name = "chirpstream"
    s.description = s.summary = "Eventmachine-based Chirpstream client"
    s.email = "joshbuddy@gmail.com"
    s.homepage = "http://github.com/joshbuddy/chirpstream"
    s.authors = ["Joshua Hull"]
    s.files = FileList["[A-Z]*", "{lib}/**/*"]
    s.add_dependency 'eventmachine', ">= 0.12.10"
    s.add_dependency 'em-http-request', ">= 0.2.7"
    s.add_dependency 'yajl-ruby', ">= 0.7.5"
    s.add_dependency 'load_path_find', ">= 0.0.5"
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
end
