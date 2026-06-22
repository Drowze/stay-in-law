import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { end: String }

  connect() {
    this.endAt = new Date(this.endValue)
    this.tick()
    this.interval = window.setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    if (this.interval) window.clearInterval(this.interval)
  }

  tick() {
    const remaining = Math.max(0, Math.floor((this.endAt - Date.now()) / 1000))

    if (remaining <= 0) {
      this.element.textContent = "00:00:00"
      if (this.interval) window.clearInterval(this.interval)
      return
    }

    const h = Math.floor(remaining / 3600)
    const m = Math.floor((remaining % 3600) / 60)
    const s = remaining % 60

    this.element.textContent = `${this.pad(h)}:${this.pad(m)}:${this.pad(s)}`
  }

  pad(value) {
    return String(value).padStart(2, "0")
  }
}
