module CounterCulture
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
          tracer = StaticTracer.new(cur_relation, @main_klass)
          @reflects, @klasses = tracer.reflections, tracer.klasses
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
          joins_query = build_join(
            @reflect.active_record.table_name,
            join_table_name,
            "#{@last_union_name}.#{@last_primary_key}",
            "#{join_table_name}.#{@reflect.foreign_key}"
          )
          @last_union_name = "#{join_table_name}"
          @last_primary_key = "#{@reflect.active_record.primary_key}"
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
end