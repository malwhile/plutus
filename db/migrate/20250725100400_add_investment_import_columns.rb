class AddInvestmentImportColumns < ActiveRecord::Migration[7.2]
  def change
    # Add col-label columns to imports table
    add_column :imports, :beginning_balance_col_label, :string
    add_column :imports, :deposits_and_withdrawals_col_label, :string
    add_column :imports, :market_gain_loss_col_label, :string
    add_column :imports, :income_returns_col_label, :string
    add_column :imports, :personal_investment_returns_col_label, :string
    add_column :imports, :cumulative_returns_col_label, :string
    add_column :imports, :ending_balance_col_label, :string

    # Add raw value columns to import_rows table
    add_column :import_rows, :beginning_balance, :string
    add_column :import_rows, :deposits_and_withdrawals, :string
    add_column :import_rows, :market_gain_loss, :string
    add_column :import_rows, :income_returns, :string
    add_column :import_rows, :personal_investment_returns, :string
    add_column :import_rows, :cumulative_returns, :string
    add_column :import_rows, :ending_balance, :string
  end
end
