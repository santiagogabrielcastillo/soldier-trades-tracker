import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

const PE_COLORS = {
  gift:       { border: "#059669", bg: "rgba(5,150,105,0.15)" },
  attractive: { border: "#16a34a", bg: "rgba(22,163,74,0.15)" },
  fair:       { border: "#ca8a04", bg: "rgba(202,138,4,0.15)" },
  expensive:  { border: "#dc2626", bg: "rgba(220,38,38,0.15)" },
}

const DEFAULT_THRESHOLDS = { gift_max: 10, attractive_max: 15, fair_max: 30 }

export default class extends Controller {
  static targets = ["priceInput", "fwdEpsInput", "growthInput", "tableBody", "tableWrapper", "errorMessage", "chartCanvas"]
  static values  = { price: Number, fwdEps: Number, thresholds: Object }

  get _thresholds() {
    const t = this.thresholdsValue
    return (t && t.gift_max) ? t : DEFAULT_THRESHOLDS
  }

  get _referenceLines() {
    const { gift_max, attractive_max, fair_max } = this._thresholds
    return [
      { y: gift_max,       color: "#059669", label: `${gift_max}x` },
      { y: attractive_max, color: "#16a34a", label: `${attractive_max}x` },
      { y: fair_max,       color: "#dc2626", label: `${fair_max}x` },
    ]
  }

  connect() {
    this.calculate()
  }

  disconnect() {
    this._chart?.destroy()
    this._chart = null
  }

  calculate() {
    const price   = parseFloat(this.priceInputTarget.value)
    const fwdEps  = parseFloat(this.fwdEpsInputTarget.value)
    const growth  = parseFloat(this.growthInputTarget.value)

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
      const eps  = fwdEps * Math.pow(1 + growthRate, year)
      const pe   = price / eps
      return { year, eps, pe }
    })

    this.tableBodyTarget.innerHTML = rows.map(({ year, eps, pe }) => `
      <tr class="border-b border-slate-100">
        <td class="py-3 pr-4 text-slate-700 font-medium">Year ${year}</td>
        <td class="py-3 pr-4 text-right text-slate-700">$${eps.toFixed(2)}</td>
        <td class="py-3 text-right font-semibold ${this._peClass(pe)} rounded px-2">${pe.toFixed(1)}x</td>
      </tr>
    `).join("")

    this._renderChart(rows)
  }

  _renderChart(rows) {
    if (!this.hasChartCanvasTarget) return
    const ctx    = this.chartCanvasTarget.getContext("2d")
    const labels = rows.map(r => `Year ${r.year}`)
    const peData = rows.map(r => parseFloat(r.pe.toFixed(2)))

    const pointColors = rows.map(r => this._peColor(r.pe))

    const refDatasets = this._referenceLines.map(line => ({
      label:          line.label,
      data:           labels.map(() => line.y),
      borderColor:    line.color,
      borderWidth:    1,
      borderDash:     [4, 4],
      pointRadius:    0,
      tension:        0,
      fill:           false,
    }))

    const datasets = [
      {
        label:                "P/E",
        data:                 peData,
        borderColor:          "#6366f1",
        backgroundColor:      "rgba(99,102,241,0.08)",
        tension:              0.35,
        fill:                 true,
        pointBackgroundColor: pointColors,
        pointRadius:          5,
        pointHoverRadius:     7,
      },
      ...refDatasets,
    ]

    if (this._chart) {
      this._chart.data.labels           = labels
      this._chart.data.datasets         = datasets
      this._chart.update()
      return
    }

    this._chart = new Chart(ctx, {
      type: "line",
      data: { labels, datasets },
      options: {
        responsive:          true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: {
            filter: item => item.datasetIndex === 0,
            callbacks: {
              label: ctx => `P/E: ${ctx.parsed.y.toFixed(1)}x`,
            },
          },
        },
        scales: {
          x: {
            grid: { color: "rgba(0,0,0,0.04)" },
            ticks: { font: { size: 11 } },
          },
          y: {
            grid:  { color: "rgba(0,0,0,0.04)" },
            ticks: { font: { size: 11 }, callback: v => `${v}x` },
            title: { display: false },
          },
        },
      },
    })
  }

  _peClass(pe) {
    const { gift_max, attractive_max, fair_max } = this._thresholds
    if (pe < gift_max)       return "bg-emerald-100 text-emerald-800"
    if (pe < attractive_max) return "bg-green-100 text-green-800"
    if (pe <= fair_max)      return "bg-yellow-100 text-yellow-800"
    return "bg-red-100 text-red-800"
  }

  _peColor(pe) {
    const { gift_max, attractive_max, fair_max } = this._thresholds
    if (pe < gift_max)       return PE_COLORS.gift.border
    if (pe < attractive_max) return PE_COLORS.attractive.border
    if (pe <= fair_max)      return PE_COLORS.fair.border
    return PE_COLORS.expensive.border
  }
}
