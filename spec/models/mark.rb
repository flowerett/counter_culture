class Mark < ActiveRecord::Base
  belongs_to :mark_out, :polymorphic => true
  counter_culture [:mark_out, :owner], :column_name => 'marks_count'
  counter_culture [:mark_out, :owner], only: [:video, :user], :column_name => 'marks_video_count'
  counter_culture :mark_out, :column_name => 'marks_count'
end