import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog"]
  static values = { openOnConnect: { type: Boolean, default: false } }

  connect() {
    if (this.openOnConnectValue) this.open()
  }

  open() {
    if (this.hasDialogTarget) {
      this.dialogTarget.showModal()
    }
  }

  close() {
    if (this.hasDialogTarget) {
      this.dialogTarget.close()
    }
  }
};
