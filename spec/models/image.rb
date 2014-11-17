class Image < ActiveRecord::Base
  belongs_to :owner, :polymorphic => true
  counter_culture :owner
end