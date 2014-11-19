module FixCounters
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
        klasses = relation_klass(hash[:relation])
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

          builder = JoinBuilder.new(reverse_relation, klass, self)
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
              records.each do |model|
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

    class JoinBuilder
      attr_reader :last_union_name, :last_primary_key
      def initialize(reverse_relation, klass, main_klass)
        @reverse_relation= reverse_relation
        @klass = klass
        @last_union_name = klass.table_name
        @last_primary_key = klass.primary_key
        @join_klass = klass
        @main_klass = main_klass
      end

      def build_joins
        joins = @reverse_relation.map { |relation| build_joins_step(relation)}
        joins
      end

      private

      def build_joins_step(cur_relation)
        @reflects, @klasses = @main_klass.relation_reflect(cur_relation)
        @reflect = @reflects.first
        # All reflects are differ only by active_record field
        join_query =  @reflect.polymorphic? ? build_polymorphic : build_simple
        # adds 'type' condition to JOIN clause if the current model is a child in a Single Table Inheritance
        # join with alias to avoid ambiguous table name with self-referential models:
        if @main_klass.column_names.include?('type') and not(@main_klass.descends_from_active_record?)
          join_query = "#{join_query} AND #{@reflect.active_record.table_name}.type IN ('#{@main_klass.name}')"
        end
        join_query
      end

      def build_polymorphic
        # Build special type of join with union for polymorphic reflections
        # example:
        #  LEFT JOIN
        #   (
        #     SELECT images.id as primary_key_owner, images.owner_id as owner_id, images.owner_type as owner_type, 'Image' as next_join_type FROM images
        #     UNION
        #     SELECT videos.id as primary_key_owner, videos.owner_id as owner_id, videos.owner_type as owner_type, 'Video' as next_join_type FROM videos
        #   )
        #   AS join_query_owner ON join_query_owner.owner_id = companies.id ANDjoin_query_owner.owner_type = 'Company'
        #     LEFT JOIN
        #      (
        #         SELECT marks.id as primary_key_mark_out, marks.mark_out_id as mark_out_id, marks.mark_out_type as mark_out_type, 'Mark' as next_join_type FROM marks
        #      )
        #     AS join_query_mark_out ON join_query_mark_out.mark_out_id = join_query_owner.primary_key_owner AND join_query_mark_out.mark_out_type = join_query_owner.next_join_type
        joins_query = build_join(
          @reflects.map {|r| build_union(r)}.join(" UNION "),
          "join_query_#{@reflect.name}",
          "join_query_#{@reflect.name}.#{@reflect.foreign_key}",
          "#{@last_union_name}.#{@last_primary_key}",
          "join_query_#{@reflect.name}.#{@reflect.foreign_type}",
          @klass.present? ? "'#{@klass.name}'" : "#{@last_union_name}.next_join_type"
        )
        @last_union_name = "join_query_#{@reflect.name}"
        @last_primary_key = "primary_key_#{@reflect.name}"
        @klass = nil
        joins_query
      end

      def build_simple
        klass = @klasses.first
        if klass.table_name == @reflect.active_record.table_name
          join_table_name = "#{klass.table_name}_#{klass.table_name}"
        else
          join_table_name = @reflect.active_record.table_name
        end
        @last_union_name = "#{join_table_name}"
        @last_primary_key = "#{@reflect.active_record.primary_key}"
        joins_query = build_join(
          @reflect.active_record.table_name,
          join_table_name,
          "#{@reflect.table_name}.#{@reflect.klass.primary_key}",
          "#{join_table_name}.#{@reflect.foreign_key}"
        )
        joins_query
      end

      def query_wrapper(raw_query)
        raw_query.gsub("\n", " ").split.join(" ")
      end

      def build_union(reflect)
        join_table_name = reflect.active_record.table_name
        reflect_name = reflect.name
        query_wrapper(
          <<-SQL
            SELECT
              #{join_table_name}.#{reflect.active_record.primary_key} as primary_key_#{reflect_name},
              #{join_table_name}.#{reflect.foreign_key} as #{reflect.foreign_key},
              #{join_table_name}.#{reflect.foreign_type} as #{reflect.foreign_type},
              '#{reflect.active_record.name}' as next_join_type
            FROM #{join_table_name}
          SQL
        )
      end

      def build_join(what_to_join, join_name, on_first_id, on_second_id, on_first_type = nil, on_second_type = nil)
        join = <<-SQL
          LEFT JOIN
            (#{what_to_join})
          AS #{join_name}
          ON #{on_first_id} = #{on_second_id}
        SQL
        join += "AND #{on_first_type} = #{on_second_type}" if on_first_type.present? && on_second_type.present?
        query_wrapper(join)
      end
    end

    def relation_reflect(relation)
      relation = relation.is_a?(Enumerable) ? relation.dup : [relation]
      # go from one relation to the next until we hit the last reflect object
      klasses = [self]
      reflects = []
      while relation.size > 0
        cur_relation = relation.shift
        reflects = klasses.map{ |k| k.reflect_on_association(cur_relation)}
        raise "No relation #{cur_relation} on #{klass.name}" if reflects.compact.size != klasses.size
        reflect = reflects.first  # TODO not right, because of first table
        ok = reflects.all?{ |r| r.foreign_key == reflect.foreign_key } || reflects.all?{ |r| r.polymorphic? == reflect.polymorphic? }
        raise "Invalid relation" unless ok
        if reflect.polymorphic?
          klasses = klasses.map { |k| polymorphic_klasses(k, cur_relation) }.flatten.map{|k| k.classify.constantize }
        else
          klasses = [reflect.klass]
        end
      end

      return reflects, klasses
    end

    def relation_klass(relation) # TODO same as below
      reflects, klasses = relation_reflect(relation)
      klasses
    end

    private

    # TODO move to separate module
    def polymorphic_klasses(klass, cur_relation)
      klass.group("#{cur_relation}_type").pluck("#{cur_relation}_type")
    end
  end

  def self.included(base)
    base.extend(ClassMethods)
  end
end