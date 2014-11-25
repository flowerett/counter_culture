module CounterCulture
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

      def trace_klass
        @klass = if @reflect.polymorphic?
          type_method = @was ? "#{@reflect.foreign_type}_was" : "#{@reflect.foreign_type}"
          @instance.send(type_method).try(:classify).try(:constantize)
        else
          @reflect.klass
        end
      end

      def trace_instance
        id_method = @was ? "#{@reflect.foreign_key}_was" : "#{@reflect.foreign_key}"
        @foreign_key_value = @instance.send(id_method)
        @instance = @klass.find_by(@klass.primary_key => @foreign_key_value)
        @instance
      end

      def trace_relation
        unless @traced
          @relations.each do |relation|
            @reflect = @klass.reflect_on_association(relation)
            raise "No relation #{relation} on #{@klass.name}" if @reflect.nil?
            break if trace_klass.nil? || trace_instance.nil?
          end
        end

        @traced = true
      end
    end
end
