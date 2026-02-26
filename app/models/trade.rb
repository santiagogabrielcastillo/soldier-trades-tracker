class Trade < ApplicationRecord
  belongs_to :exchange_account

  validates :exchange_reference_id, uniqueness: { scope: :exchange_account_id }
end
