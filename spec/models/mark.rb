class Mark < ActiveRecord::Base
  belongs_to :mark_out, :polymorphic => true
  counter_culture [:mark_out, :owner], :column_name => 'marks_count'
  counter_culture :mark_out, :column_name => 'marks_count'
end