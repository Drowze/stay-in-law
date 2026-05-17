import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.querySelectorAll(".is-auto-dismiss").forEach((notice) => {
      window.setTimeout(() => {
        notice.classList.add("is-fading")
        window.setTimeout(() => notice.remove(), 500)
      }, 4000)
    })
  }
}
