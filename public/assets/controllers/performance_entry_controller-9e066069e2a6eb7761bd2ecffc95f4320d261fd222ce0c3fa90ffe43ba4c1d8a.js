import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["type", "amountField"]

  typeChanged() {
    const selected = this.typeTargets.find((r) => r.checked)?.value
    if (selected === "deposit" || selected === "withdrawal") {
      this.amountFieldTarget.classList.remove("hidden")
    } else {
      this.amountFieldTarget.classList.add("hidden")
    }
  }
};
