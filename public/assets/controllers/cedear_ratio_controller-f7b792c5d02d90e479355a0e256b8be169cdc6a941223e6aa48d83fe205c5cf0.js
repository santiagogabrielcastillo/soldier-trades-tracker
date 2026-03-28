import { Controller } from "@hotwired/stimulus"

// Fetches the CEDEAR ratio for a given ticker on blur and populates the ratio field.
// Usage: data-controller="cedear-ratio"
//        data-cedear-ratio-lookup-url-value="/cedear_instruments/lookup"
//        data-cedear-ratio-target="ticker" (on the ticker input)
//        data-cedear-ratio-target="ratio"  (on the ratio input)
export default class extends Controller {
  static targets = ["ticker", "ratio"]
  static values = { lookupUrl: String }

  async tickerChanged() {
    const ticker = this.tickerTarget.value.trim().toUpperCase()
    if (!ticker) return

    try {
      const url = `${this.lookupUrlValue}?ticker=${encodeURIComponent(ticker)}`
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) return

      const data = await response.json()
      if (data.ratio != null && this.ratioTarget.value === "") {
        this.ratioTarget.value = data.ratio
      }
    } catch (_e) {
      // Silently ignore network errors — ratio field remains editable
    }
  }
};
