import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["result"]
  static values = { testUrl: String }

  testConnection(event) {
    const btn = event.currentTarget
    const result = this.resultTarget

    btn.disabled = true
    btn.textContent = "Testing..."
    result.textContent = ""
    result.className = "text-sm"

    fetch(this.testUrlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
        "Accept": "application/json"
      }
    })
      .then(res => res.json())
      .then(data => {
        if (data.success) {
          result.textContent = "\u2713 Connection successful"
          result.className = "text-sm font-medium text-emerald-600"
        } else {
          result.textContent = "\u2717 " + (data.error || "Invalid key")
          result.className = "text-sm font-medium text-red-600"
        }
      })
      .catch(() => {
        result.textContent = "\u2717 Request failed"
        result.className = "text-sm font-medium text-red-600"
      })
      .finally(() => {
        btn.disabled = false
        btn.textContent = "Test Connection"
      })
  }
}
