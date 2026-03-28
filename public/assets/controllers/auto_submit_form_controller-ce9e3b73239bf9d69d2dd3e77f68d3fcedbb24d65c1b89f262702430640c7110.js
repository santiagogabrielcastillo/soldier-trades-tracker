import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger"]

  connect() {
    this.boundSubmit = () => this.element.requestSubmit()
    this.triggerTargets.forEach((el) => el.addEventListener("change", this.boundSubmit))
  }

  disconnect() {
    this.triggerTargets.forEach((el) => el.removeEventListener("change", this.boundSubmit))
  }
};
