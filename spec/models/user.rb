class User < ActiveRecord::Base
  belongs_to :employer
  has_many :albums

  belongs_to :manages_company, :class_name => "Company"
  counter_culture :manages_company, :column_name => "managers_count"
  belongs_to :has_string_id
  counter_culture :has_string_id

  has_many :images
  has_many :videos
  has_many :albums

  has_many :reviews
  accepts_nested_attributes_for :reviews, :allow_destroy => true
end
