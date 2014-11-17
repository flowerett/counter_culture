class Video < ActiveRecord::Base
  belongs_to :owner, :polymorphic => true
  has_many :marks
  counter_culture :owner
end
