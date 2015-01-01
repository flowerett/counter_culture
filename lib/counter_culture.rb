require 'counter_culture/helpers/relation_tracer'
require 'counter_culture/helpers/join_builder'
require 'counter_culture/fixer'
require 'counter_culture/counter'
require 'after_commit_action'

module CounterCulture

  module ActiveRecord

    def self.included(base)
      # also add class methods to ActiveRecord::Base
      base.extend ClassMethods
    end
  end

  # extend ActiveRecord with our own code here
  ::ActiveRecord::Base.send :include, ActiveRecord
end
