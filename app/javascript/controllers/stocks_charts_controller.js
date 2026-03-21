import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

const PALETTE = [
  "#6366f1", "#f59e0b", "#10b981", "#3b82f6", "#ef4444",
  "#8b5cf6", "#ec4899", "#14b8a6", "#f97316", "#84cc16",
  "#06b6d4", "#a855f7", "#fb7185", "#34d399", "#fbbf24"
]

export default class extends Controller {
  static targets = ["pieCanvas", "pieEmpty", "barCanvas", "barEmpty", "twrCanvas", "twrEmpty"]
  static values = { data: Object }

  connect() {
    const data = this.dataValue || {}
    const pie = data.pie || []
    const bar = data.bar || []
    const twr = data.twr || []

    if (pie.length > 0 && this.hasPieCanvasTarget) {
      this.renderPie(pie)
    } else if (this.hasPieEmptyTarget) {
      this.pieEmptyTarget.classList.remove("hidden")
    }

    if (bar.length > 0 && this.hasBarCanvasTarget) {
      this.renderBar(bar)
    } else if (this.hasBarEmptyTarget) {
      this.barEmptyTarget.classList.remove("hidden")
    }

    if (twr.length > 0 && this.hasTwrCanvasTarget) {
      this.renderTwr(twr)
    } else if (this.hasTwrEmptyTarget) {
      this.twrEmptyTarget.classList.remove("hidden")
    }
  }

  disconnect() {
    if (this.pieChart) this.pieChart.destroy()
    if (this.barChart) this.barChart.destroy()
    if (this.twrChart) this.twrChart.destroy()
  }

  renderPie(pie) {
    const ctx = this.pieCanvasTarget.getContext("2d")
    this.pieChart = new Chart(ctx, {
      type: "doughnut",
      data: {
        labels: pie.map((d) => d.ticker),
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

  renderTwr(twr) {
    const ctx = this.twrCanvasTarget.getContext("2d")
    const lastVal = twr[twr.length - 1]?.twr_pct ?? 0
    const color = lastVal >= 0 ? "rgb(5, 150, 105)" : "rgb(220, 38, 38)"
    this.twrChart = new Chart(ctx, {
      type: "line",
      data: {
        labels: twr.map((d) => d.date),
        datasets: [{
          label: "TWR",
          data: twr.map((d) => d.twr_pct),
          borderColor: color,
          backgroundColor: color.replace("rgb", "rgba").replace(")", ", 0.08)"),
          fill: true,
          tension: 0.2,
          pointRadius: 3
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: { callbacks: { label: (ctx) => ` ${ctx.parsed.y.toFixed(2)}%` } }
        },
        scales: {
          x: { type: "category" },
          y: { ticks: { callback: (v) => `${v}%` } }
        }
      }
    })
  }

  renderBar(bar) {
    const ctx = this.barCanvasTarget.getContext("2d")
    this.barChart = new Chart(ctx, {
      type: "bar",
      data: {
        labels: bar.map((d) => d.ticker),
        datasets: [{
          label: "Unrealized P&L",
          data: bar.map((d) => d.pct),
          backgroundColor: bar.map((d) => d.pct >= 0 ? "rgba(5, 150, 105, 0.7)" : "rgba(220, 38, 38, 0.7)"),
          borderColor: bar.map((d) => d.pct >= 0 ? "rgb(5, 150, 105)" : "rgb(220, 38, 38)"),
          borderWidth: 1
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: (ctx) => ` ${ctx.parsed.y.toFixed(2)}%`
            }
          }
        },
        scales: {
          y: {
            beginAtZero: true,
            ticks: { callback: (v) => `${v}%` }
          }
        }
      }
    })
  }
}
