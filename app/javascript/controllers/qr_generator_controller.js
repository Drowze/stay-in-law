import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "error", "submitButton", "results", "grid"]
  static values = { url: String }

  async submit(event) {
    event.preventDefault()

    this.submitButtonTarget.textContent = "Gerando…"
    this.submitButtonTarget.disabled = true
    this.errorTarget.classList.add("is-hidden")

    const csrf = document.querySelector("meta[name='csrf-token']")?.content

    try {
      const body = new URLSearchParams(new FormData(this.formTarget))
      const response = await fetch(this.urlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": csrf
        },
        body: body.toString()
      })

      if (response.status === 401) {
        window.location.reload()
        return
      }

      const payload = await response.json()

      if (!response.ok) {
        this.errorTarget.textContent = payload.error || "Erro desconhecido."
        this.errorTarget.classList.remove("is-hidden")
        return
      }

      this.renderQRCodes(payload)
    } catch (_error) {
      this.errorTarget.textContent = "Erro de rede. Tente novamente."
      this.errorTarget.classList.remove("is-hidden")
    } finally {
      this.submitButtonTarget.textContent = "Gerar QR Codes"
      this.submitButtonTarget.disabled = false
    }
  }

  renderQRCodes(tokens) {
    this.gridTarget.innerHTML = ""

    tokens.forEach((tokenData) => {
      const wrapper = document.createElement("div")
      wrapper.className = "card qr-card"
      wrapper.dataset.minutes = tokenData.minutes

      const qrDiv = document.createElement("div")
      qrDiv.className = "qr-image"

      const info = document.createElement("p")
      info.className = "qr-info"
      const scanUrl = `${window.location.origin}/?t=${encodeURIComponent(tokenData.token)}`
      info.innerHTML = `<strong class=\"qr-info-minutes\">${tokenData.minutes} min</strong><br>${scanUrl}`

      wrapper.append(qrDiv, info)
      this.gridTarget.appendChild(wrapper)

      this.makeQRCode(qrDiv, scanUrl, tokenData.minutes, 220)
    })

    this.resultsTarget.classList.remove("is-hidden")
    this.resultsTarget.scrollIntoView({ behavior: "smooth" })
  }

  makeQRCode(element, url, minutes, size) {
    new window.QRCodeStyling({
      width: size,
      height: size,
      type: "canvas",
      data: url,
      image: this.minutesSVG(minutes),
      dotsOptions: { type: "rounded", color: "#6d28d9" },
      cornersSquareOptions: { type: "extra-rounded", color: "#ec4899" },
      cornersDotOptions: { type: "dot", color: "#ec4899" },
      backgroundOptions: { color: "#ffffff" },
      imageOptions: { crossOrigin: "anonymous", margin: 0, imageSize: 0.42 }
    }).append(element)
  }

  minutesSVG(minutes) {
    const svg = `<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"68\"><text x=\"50\" y=\"50\" text-anchor=\"middle\" font-family=\"Nunito,sans-serif\" font-weight=\"900\" font-size=\"54\" fill=\"#ec4899\">${minutes}</text></svg>`
    return `data:image/svg+xml;base64,${window.btoa(svg)}`
  }

  print() {
    const cards = this.gridTarget.querySelectorAll(".qr-card")
    if (!cards.length) return

    const items = Array.from(cards).map((card) => {
      const canvas = card.querySelector("canvas")
      return { src: canvas ? canvas.toDataURL("image/png") : "", minutes: card.dataset.minutes }
    })

    const cardCss = [
      "body{margin:0;font-family:Nunito,sans-serif;background:#fff}",
      ".grid{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;padding:8px}",
      ".card{text-align:center;border:1px solid #f3e0ec;border-radius:12px;padding:8px;break-inside:avoid}",
      ".card:nth-child(20n){break-after:always}",
      "img{width:160px;height:160px;display:block;margin:0 auto}",
      ".label{font-size:13px;font-weight:700;color:#6d28d9;margin-top:4px}",
      "@page{size:A4;margin:10mm}"
    ].join("")

    const cardsHtml = items.map((item) => `<div class=\"card\"><img src=\"${item.src}\"><p class=\"label\">${item.minutes} min</p></div>`).join("")

    const html = `<!DOCTYPE html><html><head><meta charset=\"UTF-8\"><link href=\"https://fonts.googleapis.com/css2?family=Nunito:wght@700&display=swap\" rel=\"stylesheet\"><style>${cardCss}</style></head><body><div class=\"grid\">${cardsHtml}</div><script>window.onload=function(){window.print();window.close();}<\\/script></body></html>`

    const win = window.open("", "_blank")
    if (!win) return
    win.document.write(html)
    win.document.close()
  }
}
