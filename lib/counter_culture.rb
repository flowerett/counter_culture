require 'fix_counters'
require 'after_commit_action'

module CounterCulture

  module ActiveRecord

    def self.included(base)
      # also add class methods to ActiveRecord::Base
      base.extend ClassMethods
      base.extend FixCounters::ClassMethods
    end

    module ClassMethods
      # this holds all configuration data
      attr_reader :after_commit_counter_cache

      # called to configure counter caches
      def counter_culture(relation, options = {})
        unless @after_commit_counter_cache
          # initialize callbacks only once
          after_create :_update_counts_after_create
          after_destroy :_update_counts_after_destroy
          after_update :_update_counts_after_update

          # we keep a list of all counter caches we must maintain
          @after_commit_counter_cache = []
        end

        # add the current information to our list
        @after_commit_counter_cache<< {
          :relation => relation.is_a?(Enumerable) ? relation : [relation],
          :counter_cache_name => (options[:column_name] || "#{name.tableize}_count"),
          :column_names => options[:column_names],
          :delta_column => options[:delta_column],
          :foreign_key_values => options[:foreign_key_values],
          :touch => options[:touch]
        }
      end
    end

    private
    # need to make sure counter_culture is only activated once
    # per commit; otherwise, if we do an update in an after_create,
    # we would be triggered twice within the same transaction -- once
    # for the create, once for the update
    def _wrap_in_counter_culture_active(&block) # TODO find better patern
      unless @_counter_culture_active # don't do anything; we are already active for this transaction
        @_counter_culture_active = true
        block.call
        execute_after_commit { @_counter_culture_active = false}
      end
    end

    # called by after_create callback
    def _update_counts_after_create
      _wrap_in_counter_culture_active do
        self.class.after_commit_counter_cache.each do |hash|
          # increment counter cache
          change_counter_cache(hash.merge(:increment => true))
        end
      end
    end

    # called by after_destroy callback
    def _update_counts_after_destroy
      _wrap_in_counter_culture_active do
        self.class.after_commit_counter_cache.each do |hash|
          # decrement counter cache
          change_counter_cache(hash.merge(:increment => false))
        end
      end
    end

    # called by after_update callback
    def _update_counts_after_update
      _wrap_in_counter_culture_active do
        self.class.after_commit_counter_cache.each do |hash| # TODO figure it out
          # figure out whether the applicable counter cache changed (this can happen
          # with dynamic column names)
          counter_cache_name_was = counter_cache_name_for(previous_model, hash[:counter_cache_name])
          counter_cache_name = counter_cache_name_for(self, hash[:counter_cache_name])
          if RelationTracer.first_changed?(hash[:relation], self) ||
            (hash[:delta_column] && send("#{hash[:delta_column]}_changed?")) ||
            counter_cache_name != counter_cache_name_was || try("#{hash[:relation].first.to_s}_type_changed?")

            # increment the counter cache of the new value
            change_counter_cache(hash.merge(:increment => true, :counter_column => counter_cache_name)) # unless try(:deleted_at_changed?)
            # decrement the counter cache of the old value
            change_counter_cache(hash.merge(:increment => false, :was => true, :counter_column => counter_cache_name_was))
          end
        end
      end
    end

    # increments or decrements a counter cache
    #
    # options:
    #   :increment => true to increment, false to decrement
    #   :relation => which relation to increment the count on,
    #   :counter_cache_name => the column name of the counter cache
    #   :counter_column => overrides :counter_cache_name
    #   :delta_column => override the default count delta (1) with the value of this column in the counted record
    #   :was => whether to get the current value or the old value of the
    #      first part of the relation
    def change_counter_cache(options)
      options[:counter_column] = counter_cache_name_for(self, options[:counter_cache_name]) unless options.has_key?(:counter_column)


      tracer = RelationTracer.new(options[:relation], self, options[:was])
      # default to the current foreign key value
      id_to_change = tracer.id_to_change
      # allow overwriting of foreign key value by the caller
      id_to_change = options[:foreign_key_values].call(id_to_change) if options[:foreign_key_values]
      klass = tracer.klass
      if id_to_change && options[:counter_column]
        delta_magnitude = if options[:delta_column]
                            delta_attr_name = options[:was] ? "#{options[:delta_column]}_was" : options[:delta_column]
                            self.send(delta_attr_name) || 0
                          else
                            1
                          end
        execute_after_commit do
          # increment or decrement?
          operator = options[:increment] ? '+' : '-'

          # we don't use Rails' update_counters because we support changing the timestamp
          quoted_column = self.class.connection.quote_column_name(options[:counter_column])

          updates = []
          # this updates the actual counter
          updates << "#{quoted_column} = COALESCE(#{quoted_column}, 0) #{operator} #{delta_magnitude}"
          # and here we update the timestamp, if so desired
          if options[:touch]
            current_time = current_time_from_proper_timezone
            timestamp_attributes_for_update_in_model.each do |timestamp_column|
              updates << "#{timestamp_column} = '#{current_time.to_formatted_s(:db)}'"
            end
          end
          klass.where(klass.primary_key => id_to_change).update_all updates.join(', ')
        end
      end
    end

    # Gets the name of the counter cache for a specific object
    #
    # obj: object to calculate the counter cache name for
    # cache_name_finder: object used to calculate the cache name
    def counter_cache_name_for(obj, cache_name_finder) # TODO rename method
      # figure out what the column name is
      if cache_name_finder.is_a? Proc
        # dynamic column name -- call the Proc
        cache_name_finder.call(obj)
      else
        # static column name
        cache_name_finder
      end
    end

    # Creates a copy of the current model with changes rolled back
    def previous_model # TODO find better solution
      prev = self.dup

      self.changed_attributes.each_pair do |key, value|
        prev.send("#{key}=".to_sym, value)
      end

      prev
    end

    class RelationTracer
      def initialize(relation, instance, was = false)
        @relations = relation.is_a?(Enumerable) ? relation : [relation]
        @klass = instance.class
        @instance = instance
        @was = was
        @traced = false
      end

      def self.first_changed?(relation, instance)
        relation = relation.is_a?(Enumerable) ? relation.first : relation
        reflect = instance.class.reflect_on_association(relation)
        instance.send("#{reflect.foreign_key}_changed?") || instance.try("#{reflect.foreign_type}_changed?")
      end

      def foreign_key
        trace_relation
        @reflect.foreign_key
      end

      def foreign_type
        trace_relation
        @reflect.foreign_type
      end

      def id_to_change
        trace_relation
        @foreign_key_value
      end

      def klass
        trace_relation
        @klass
      end

      private

      def trace_relation # TOO complicated
        return @traced if @traced
        @relations.each do |relation|
          @reflect = @klass.reflect_on_association(relation)
          raise "No relation #{relation} on #{@klass.name}" if @reflect.nil?

          if @reflect.polymorphic?
            type_method = @was ? "#{@reflect.foreign_type}_was" : "#{@reflect.foreign_type}"
            @klass = @instance.send(type_method).try(:classify).try(:constantize)
          else
            @klass = @reflect.klass
          end

          break if @klass.nil?

          id_method = @was ? "#{@reflect.foreign_key}_was" : "#{@reflect.foreign_key}"
          @foreign_key_value = @instance.send(id_method)
          @instance = @klass.find_by(@klass.primary_key => @foreign_key_value)

          break if @instance.nil?
        end
        @traced = true
      end
    end
    # gets the value of the foreign key on the given relation
    #
    # relation: a symbol or array of symbols; specifies the relation
    #   that has the counter cache column
    # was: whether to get the current or past value from ActiveRecord;
    #   pass true to get the past value, false or nothing to get the
    #   current value
    def foreign_key_value(relation, was = false) # TODO fail with polymorphic when update to different class
      relation =
      if was
        foreign_key_value = send("#{relation_foreign_key(relation)}_was")
        value = relation_klass(first, was).find(foreign_key_value) if foreign_key_value
      else
        value = self
      end
      while !value.nil? && relation.size > 0
        value = value.send(relation.shift) # what if we updated records before?
      end
      return value.try(:id)
    end


      # gets the reflect object on the given relation
      #
      # relation: a symbol or array of symbols; specifies the relation
      #   that has the counter cache column
      def relation_reflect(relation, was = false)
        relation = relation.is_a?(Enumerable) ? relation.dup : [relation]

        # go from one relation to the next until we hit the last reflect object
        klass = self.class
        instance = self
        while relation.size > 0
          cur_relation = relation.shift

          reflect = klass.reflect_on_association(cur_relation)
          raise "No relation #{cur_relation} on #{klass.name}" if reflect.nil?
          # Check if relation polymorphic and get through instance klass of relation
          if reflect.polymorphic?
            type_method = was ? "#{reflect.foreign_type}_was" : "#{reflect.foreign_type}"
            id_method = was ? "#{reflect.foreign_key}_was" : "#{reflect.foreign_key}"
            klass = instance.send(type_method).classify.constantize #TODO can be null
            instance = klass.find_by(klass.primary_key => instance.send(id_method))
          else
            klass = reflect.klass
            instance = klass.find_by(klass.primary_key => instance.try(reflect.foreign_key))
          end
        end

        return reflect, klass, instance
      end

      # gets the class of the given relation
      #
      # relation: a symbol or array of symbols; specifies the relation
      #   that has the counter cache column
      def relation_klass(relation, was = false) # TODO same as below
        relation_reflect(relation, was).second
      end

      # gets the foreign key name of the given relation
      #
      # relation: a symbol or array of symbols; specifies the relation
      #   that has the counter cache column
      def relation_foreign_key(relation)
        relation_reflect(relation).first.foreign_key
      end

      # gets the foreign key name of the relation. will look at the first
      # level only -- i.e., if passed an array will consider only its
      # first element
      #
      # relation: a symbol or array of symbols; specifies the relation
      #   that has the counter cache column
      def first_level_relation_foreign_key(relation)
        relation = relation.first if relation.is_a?(Enumerable)
        relation_reflect(relation).first.foreign_key
      end

      def first_polymorphic?(relation)
        relation = relation.first if relation.is_a?(Enumerable)
        relation_reflect(relation).first.polymorphic?
      end
  end

  # extend ActiveRecord with our own code here
  ::ActiveRecord::Base.send :include, ActiveRecord
end

