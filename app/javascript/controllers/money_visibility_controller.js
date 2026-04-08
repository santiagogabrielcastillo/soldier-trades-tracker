import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "money_hidden"
const MASK = '<span class="font-numeric text-slate-300 select-none" aria-hidden="true">*</span>'

export default class extends Controller {
  static targets = ["eyeOn", "eyeOff"]

  connect() {
    this.#applyVisibility(localStorage.getItem(STORAGE_KEY) === "true")
  }

  toggle() {
    const next = !(localStorage.getItem(STORAGE_KEY) === "true")
    localStorage.setItem(STORAGE_KEY, String(next))
    this.#applyVisibility(next)
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
  }
}
