class InvestmentImport < Import
  after_create :set_default_date_format

  def import!
    raise "InvestmentImport requires an account" unless account.present?

    transaction do
      rows.each do |row|
        investment_value = InvestmentValue.create!(
          account: account,
          import: self,
          date: Date.strptime(row.date, date_format),
          currency: row.currency.presence || default_currency,
          beginning_balance: row.beginning_balance.presence&.to_d,
          deposits_and_withdrawals: row.deposits_and_withdrawals.presence&.to_d,
          market_gain_loss: row.market_gain_loss.presence&.to_d,
          income_returns: row.income_returns.presence&.to_d,
          personal_investment_returns: row.personal_investment_returns.presence&.to_d,
          cumulative_returns: row.cumulative_returns.presence&.to_d,
          ending_balance: row.ending_balance.presence&.to_d
        )

        # Create an entry for the investment snapshot
        if investment_value.ending_balance.present?
          account.entries.create!(
            entryable: Valuation.new(kind: "reconciliation"),
            amount: investment_value.ending_balance,
            name: "Investment snapshot",
            currency: investment_value.currency,
            date: investment_value.date,
            import: self
          )
        end
      end

      # Update account balance to the latest ending_balance
      latest_value = account.investment_values.order(date: :desc).first
      account.update!(balance: latest_value.ending_balance) if latest_value&.ending_balance.present?
    end
  end

  def revert
    InvestmentValue.where(import: self).destroy_all
    Entry.where(import: self).destroy_all
    family.sync_later
    update! status: :pending
  rescue => error
    update! status: :revert_failed, error: error.message
  end

  def generate_rows_from_csv
    rows.destroy_all

    mapped_rows = csv_rows.map do |row|
      {
        date: row[date_col_label].to_s,
        currency: (row[currency_col_label] || default_currency).to_s,
        beginning_balance: sanitize_number(row[beginning_balance_col_label]).to_s,
        deposits_and_withdrawals: sanitize_number(row[deposits_and_withdrawals_col_label]).to_s,
        market_gain_loss: sanitize_number(row[market_gain_loss_col_label]).to_s,
        income_returns: sanitize_number(row[income_returns_col_label]).to_s,
        personal_investment_returns: sanitize_number(row[personal_investment_returns_col_label]).to_s,
        cumulative_returns: sanitize_number(row[cumulative_returns_col_label]).to_s,
        ending_balance: sanitize_number(row[ending_balance_col_label]).to_s
      }
    end

    rows.insert_all!(mapped_rows)
  end

  def required_column_keys
    %i[date ending_balance]
  end

  def column_keys
    %i[
      date currency beginning_balance deposits_and_withdrawals
      market_gain_loss income_returns personal_investment_returns
      cumulative_returns ending_balance
    ]
  end

  def mapping_steps
    []
  end

  def dry_run
    { investment_snapshots: rows.count }
  end

  def csv_template
    template = <<~CSV
      date*,beginning_balance,deposits_withdrawals,market_gain_loss,income_returns,personal_returns,cumulative_returns,ending_balance*,currency
      03/2026,10000.00,500.00,250.00,50.00,2.5,15.3,10800.00,USD
      02/2026,9500.00,0.00,500.00,25.00,2.1,12.5,10000.00,USD
    CSV

    CSV.parse(template, headers: true)
  end

  private
    def set_default_date_format
      self.date_format = "%m/%Y"
      save!
    end
end
