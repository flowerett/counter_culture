class Video < ActiveRecord::Base
  belongs_to :owner, :polymorphic => true
  belongs_to :album
  has_many :marks

  counter_culture :owner
  counter_culture [:album, :owner], :column_name => 'album_videos_count'
end
