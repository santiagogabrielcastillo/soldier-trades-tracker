import { Controller } from "@hotwired/stimulus"

// STORAGE_KEY duplicated in application layout boot script (must stay in sync).
const STORAGE_KEY = "money_hidden"
const MASK = '<span class="font-numeric text-slate-300 select-none" aria-hidden="true">*</span>'

export default class extends Controller {
  static targets = ["eyeOn", "eyeOff"]

  connect() {
    this.#applyVisibility(this.#getHidden())
    document.documentElement.classList.remove("money-hidden--boot")
  }

  disconnect() {
    // When amounts are hidden, do not restore DOM text — it can run after Turbo swaps
    // the body and would briefly reveal figures on the new page.
    if (!this.#getHidden()) this.#applyVisibility(false)
  }

  toggle() {
    const next = !this.#getHidden()
    this.#setHidden(next)
    this.#applyVisibility(next)
  }

  #getHidden() {
    try { return localStorage.getItem(STORAGE_KEY) === "true" } catch { return false }
  }

  #setHidden(value) {
    try { localStorage.setItem(STORAGE_KEY, String(value)) } catch { /* ignore */ }
  }

  #applyVisibility(hidden) {
    document.querySelectorAll("[data-money]").forEach(el => {
      if (hidden) {
        if (!el.dataset.originalContent) {
          el.dataset.originalContent = el.innerHTML
        }
        el.innerHTML = MASK
      } else {
        if (el.dataset.originalContent !== undefined) {
          el.innerHTML = el.dataset.originalContent
          delete el.dataset.originalContent
        }
      }
    })

    this.eyeOnTargets.forEach(t => t.classList.toggle("hidden", hidden))
    this.eyeOffTargets.forEach(t => t.classList.toggle("hidden", !hidden))

    document.querySelectorAll("[data-action*='money-visibility#toggle']").forEach(btn => {
      btn.setAttribute("aria-pressed", String(hidden))
    })
  }
}
