require "test_helper"

class AuditBadgeComponentTest < ViewComponent::TestCase
  test "renders nothing when last version was by the record owner" do
    trade = trades(:one)
    owner = trade.exchange_account.user
    whodunnit = { id: owner.id, name: owner.email, role: "user" }.to_json
    trade.versions.create!(event: "update", whodunnit: whodunnit)

    render_inline(AuditBadgeComponent.new(record: trade, owner: owner))
    assert_no_selector "[data-audit-badge]"
  end

  test "renders badge when last version was by an admin" do
    trade = trades(:one)
    owner = trade.exchange_account.user
    whodunnit = { id: 999, name: "admin@example.com", role: "admin" }.to_json
    trade.versions.create!(event: "update", whodunnit: whodunnit)

    render_inline(AuditBadgeComponent.new(record: trade, owner: owner))
    assert_selector "[data-audit-badge]"
  end
end
