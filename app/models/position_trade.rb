# frozen_string_literal: true

class PositionTrade < ApplicationRecord
  belongs_to :position
  belongs_to :trade
end
