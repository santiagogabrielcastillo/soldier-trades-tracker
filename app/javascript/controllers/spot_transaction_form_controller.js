import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tokenWrapper", "priceWrapper"]

  connect() {
    this.togglePriceAndToken()
  }

  togglePriceAndToken() {
    const sideSelect = this.element.querySelector('select[name="side"]')
    if (!sideSelect || !this.hasTokenWrapperTarget || !this.hasPriceWrapperTarget) return
    const value = sideSelect.value
    const isCash = value === "deposit" || value === "withdraw"
    this.tokenWrapperTarget.hidden = isCash
    this.priceWrapperTarget.hidden = isCash
  }
}
