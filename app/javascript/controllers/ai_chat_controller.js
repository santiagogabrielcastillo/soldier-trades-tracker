import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { chatUrl: String }
  static targets = ["panel", "input", "messages", "submit", "trigger"]

  toggle() {
    this.panelTarget.classList.toggle("hidden")
    const isOpen = !this.panelTarget.classList.contains("hidden")
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", String(isOpen))
    }
    if (isOpen) {
      this.inputTarget.focus()
    } else if (this.hasTriggerTarget) {
      this.triggerTarget.focus()
    }
  }

  handleKeydown(event) {
    if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
      this.sendMessage()
    }
  }

  async sendMessage() {
    const userMessage = this.inputTarget.value.trim()
    if (!userMessage) return

    this._appendUserMessage(userMessage)
    this.inputTarget.value = ""
    this.submitTarget.disabled = true

    const loadingEl = this._appendLoading()

    try {
      const response = await fetch(this.chatUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: JSON.stringify({ message: userMessage })
      })

      const data = await response.json()

      if (response.ok) {
        this._replaceLoading(loadingEl, this._aiResponseHTML(data.response))
      } else {
        let errorText
        if (data.error === "no_api_key") {
          errorText = "Please add your Gemini API key in Settings."
        } else {
          errorText = data.message || "Something went wrong. Please try again."
        }
        this._replaceLoading(loadingEl, this._errorHTML(errorText))
      }
    } catch (_error) {
      this._replaceLoading(loadingEl, this._errorHTML("Something went wrong. Please try again."))
    } finally {
      this.submitTarget.disabled = false
    }
  }

  _appendUserMessage(text) {
    const div = document.createElement("div")
    div.innerHTML = `
      <div class="flex justify-end mb-2">
        <div class="bg-slate-700 text-white text-sm rounded-lg px-3 py-2 max-w-[80%]">${this._escapeHtml(text)}</div>
      </div>
    `
    this.messagesTarget.appendChild(div.firstElementChild)
    this._scrollToBottom()
  }

  _appendLoading() {
    const div = document.createElement("div")
    div.innerHTML = `
      <div class="flex justify-start mb-2" data-loading>
        <div class="bg-white border border-slate-200 text-slate-500 text-sm rounded-lg px-3 py-2 italic">AI is thinking...</div>
      </div>
    `
    const el = div.firstElementChild
    this.messagesTarget.appendChild(el)
    this._scrollToBottom()
    return el
  }

  _replaceLoading(loadingEl, html) {
    const div = document.createElement("div")
    div.innerHTML = html
    loadingEl.replaceWith(div.firstElementChild)
    this._scrollToBottom()
  }

  _aiResponseHTML(text) {
    return `
      <div class="flex justify-start mb-2">
        <div class="bg-white border border-slate-200 text-slate-800 text-sm rounded-lg px-3 py-2 max-w-[80%] whitespace-pre-wrap">${this._escapeHtml(text)}</div>
      </div>
    `
  }

  _errorHTML(text) {
    return `
      <div class="flex justify-start mb-2">
        <div class="bg-red-50 border border-red-200 text-red-700 text-sm rounded-lg px-3 py-2 max-w-[80%]">${this._escapeHtml(text)}</div>
      </div>
    `
  }

  _scrollToBottom() {
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }

  _escapeHtml(text) {
    const div = document.createElement("div")
    div.appendChild(document.createTextNode(text))
    return div.innerHTML
  }
}
