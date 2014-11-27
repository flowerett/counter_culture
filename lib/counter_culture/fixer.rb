module CounterCulture
  module ActiveRecord
    module ClassMethods
      # checks all of the declared counter caches on this class for correctnes based
      # on original data; if the counter cache is incorrect, sets it to the correct
      # count
      #
      # options:
      #   { :exclude => list of relations to skip when fixing counts,
      #     :only => only these relations will have their counts fixed }
      # returns: a list of fixed record as an array of hashes of the form:
      #   { :entity => which model the count was fixed on,
      #     :id => the id of the model that had the incorrect count,
      #     :what => which column contained the incorrect count,
      #     :wrong => the previously saved, incorrect count,
      #     :right => the newly fixed, correct count }
      #
      def counter_culture_fix_counts(options = {})
        raise "No counter cache defined on #{self.name}" unless @after_commit_counter_cache

        options[:exclude] = [options[:exclude]] if options[:exclude] && !options[:exclude].is_a?(Enumerable)
        options[:exclude] = options[:exclude].try(:map) {|x| x.is_a?(Enumerable) ? x : [x] }
        options[:only] = [options[:only]] if options[:only] && !options[:only].is_a?(Enumerable)
        options[:only] = options[:only].try(:map) {|x| x.is_a?(Enumerable) ? x : [x] }

        fixed = []
        @after_commit_counter_cache.each do |hash|
          next if options[:exclude] && options[:exclude].include?(hash[:relation])
          next if options[:only] && !options[:only].include?(hash[:relation])

          if options[:skip_unsupported]
            next if (hash[:foreign_key_values] || (hash[:counter_cache_name].is_a?(Proc) && !hash[:column_names]))
          else
            raise "Fixing counter caches is not supported when using :foreign_key_values; you may skip this relation with :skip_unsupported => true" if hash[:foreign_key_values]
            raise "Must provide :column_names option for relation #{hash[:relation].inspect} when :column_name is a Proc; you may skip this relation with :skip_unsupported => true" if hash[:counter_cache_name].is_a?(Proc) && !hash[:column_names]
          end

          # if we're provided a custom set of column names with conditions, use them; just use the
          # column name otherwise
          # which class does this relation ultimately point to? that's where we have to start
          # In case of polymorphic assosoations is a array of classes
          klasses = StaticTracer.new(hash[:relation], self).klasses
          klasses.each do |klass|
            query = klass
            if klass.table_name == self.table_name
              self_table_name = "#{self.table_name}_#{self.table_name}"
            else
              self_table_name = self.table_name
            end
            column_names = hash[:column_names] || {nil => hash[:counter_cache_name]}
            raise ":column_names must be a Hash of conditions and column names" unless column_names.is_a?(Hash)

            # we need to work our way back from the end-point of the relation to this class itself;
            # make a list of arrays pointing to the second-to-last, third-to-last, etc.
            reverse_relation = (1..hash[:relation].length).to_a.reverse.inject([]) {|a,i| a << hash[:relation][0,i]; a }

            # store joins in an array so that we can later apply column-specific conditions

            builder = JoinBuilder.new(reverse_relation, klass, self, hash[:union_load_columns])
            joins = builder.build_joins

            # if a delta column is provided use SUM, otherwise use COUNT
            count_select = hash[:delta_column] ? "SUM(COALESCE(#{self_table_name}.#{hash[:delta_column]},0))" : "COUNT(#{builder.last_union_name}.#{builder.last_primary_key})"

            # respect the deleted_at column if it exists
            # TODO make sure we actually need this
            # query = query.where("#{last_union_name}.deleted_at IS NULL") if self.column_names.include?('deleted_at')


            # iterate over all the possible counter cache column names

            column_names.each do |where, column_name|
            # select id and count (from above) as well as cache column ('column_name') for later comparison
              counts_query = query.select("#{klass.table_name}.#{klass.primary_key}, #{count_select} AS count, #{klass.table_name}.#{column_name}")

              # we need to join together tables until we get back to the table this class itself lives in
              # conditions must also be applied to the join on which we are counting
              joins.each_with_index do |join,index|
                join += " AND (#{sanitize_sql_for_conditions(where)})" if index == joins.size - 1 && where
                counts_query = counts_query.joins(join)
              end

              # iterate in batches; otherwise we might run out of memory when there's a lot of
              # instances and we try to load all their counts at once
              start = 0
              batch_size = options[:batch_size] || 1000
              while (records = counts_query.reorder(full_primary_key(klass) + " ASC").offset(start).limit(batch_size).group(full_primary_key(klass)).to_a).any?
                # now iterate over all the models and see whether their counts are right
                records.each do |model| # TODO batch update???
                  count = model.read_attribute('count') || 0
                  if model.read_attribute(column_name) != count
                    # keep track of what we fixed, e.g. for a notification email
                    fixed<< {
                      :entity => klass.name,
                      klass.primary_key.to_sym => model.send(klass.primary_key),
                      :what => column_name,
                      :wrong => model.send(column_name),
                      :right => count
                    }
                    # use update_all because it's faster and because a fixed counter-cache shouldn't
                    # update the timestamp
                    klass.where(klass.primary_key => model.send(klass.primary_key)).update_all(column_name => count)
                  end
                end
                start += batch_size
              end
            end
          end
        end

        return fixed
      end

      private

      # the string to pass to order() in order to sort by primary key
      def full_primary_key(klass)
        "#{klass.quoted_table_name}.#{klass.quoted_primary_key}"
      end
    end
  end
end