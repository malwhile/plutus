class InvestmentValue < ApplicationRecord
  belongs_to :account
  belongs_to :import, optional: true

  validates :date, :currency, presence: true
  validates :ending_balance, numericality: true, allow_nil: true
  validates :date, uniqueness: { scope: [ :account_id, :currency ] }
end
