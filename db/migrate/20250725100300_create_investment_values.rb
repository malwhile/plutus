class CreateInvestmentValues < ActiveRecord::Migration[7.2]
  def change
    create_table :investment_values, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.uuid :import_id
      t.date :date, null: false
      t.string :currency, null: false
      t.decimal :beginning_balance, precision: 19, scale: 4
      t.decimal :deposits_and_withdrawals, precision: 19, scale: 4
      t.decimal :market_gain_loss, precision: 19, scale: 4
      t.decimal :income_returns, precision: 19, scale: 4
      t.decimal :personal_investment_returns, precision: 19, scale: 4
      t.decimal :cumulative_returns, precision: 19, scale: 4
      t.decimal :ending_balance, precision: 19, scale: 4
      t.timestamps
    end

    add_foreign_key :investment_values, :imports
    add_index :investment_values, [ :account_id, :date, :currency ], unique: true
    add_index :investment_values, :import_id
  end
end
