import { Controller } from "@hotwired/stimulus"

// ARIA combobox for token search: filter list on input, keyboard (ArrowUp/Down, Enter, Escape), click to select.
export default class extends Controller {
  static targets = ["input", "listbox"]
  static values = { tokens: Array }

  connect() {
    this.filteredTokens = this.tokensValue || []
    this.highlightedIndex = -1
    const listbox = this.listboxTarget
    const id = listbox.id || "spot-token-listbox"
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.setAttribute("aria-haspopup", "listbox")
    this.inputTarget.setAttribute("aria-controls", id)
    this.inputTarget.setAttribute("aria-autocomplete", "list")
    listbox.setAttribute("role", "listbox")
    listbox.setAttribute("id", id)
    listbox.hidden = true
  }

  filter(event) {
    const q = (event.target.value || "").trim().toUpperCase()
    this.filteredTokens = q
      ? this.tokensValue.filter((t) => t.toUpperCase().includes(q))
      : [...this.tokensValue]
    this.renderList()
    this.highlightedIndex = -1
    this.listboxTarget.hidden = this.filteredTokens.length === 0
    this.inputTarget.setAttribute("aria-expanded", this.filteredTokens.length > 0 ? "true" : "false")
  }

  renderList() {
    const listbox = this.listboxTarget
    const id = listbox.id || "spot-token-listbox"
    listbox.innerHTML = this.filteredTokens
      .map(
        (token, i) =>
          `<li role="option" id="${id}-${i}" data-value="${this.escapeAttr(token)}" class="cursor-pointer px-3 py-2 text-sm hover:bg-slate-100">${this.escapeHtml(token)}</li>`
      )
      .join("")
    this.listboxTarget.hidden = this.filteredTokens.length === 0
  }

  escapeAttr(s) {
    const div = document.createElement("div")
    div.textContent = s
    return div.innerHTML.replace(/"/g, "&quot;")
  }

  escapeHtml(s) {
    const div = document.createElement("div")
    div.textContent = s
    return div.innerHTML
  }

  keydown(event) {
    if (!this.hasListboxTarget) return
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.highlightedIndex = Math.min(this.highlightedIndex + 1, this.filteredTokens.length - 1)
        this.syncHighlight()
        break
      case "ArrowUp":
        event.preventDefault()
        this.highlightedIndex = Math.max(this.highlightedIndex - 1, -1)
        this.syncHighlight()
        break
      case "Enter":
        if (this.highlightedIndex >= 0 && this.filteredTokens[this.highlightedIndex]) {
          event.preventDefault()
          this.selectToken(this.filteredTokens[this.highlightedIndex])
        }
        break
      case "Escape":
        this.listboxTarget.hidden = true
        this.inputTarget.setAttribute("aria-expanded", "false")
        this.highlightedIndex = -1
        break
    }
  }

  syncHighlight() {
    const options = this.listboxTarget.querySelectorAll("[role='option']")
    options.forEach((el, i) => {
      el.classList.toggle("bg-slate-100", i === this.highlightedIndex)
      el.setAttribute("aria-selected", i === this.highlightedIndex ? "true" : "false")
      if (i === this.highlightedIndex) this.inputTarget.setAttribute("aria-activedescendant", el.id || "")
    })
    if (this.highlightedIndex < 0) this.inputTarget.removeAttribute("aria-activedescendant")
  }

  selectToken(token) {
    this.inputTarget.value = token
    this.listboxTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
    this.highlightedIndex = -1
  }

  selectOption(event) {
    const option = event.target.closest("[role='option']")
    if (option) this.selectToken(option.getAttribute("data-value") || option.textContent.trim())
  }
}
