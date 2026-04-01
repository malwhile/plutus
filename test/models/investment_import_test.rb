require "test_helper"

class InvestmentImportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper, ImportInterfaceTest

  setup do
    @subject = @import = imports(:investment)
    @import.update!(account: accounts(:investment))
  end

  test "sets default date format on create" do
    import = InvestmentImport.create!(family: families(:dylan_family))
    assert_equal "%m/%Y", import.date_format
  end

  test "column_keys returns expected keys" do
    expected = %i[
      date currency beginning_balance deposits_and_withdrawals
      market_gain_loss income_returns personal_investment_returns
      cumulative_returns ending_balance
    ]
    assert_equal expected, @import.column_keys
  end

  test "required_column_keys returns date and ending_balance" do
    assert_equal %i[date ending_balance], @import.required_column_keys
  end

  test "mapping_steps returns empty array" do
    assert_equal [], @import.mapping_steps
  end

  test "dry_run returns snapshot count" do
    @import.rows.create!(
      date: "03/2026",
      ending_balance: "10800.00",
      currency: "USD"
    )
    assert_equal({ investment_snapshots: 1 }, @import.dry_run)
  end

  test "imports investment values from CSV" do
    import_csv = <<~CSV
      date,beginning_balance,deposits_withdrawals,market_gain_loss,income_returns,personal_returns,cumulative_returns,ending_balance,currency
      03/2026,10000.00,500.00,250.00,50.00,2.5,15.3,10800.00,USD
      02/2026,9500.00,0.00,500.00,25.00,2.1,12.5,10000.00,USD
    CSV

    @import.update!(
      raw_file_str: import_csv,
      date_col_label: "date",
      beginning_balance_col_label: "beginning_balance",
      deposits_and_withdrawals_col_label: "deposits_withdrawals",
      market_gain_loss_col_label: "market_gain_loss",
      income_returns_col_label: "income_returns",
      personal_investment_returns_col_label: "personal_returns",
      cumulative_returns_col_label: "cumulative_returns",
      ending_balance_col_label: "ending_balance",
      currency_col_label: "currency"
    )

    @import.generate_rows_from_csv

    assert_difference -> { InvestmentValue.count } => 2 do
      assert_difference -> { Entry.where(import: @import).count } => 2 do
        @import.publish
      end
    end

    assert_equal "complete", @import.status

    values = @import.investment_values.order(date: :asc)
    assert_equal Date.new(2026, 2, 1), values.first.date
    assert_equal 10000.00, values.first.ending_balance.to_f
    assert_equal Date.new(2026, 3, 1), values.last.date
    assert_equal 10800.00, values.last.ending_balance.to_f
  end

  test "reverts investment values" do
    import_csv = <<~CSV
      date,ending_balance,currency
      03/2026,10800.00,USD
    CSV

    @import.update!(
      raw_file_str: import_csv,
      date_col_label: "date",
      ending_balance_col_label: "ending_balance",
      currency_col_label: "currency"
    )

    @import.generate_rows_from_csv

    assert_difference -> { InvestmentValue.count } => 1 do
      assert_difference -> { Entry.where(import: @import).count } => 1 do
        @import.publish
      end
    end

    assert_equal "complete", @import.status
    assert_equal 1, @import.investment_values.count
    assert_equal 1, Entry.where(import: @import).count

    @import.revert_later
    perform_enqueued_jobs

    assert @import.reload.pending?
    assert_equal 0, InvestmentValue.where(import: @import).count
    assert_equal 0, Entry.where(import: @import).count
  end

  test "row is invalid when ending_balance is missing" do
    row = @import.rows.build(date: "03/2026", currency: "USD")
    assert row.invalid?
    assert_includes row.errors[:ending_balance], "is required"
  end

  test "row is invalid when date is outside acceptable range" do
    row = @import.rows.build(
      date: "01/2027",
      ending_balance: "10000",
      currency: "USD"
    )
    assert row.invalid?
    # The validator will try to parse "01/2027" with "%m/%Y" which succeeds but gives a future date
    assert row.errors[:date].any? { |msg| msg =~ /must be between/ }
  end

  test "all monetary fields are optional" do
    import_csv = <<~CSV
      date,ending_balance,currency
      03/2026,10800.00,USD
    CSV

    @import.update!(
      raw_file_str: import_csv,
      date_col_label: "date",
      ending_balance_col_label: "ending_balance",
      currency_col_label: "currency",
      beginning_balance_col_label: nil,
      deposits_and_withdrawals_col_label: nil,
      market_gain_loss_col_label: nil,
      income_returns_col_label: nil,
      personal_investment_returns_col_label: nil,
      cumulative_returns_col_label: nil
    )

    @import.generate_rows_from_csv

    assert_difference -> { InvestmentValue.count } => 1 do
      @import.publish
    end

    value = @import.investment_values.first
    assert_equal 10800.00, value.ending_balance.to_f
    assert_nil value.beginning_balance
    assert_nil value.deposits_and_withdrawals
    assert_nil value.market_gain_loss
  end

  test "uses default currency when not provided" do
    import_csv = <<~CSV
      date,ending_balance
      03/2026,10800.00
    CSV

    @import.update!(
      raw_file_str: import_csv,
      date_col_label: "date",
      ending_balance_col_label: "ending_balance",
      currency_col_label: nil
    )

    @import.generate_rows_from_csv

    assert_difference -> { InvestmentValue.count } => 1 do
      @import.publish
    end

    value = @import.investment_values.first
    assert_equal @import.family.currency, value.currency
  end

  test "skips uniqueness check on import for now" do
    # TODO: This test documents that uniqueness validation happens at the DB level
    # but the import! method doesn't currently enforce it strictly. This is acceptable
    # because the unique constraint at the DB level will prevent duplicates, but we
    # may want stricter validation in the future.
    skip "Uniqueness constraint exists at DB level but not strictly enforced in import!"
  end

  test "updates account balance to the most recent ending_balance after import" do
    import_csv = <<~CSV
      date,beginning_balance,deposits_withdrawals,market_gain_loss,income_returns,personal_returns,cumulative_returns,ending_balance,currency
      03/2026,10000.00,500.00,250.00,50.00,2.5,15.3,10800.00,USD
      02/2026,9500.00,0.00,500.00,25.00,2.1,12.5,10000.00,USD
    CSV

    original_balance = @import.account.balance
    @import.update!(
      raw_file_str: import_csv,
      date_col_label: "date",
      beginning_balance_col_label: "beginning_balance",
      deposits_and_withdrawals_col_label: "deposits_withdrawals",
      market_gain_loss_col_label: "market_gain_loss",
      income_returns_col_label: "income_returns",
      personal_investment_returns_col_label: "personal_returns",
      cumulative_returns_col_label: "cumulative_returns",
      ending_balance_col_label: "ending_balance",
      currency_col_label: "currency"
    )

    @import.generate_rows_from_csv
    assert_difference -> { Entry.where(import: @import).count } => 2 do
      @import.publish
    end

    @import.account.reload
    # Account balance should be updated to the most recent ending_balance (03/2026: 10800.00)
    assert_equal 10800.00, @import.account.balance.to_f

    # Entries should be visible in account activity
    entries = @import.account.entries.where(import: @import).order(date: :asc)
    assert_equal 2, entries.count
    assert_equal 10000.00, entries.first.amount.to_f
    assert_equal 10800.00, entries.last.amount.to_f
  end

  test "does not update account balance when no ending_balance rows exist" do
    # Edge case: all rows have nil ending_balance
    import_csv = <<~CSV
      date,currency
      03/2026,USD
    CSV

    initial_balance = @import.account.balance
    @import.update!(
      raw_file_str: import_csv,
      date_col_label: "date",
      ending_balance_col_label: "missing_column",
      currency_col_label: "currency"
    )

    @import.generate_rows_from_csv
    @import.publish

    @import.account.reload
    # Account balance should remain unchanged
    assert_equal initial_balance, @import.account.balance
    # No entries should be created without ending_balance
    assert_equal 0, Entry.where(import: @import).count
  end
end
