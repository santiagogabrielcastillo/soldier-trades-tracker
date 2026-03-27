import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "stocks_table_amounts_hidden"
const MASK = '<span class="font-numeric text-slate-300 select-none">*</span>'

export default class extends Controller {
  static targets = ["moneyCell", "eyeOn", "eyeOff"]

  connect() {
    this.#applyVisibility(localStorage.getItem(STORAGE_KEY) === "true")
  }

  toggle() {
    const nextHidden = !(localStorage.getItem(STORAGE_KEY) === "true")
    localStorage.setItem(STORAGE_KEY, String(nextHidden))
    this.#applyVisibility(nextHidden)
  }

  #applyVisibility(hidden) {
    this.moneyCellTargets.forEach(el => {
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

    if (this.hasEyeOnTarget)  this.eyeOnTarget.classList.toggle("hidden", hidden)
    if (this.hasEyeOffTarget) this.eyeOffTarget.classList.toggle("hidden", !hidden)
  }
}
