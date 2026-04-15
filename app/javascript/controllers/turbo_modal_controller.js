import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "frame"]

  open() {
    if (this.hasDialogTarget) {
      this.dialogTarget.showModal()
    }
  }

  close() {
    if (this.hasDialogTarget) {
      this.dialogTarget.close()
    }
    if (this.hasFrameTarget) {
      this.frameTarget.innerHTML = ""
    }
  }
}
