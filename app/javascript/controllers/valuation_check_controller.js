import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["priceInput", "fwdEpsInput", "growthInput", "tableBody", "tableWrapper", "errorMessage"]

  connect() {
    this.calculate()
  }

  calculate() {
    const price = parseFloat(this.priceInputTarget.value)
    const fwdEps = parseFloat(this.fwdEpsInputTarget.value)
    const growth = parseFloat(this.growthInputTarget.value)

    if (!price || !fwdEps || price <= 0 || fwdEps <= 0 || isNaN(growth)) {
      this.tableWrapperTarget.classList.add("hidden")
      const hasAnyInput = this.priceInputTarget.value || this.fwdEpsInputTarget.value || this.growthInputTarget.value
      this.errorMessageTarget.classList.toggle("hidden", !hasAnyInput)
      return
    }

    this.errorMessageTarget.classList.add("hidden")
    this.tableWrapperTarget.classList.remove("hidden")

    const growthRate = growth / 100
    const rows = Array.from({ length: 5 }, (_, i) => {
      const year = i + 1
      const eps = fwdEps * Math.pow(1 + growthRate, year)
      const pe = price / eps
      return { year, eps, pe }
    })

    this.tableBodyTarget.innerHTML = rows.map(({ year, eps, pe }) => `
      <tr class="border-b border-slate-100">
        <td class="py-3 pr-4 text-slate-700 font-medium">Year ${year}</td>
        <td class="py-3 pr-4 text-right text-slate-700">$${eps.toFixed(2)}</td>
        <td class="py-3 text-right font-semibold ${this._peClass(pe)} rounded px-2">${pe.toFixed(1)}x</td>
      </tr>
    `).join("")
  }

  _peClass(pe) {
    if (pe < 10) return "bg-emerald-100 text-emerald-800"
    if (pe < 15) return "bg-green-100 text-green-800"
    if (pe <= 30) return "bg-yellow-100 text-yellow-800"
    return "bg-red-100 text-red-800"
  }
}
