class Organization < ActiveRecord::Base
  has_many :memberships
end