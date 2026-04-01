import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["drawer", "overlay"]

  connect() {
    this._onKeydown = (e) => { if (e.key === "Escape") this.close() }
    document.addEventListener("keydown", this._onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKeydown)
    this.close()
  }

  open(event) {
    this._opener = event?.currentTarget ?? null
    this._isClosing = false
    this.drawerTarget.classList.remove("-translate-x-full")
    this.overlayTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
    if (this._opener) this._opener.setAttribute("aria-expanded", "true")
    this.drawerTarget.querySelector("nav a, nav button")?.focus()
  }

  close() {
    if (this._isClosing) return
    this._isClosing = true
    this.drawerTarget.classList.add("-translate-x-full")
    this.overlayTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
    if (this._opener) {
      this._opener.setAttribute("aria-expanded", "false")
      this._opener.focus()
      this._opener = null
    }
    this.drawerTarget.addEventListener(
      "transitionend",
      () => { this._isClosing = false },
      { once: true }
    )
  }
}
