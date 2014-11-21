class Image < ActiveRecord::Base
  belongs_to :owner, :polymorphic => true
  counter_culture :owner
  belongs_to :album
  counter_culture [:album, :owner], column_name: 'album_images_count'
  has_many :marks
end