import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

export default class extends Controller {
  static targets = ["canvas", "empty"]
  static values = { series: Array }

  connect() {
    const series = this.seriesValue || []
    if (series.length === 0) {
      if (this.hasEmptyTarget) this.emptyTarget.classList.remove("hidden")
      return
    }
    const labels = series.map((d) => d.date)
    const values = series.map((d) => d.value)
    if (this.hasCanvasTarget) this.renderChart(labels, values)
  }

  disconnect() {
    if (this.chart) this.chart.destroy()
  }

  renderChart(labels, values) {
    const ctx = this.canvasTarget.getContext("2d")
    this.chart = new Chart(ctx, {
      type: "line",
      data: {
        labels,
        datasets: [{
          label: "Cost basis",
          data: values,
          borderColor: "rgb(15 23 42)",
          backgroundColor: "rgba(15 23 42, 0.1)",
          fill: true,
          tension: 0.2
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          x: { type: "category" },
          y: { beginAtZero: true }
        }
      }
    })
  }
}
