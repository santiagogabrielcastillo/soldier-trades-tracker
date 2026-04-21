import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

const PALETTE = [
  "#6366f1", "#f59e0b", "#10b981", "#3b82f6", "#ef4444",
  "#8b5cf6", "#ec4899", "#14b8a6", "#f97316", "#84cc16",
  "#06b6d4", "#a855f7", "#fb7185", "#34d399", "#fbbf24"
]

export default class extends Controller {
  static targets = ["pieCanvas", "pieEmpty"]
  static values = { pie: Array }

  connect() {
    const pie = this.pieValue || []

    if (pie.length > 0 && this.hasPieCanvasTarget) {
      this.renderPie(pie)
    } else if (this.hasPieEmptyTarget) {
      this.pieEmptyTarget.classList.remove("hidden")
    }
  }

  disconnect() {
    if (this.pieChart) this.pieChart.destroy()
  }

  renderPie(pie) {
    const ctx = this.pieCanvasTarget.getContext("2d")
    this.pieChart = new Chart(ctx, {
      type: "doughnut",
      data: {
        labels: pie.map((d) => d.token),
        datasets: [{
          data: pie.map((d) => d.pct),
          backgroundColor: pie.map((_, i) => PALETTE[i % PALETTE.length]),
          borderWidth: 1,
          borderColor: "#fff"
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { position: "right", labels: { boxWidth: 12, font: { size: 11 } } },
          tooltip: {
            callbacks: {
              label: (ctx) => ` ${ctx.label}: ${ctx.parsed.toFixed(1)}%`
            }
          }
        }
      }
    })
  }
};
