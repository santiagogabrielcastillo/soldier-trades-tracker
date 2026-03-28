# frozen_string_literal: true

require "test_helper"

class HistoricSyncJobTest < ActiveJob::TestCase
  setup do
    # Create account via model so api_key/api_secret are encrypted in-process (avoids Decryption in job).
    @account = ExchangeAccount.create!(
      user: users(:one),
      provider_type: "bingx",
      api_key: "test_key",
      api_secret: "test_secret",
      linked_at: 1.day.ago,
      last_synced_at: 1.day.ago
    )
  end

  test "clears last_synced_at before calling SyncService with historic: true" do
    cleared = false
    synced_historic = false

    ExchangeAccounts::SyncService.stub(:call, ->(account, historic: false) {
      cleared = account.last_synced_at.nil?
      synced_historic = historic
      :ok
    }) do
      HistoricSyncJob.perform_now(@account.id)
    end

    assert cleared, "Expected last_synced_at to be nil before SyncService.call"
    assert synced_historic, "Expected SyncService.call to be called with historic: true"
  end

  test "clears historic_sync_requested_at after successful sync" do
    @account.update!(historic_sync_requested_at: Time.current)

    ExchangeAccounts::SyncService.stub(:call, ->(*) { :ok }) do
      HistoricSyncJob.perform_now(@account.id)
    end

    @account.reload
    assert_nil @account.historic_sync_requested_at
  end

  test "records sync failure and re-raises on error" do
    ExchangeAccounts::SyncService.stub(:call, ->(*) { raise Exchanges::ApiError, "timeout" }) do
      assert_raises(Exchanges::ApiError) do
        HistoricSyncJob.perform_now(@account.id)
      end
    end

    @account.reload
    assert @account.last_sync_failed_at.present?
    assert_match(/timeout/, @account.last_sync_error)
  end

  test "returns early without error when account does not exist" do
    assert_nothing_raised do
      HistoricSyncJob.perform_now(999_999_999)
    end
  end
end
