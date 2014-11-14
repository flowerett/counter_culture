class Memberships < ActiveRecord::Base
  belongs_to :user
  belongs_to :group, polymorphic: true

  counter_culture :group
end