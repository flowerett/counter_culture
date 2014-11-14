class Community < ActiveRecord::Base
  has_many :memberships
end