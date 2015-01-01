class Album < ActiveRecord::Base
  belongs_to :owner, polymorphic: true
  has_many :images
  has_many :videos
end