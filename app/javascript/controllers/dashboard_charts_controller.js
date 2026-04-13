import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

export default class extends Controller {
  static targets = ["balanceCanvas", "balanceEmpty", "plCanvas", "plEmpty"]
  static values = { value: String }

  connect() {
    let data
    try {
      data = JSON.parse(this.valueValue || "{}")
    } catch (e) {
      console.warn("Dashboard charts: invalid data", e)
      data = { balance_series: [], cumulative_pl_series: [] }
    }
    const balanceSeries = data.balance_series || []
    const cumulativePlSeries = data.cumulative_pl_series || []

    const labels = (balanceSeries.length ? balanceSeries : cumulativePlSeries).map((d) => d.date)

    if (balanceSeries.length) {
      this.renderBalanceChart(labels, balanceSeries.map((d) => d.value))
    } else {
      this.showEmpty("balanceCanvas", "balanceEmpty")
    }

    if (cumulativePlSeries.length) {
      this.renderPlChart(labels, cumulativePlSeries.map((d) => d.value))
    } else {
      this.showEmpty("plCanvas", "plEmpty")
    }
  }

  disconnect() {
    if (this.balanceChart) this.balanceChart.destroy()
    if (this.plChart) this.plChart.destroy()
  }

  // Hide the canvas and reveal the empty state. Using style.display avoids
  // any Tailwind class ordering conflicts between `hidden` and `flex`.
  showEmpty(canvasTargetName, emptyTargetName) {
    const hasCanvas = `has${canvasTargetName.charAt(0).toUpperCase() + canvasTargetName.slice(1)}Target`
    const hasEmpty  = `has${emptyTargetName.charAt(0).toUpperCase() + emptyTargetName.slice(1)}Target`
    const canvasKey = `${canvasTargetName}Target`
    const emptyKey  = `${emptyTargetName}Target`

    if (this[hasCanvas]) this[canvasKey].style.display = "none"
    if (this[hasEmpty])  this[emptyKey].style.display  = "flex"
  }

  chartOptions(yBeginAtZero) {
    return {
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        x: { type: "category" },
        y: { beginAtZero: yBeginAtZero }
      }
    }
  }

  renderBalanceChart(labels, values) {
    if (!this.hasBalanceCanvasTarget) return
    const ctx = this.balanceCanvasTarget.getContext("2d")
    this.balanceChart = new Chart(ctx, {
      type: "line",
      data: {
        labels,
        datasets: [{
          label: "Balance",
          data: values,
          borderColor: "rgb(15 23 42)",
          backgroundColor: "rgba(15, 23, 42, 0.1)",
          fill: true,
          tension: 0.2
        }]
      },
      options: this.chartOptions(false)
    })
  }

  renderPlChart(labels, values) {
    if (!this.hasPlCanvasTarget) return
    const ctx = this.plCanvasTarget.getContext("2d")
    const color = values.length && values[values.length - 1] >= 0 ? "rgb(5 150 105)" : "rgb(220 38 38)"
    this.plChart = new Chart(ctx, {
      type: "line",
      data: {
        labels,
        datasets: [{
          label: "Cumulative P&L",
          data: values,
          borderColor: color,
          backgroundColor: color.replace(/^rgb\((\d+)\s+(\d+)\s+(\d+)\)$/, "rgba($1, $2, $3, 0.1)"),
          fill: true,
          tension: 0.2
        }]
      },
      options: this.chartOptions(true)
    })
  }
}
