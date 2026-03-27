import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { data: Object }
  static targets = ["pie", "bar"]

  connect() {
    if (this.hasPieTarget) this.#buildPie()
    if (this.hasBarTarget) this.#buildBar()
  }

  disconnect() {
    this.#pieChart?.destroy()
    this.#barChart?.destroy()
  }

  #buildPie() {
    const { Chart } = window
    if (!Chart) return
    const { buckets } = this.dataValue
    if (!buckets?.length) return

    this.#pieChart = new Chart(this.pieTarget, {
      type: "doughnut",
      data: {
        labels: buckets.map(b => b.name),
        datasets: [{ data: buckets.map(b => b.actual_usd), backgroundColor: buckets.map(b => b.color), borderWidth: 2, borderColor: "#fff" }]
      },
      options: {
        responsive: true, maintainAspectRatio: false, cutout: "65%",
        plugins: { legend: { position: "right", labels: { boxWidth: 12, padding: 16, font: { size: 12 } } } }
      }
    })
  }

  #buildBar() {
    const { Chart } = window
    if (!Chart) return
    const { buckets } = this.dataValue
    const withTargets = (buckets || []).filter(b => b.target_pct != null)
    if (!withTargets.length) return

    this.#barChart = new Chart(this.barTarget, {
      type: "bar",
      data: {
        labels: withTargets.map(b => b.name),
        datasets: [
          { label: "Actual %",  data: withTargets.map(b => b.actual_pct),  backgroundColor: withTargets.map(b => b.color), borderRadius: 4 },
          { label: "Target %",  data: withTargets.map(b => b.target_pct), backgroundColor: withTargets.map(b => b.color + "55"), borderRadius: 4, borderDash: [4,2] }
        ]
      },
      options: {
        responsive: true, maintainAspectRatio: false,
        plugins: { legend: { labels: { boxWidth: 12, padding: 12, font: { size: 12 } } } },
        scales: { y: { beginAtZero: true, max: 100, ticks: { callback: v => v + "%" } } }
      }
    })
  }
}
