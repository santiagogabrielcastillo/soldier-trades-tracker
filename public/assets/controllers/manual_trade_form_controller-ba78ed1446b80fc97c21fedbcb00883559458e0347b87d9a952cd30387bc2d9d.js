import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["quantity", "price", "netAmountPreview"]

  connect() { this.updateNetAmount() }

  updateNetAmount() {
    if (!this.hasNetAmountPreviewTarget) return

    const qty   = parseFloat(this.quantityTarget?.value) || 0
    const price = parseFloat(this.priceTarget?.value)   || 0
    const side  = this.element.querySelector('select[name$="[side]"]')?.value || "buy"

    if (qty <= 0 || price <= 0) {
      this.netAmountPreviewTarget.textContent = "—"
      return
    }

    const notional = qty * price
    const signed   = side === "sell" ? notional : -notional
    const formatted = new Intl.NumberFormat("en-US", {
      style: "currency", currency: "USD",
      minimumFractionDigits: 2, maximumFractionDigits: 8
    }).format(signed)

    this.netAmountPreviewTarget.textContent =
      `${formatted} (${side === "sell" ? "received" : "spent"})`
  }
};
