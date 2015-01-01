module CounterCulture
  module ActiveRecord
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
        #relation = relation.map{ |r| r.is_a?(Hash) ? r.keys.first : r }
        # TODO add method in middle classes
        # find out best way to do it
        @after_commit_counter_cache << {
          :relation => relation.is_a?(Enumerable) ? relation : [relation],
          :counter_cache_name => (options[:column_name] || "#{name.tableize}_count"),
          :column_names => options[:column_names],
          :delta_column => options[:delta_column],
          :foreign_key_values => options[:foreign_key_values],
          :touch => options[:touch],
          # Can be hash, array or symbol, array will be used only on first level
          # example { video => user }, only increment counter when first level is Video second is User classes
          # hashes can be nested like { video => { user => { .. }}}
          :only => options[:only].is_a?(Enumerable) ? options[:only] : options[:only].present? ? [options[:only]] : nil
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

      tracer = RelationTracer.new(options[:relation], self, options[:was], options[:only])
      # default to the current foreign key value
      id_to_change = tracer.id_to_change
      # allow overwriting of foreign key value by the caller
      id_to_change = options[:foreign_key_values].call(id_to_change) if options[:foreign_key_values]
      klass = tracer.klass
      # TODO add option :foreign_type_values
      if id_to_change && klass && options[:counter_column]
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
  end
end
