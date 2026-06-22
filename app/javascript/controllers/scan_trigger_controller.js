import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  connect() {
    const params = new URLSearchParams(window.location.search)
    const token = params.get("t")
    if (!token) return

    const csrf = document.querySelector("meta[name='csrf-token']")?.content

    fetch(this.urlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "X-CSRF-Token": csrf
      },
      body: `token=${encodeURIComponent(token)}`
    })
      .then(async (res) => {
        if (res.status === 401) {
          window.location.reload()
          return
        }

        const data = await res.json()

        if (res.status === 201) {
          const notice = data.outlaw_card ? "success_debt_paid" : "success_time_added"
          window.location.href = `/?notice=${notice}`
          return
        }

        if (res.status === 422) {
          const notice = data.code === "token_already_used" ? "failure_token_already_used" : "failure_countdown_active"
          window.location.href = `/?notice=${notice}`
          return
        }

        window.location.href = "/?notice=failure_bad_scan"
      })
      .catch(() => {
        window.location.href = "/?notice=failure_bad_scan"
      })
  }
}
