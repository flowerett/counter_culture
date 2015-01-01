ENV['RAILS_ENV'] = 'test'

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))

require "rails_app/config/environment"

require 'rspec'
require 'counter_culture'

load "#{File.dirname(__FILE__)}/schema.rb"

# Requires supporting files with custom matchers and macros, etc,
# in ./support/ and its subdirectories.
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each {|f| require f}


ActiveRecord::Base.logger = Logger.new(STDOUT)
ActiveRecord::Base.logger.level = 0

RSpec.configure do |config|
  config.fail_fast = true
end

# I don't known why, but its not working other way, but on my other machine it works perfectly (WTF?)
require "#{File.dirname(__FILE__)}/models/review.rb"
require "#{File.dirname(__FILE__)}/models/twitter_review.rb"
Dir["#{File.dirname(__FILE__)}/models/*.rb"].each {|f| require f }
