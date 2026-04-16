// app/javascript/controllers/spot_scenario_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    positions: Array,      // [{token, balance, net_usd_invested, breakeven, current_price}]
    cashBalance: Number,
    spotValue: Number,
    totalPortfolio: Number,
  }

  static targets = [
    "panel", "toggleIcon",
    "targetCashPct", "budgetAmount", "afterInvestSummary",
    "manualTab", "optimizeTab", "manualContent", "optimizeContent",
    "sliderBody", "budgetBar", "budgetAllocated", "budgetRemaining",
    "optimizerModeFixed", "optimizerModeFloor", "targetRoiWrapper",
    "targetRoi", "checkboxContainer", "optimizeBtn", "optimizeResults",
  ]

  connect() {
    this._open = false
    this._activeTab = "manual"
    this._optimizerMode = "fixed"
    this._sliderValues = {} // token -> allocated amount
  }

  // ── Panel toggle ──────────────────────────────────────────────

  toggle() {
    this._open = !this._open
    this.panelTarget.classList.toggle("hidden", !this._open)
    this.toggleIconTarget.textContent = this._open ? "▼" : "▶"
    if (this._open) this._initPanel()
  }

  _initPanel() {
    const currentPct = this.totalPortfolioValue > 0
      ? (this.cashBalanceValue / this.totalPortfolioValue * 100)
      : 0
    this.targetCashPctTarget.value = currentPct.toFixed(1)
    this.budgetAmountTarget.value = "0.00"
    this._updateAfterInvestSummary(0)
    this._activateTab("manual")
    this._initOptimizerMode("fixed")
    this._resetSliders()
    this._renderCheckboxes()
  }

  // ── Budget inputs ─────────────────────────────────────────────

  onTargetCashPctInput() {
    const pct = parseFloat(this.targetCashPctTarget.value) || 0
    const budget = Math.max(0, this.cashBalanceValue - (pct / 100) * this.totalPortfolioValue)
    this.budgetAmountTarget.value = budget.toFixed(2)
    this._updateAfterInvestSummary(budget)
    this._resetSliders()
  }

  onBudgetAmountInput() {
    const budget = Math.max(0, parseFloat(this.budgetAmountTarget.value) || 0)
    const newCash = this.cashBalanceValue - budget
    const newPct = this.totalPortfolioValue > 0 ? (newCash / this.totalPortfolioValue * 100) : 0
    this.targetCashPctTarget.value = Math.max(0, newPct).toFixed(1)
    this._updateAfterInvestSummary(budget)
    this._resetSliders()
  }

  _updateAfterInvestSummary(budget) {
    const newCash = this.cashBalanceValue - budget
    const newPct = this.totalPortfolioValue > 0 ? (newCash / this.totalPortfolioValue * 100) : 0
    this.afterInvestSummaryTarget.textContent =
      `After invest: cash = ${this._formatMoney(Math.max(0, newCash))} (${Math.max(0, newPct).toFixed(1)}%)`
  }

  get budget() {
    return Math.max(0, parseFloat(this.budgetAmountTarget.value) || 0)
  }

  // ── Tab switching ─────────────────────────────────────────────

  switchToManual() { this._activateTab("manual") }
  switchToOptimize() { this._activateTab("optimize") }

  _activateTab(tab) {
    this._activeTab = tab
    const isManual = tab === "manual"
    this.manualContentTarget.classList.toggle("hidden", !isManual)
    this.optimizeContentTarget.classList.toggle("hidden", isManual)
    this.manualTabTarget.classList.toggle("bg-indigo-600", isManual)
    this.manualTabTarget.classList.toggle("text-white", isManual)
    this.manualTabTarget.classList.toggle("text-indigo-600", !isManual)
    this.optimizeTabTarget.classList.toggle("bg-indigo-600", !isManual)
    this.optimizeTabTarget.classList.toggle("text-white", !isManual)
    this.optimizeTabTarget.classList.toggle("text-indigo-600", isManual)
    if (isManual) this._renderSliderRows()
  }

  // ── Optimizer mode toggle ─────────────────────────────────────

  setModeFixed() { this._initOptimizerMode("fixed") }
  setModeFloor() { this._initOptimizerMode("floor") }

  _initOptimizerMode(mode) {
    this._optimizerMode = mode
    const isFixed = mode === "fixed"
    this.targetRoiWrapperTarget.classList.toggle("hidden", !isFixed)
    this.optimizerModeFixedTarget.classList.toggle("bg-indigo-600", isFixed)
    this.optimizerModeFixedTarget.classList.toggle("text-white", isFixed)
    this.optimizerModeFixedTarget.classList.toggle("text-indigo-600", !isFixed)
    this.optimizerModeFloorTarget.classList.toggle("bg-indigo-600", !isFixed)
    this.optimizerModeFloorTarget.classList.toggle("text-white", !isFixed)
    this.optimizerModeFloorTarget.classList.toggle("text-indigo-600", isFixed)
    this.optimizeResultsTarget.innerHTML = "" // clear stale results
  }

  // ── Helpers ───────────────────────────────────────────────────

  _formatMoney(value) {
    if (value == null || isNaN(value)) return "—"
    return "$" + parseFloat(value).toLocaleString("en-US", {
      minimumFractionDigits: 2, maximumFractionDigits: 2,
    })
  }

  _formatRoi(roi, isRiskFree) {
    if (isRiskFree) return "Risk free"
    if (roi == null || !isFinite(roi)) return "—"
    return (roi >= 0 ? "+" : "") + roi.toFixed(2) + "%"
  }

  _roiColorClass(roi, isRiskFree) {
    if (isRiskFree) return "text-emerald-600"
    if (roi == null || !isFinite(roi)) return "text-slate-400"
    if (roi >= 0) return "text-emerald-600"
    return "text-red-600"
  }

  _newRoiColorClass(currentRoi, newRoi, isRiskFree) {
    if (isRiskFree) return "text-emerald-600"
    if (newRoi == null || !isFinite(newRoi)) return "text-slate-400"
    if (newRoi >= 0) return "text-emerald-600"
    if (newRoi > (currentRoi || newRoi)) return "text-amber-600" // improved but still negative
    return "text-red-600"
  }

  _escapeAttr(s) {
    return String(s).replace(/&/g, "&amp;").replace(/"/g, "&quot;")
  }

  _calcCurrentRoi(pos) {
    const breakeven = parseFloat(pos.breakeven)
    const currentPrice = parseFloat(pos.current_price)
    if (!breakeven || !currentPrice) return null
    return (currentPrice - breakeven) / breakeven * 100
  }

  _isRiskFree(pos) {
    return parseFloat(pos.net_usd_invested) < 0
  }

  _calcProjectedRoi(pos, injection) {
    const balance = parseFloat(pos.balance)
    const netUsd = parseFloat(pos.net_usd_invested)
    const currentPrice = parseFloat(pos.current_price)
    if (!currentPrice || !balance) return null
    const newBalance = balance + injection / currentPrice
    const newBreakeven = (netUsd + injection) / newBalance
    if (newBreakeven <= 0) return Infinity
    return (currentPrice - newBreakeven) / newBreakeven * 100
  }

  // Injection in $ needed to bring pos to targetRoiPct. Returns 0 if already there/past.
  _calcInjectionNeeded(pos, targetRoiPct) {
    const balance = parseFloat(pos.balance)
    const netUsd = parseFloat(pos.net_usd_invested)
    const currentPrice = parseFloat(pos.current_price)
    if (!currentPrice) return 0
    const targetBreakeven = currentPrice / (1 + targetRoiPct / 100)
    const denominator = 1 - targetBreakeven / currentPrice
    if (Math.abs(denominator) < 1e-10) return 0
    return Math.max(0, (targetBreakeven * balance - netUsd) / denominator)
  }

  _resetSliders() {
    this.positionsValue.forEach(p => { this._sliderValues[p.token] = 0 })
    if (this._activeTab === "manual") this._renderSliderRows()
    this._updateBudgetBar()
  }

  _renderCheckboxes() { /* implemented in Task 5 */ }

  _renderSliderRows() {
    const budget = this.budget
    const positions = this.positionsValue

    this.sliderBodyTarget.innerHTML = positions.map(pos => {
      const currentRoi = this._calcCurrentRoi(pos)
      const isRiskFree = this._isRiskFree(pos)
      const hasPrice = !!pos.current_price
      const disabled = !hasPrice || isRiskFree || budget <= 0
      const injection = this._sliderValues[pos.token] || 0
      const newRoi = disabled ? currentRoi : this._calcProjectedRoi(pos, injection)

      const currentRoiStr = this._formatRoi(currentRoi, isRiskFree)
      const currentRoiClass = this._roiColorClass(currentRoi, isRiskFree)
      const newRoiStr = this._formatRoi(newRoi, isRiskFree)
      const newRoiClass = this._newRoiColorClass(currentRoi, newRoi, isRiskFree)
      const injectStr = injection > 0 ? this._formatMoney(injection) : "$0"
      const injectClass = injection > 0 ? "font-semibold text-indigo-600" : "text-slate-400"
      const tooltip = !hasPrice ? "Sync prices first" : (isRiskFree ? "Risk-free position" : "")
      const rowClass = disabled ? "opacity-50" : ""

      return `
        <tr class="border-b border-slate-100 ${rowClass}" data-token="${this._escapeAttr(pos.token)}">
          <td class="whitespace-nowrap px-4 py-3 font-semibold text-slate-900">${this._escapeAttr(pos.token)}</td>
          <td class="whitespace-nowrap px-4 py-3 text-right text-slate-600">${pos.breakeven ? this._formatMoney(parseFloat(pos.breakeven)) : "—"}</td>
          <td class="whitespace-nowrap px-4 py-3 text-right font-semibold ${currentRoiClass}">${currentRoiStr}</td>
          <td class="px-6 py-3">
            <input
              type="range" min="0" max="${budget}" step="1" value="${injection}"
              ${disabled ? 'disabled title="' + this._escapeAttr(tooltip) + '"' : ''}
              data-action="input->spot-scenario#onSliderInput"
              data-token="${this._escapeAttr(pos.token)}"
              class="w-full disabled:cursor-not-allowed"
              style="accent-color:#6366f1"
            />
          </td>
          <td class="whitespace-nowrap px-4 py-3 text-right text-sm ${injectClass}"
              data-inject-amount="${this._escapeAttr(pos.token)}">${injectStr}</td>
          <td class="whitespace-nowrap px-4 py-3 text-right font-semibold ${newRoiClass}"
              data-new-roi="${this._escapeAttr(pos.token)}">${newRoiStr}</td>
        </tr>
      `
    }).join("")

    this._updateBudgetBar()
  }

  onSliderInput(event) {
    const token = event.target.dataset.token
    const requested = parseFloat(event.target.value) || 0
    const budget = this.budget

    // Clamp: this slider can only use what's left after other sliders
    const otherSum = Object.entries(this._sliderValues)
      .filter(([t]) => t !== token)
      .reduce((sum, [, v]) => sum + v, 0)
    const maxForThis = Math.max(0, budget - otherSum)
    const clamped = Math.min(requested, maxForThis)
    event.target.value = clamped
    this._sliderValues[token] = clamped

    // Update inject $ cell
    const injectCell = this.sliderBodyTarget.querySelector(`[data-inject-amount="${token}"]`)
    if (injectCell) {
      injectCell.textContent = clamped > 0 ? this._formatMoney(clamped) : "$0"
      injectCell.className = `whitespace-nowrap px-4 py-3 text-right text-sm ${clamped > 0 ? "font-semibold text-indigo-600" : "text-slate-400"}`
    }

    // Update new ROI cell
    const pos = this.positionsValue.find(p => p.token === token)
    if (pos) {
      const currentRoi = this._calcCurrentRoi(pos)
      const isRiskFree = this._isRiskFree(pos)
      const newRoi = this._calcProjectedRoi(pos, clamped)
      const roiCell = this.sliderBodyTarget.querySelector(`[data-new-roi="${token}"]`)
      if (roiCell) {
        roiCell.textContent = this._formatRoi(newRoi, isRiskFree)
        roiCell.className = `whitespace-nowrap px-4 py-3 text-right font-semibold ${this._newRoiColorClass(currentRoi, newRoi, isRiskFree)}`
      }
    }

    this._updateBudgetBar()
  }

  _updateBudgetBar() {
    const budget = this.budget
    const allocated = Object.values(this._sliderValues).reduce((s, v) => s + v, 0)
    const remaining = Math.max(0, budget - allocated)
    const pct = budget > 0 ? Math.min(100, (allocated / budget) * 100) : 0

    this.budgetBarTarget.style.width = pct + "%"
    this.budgetAllocatedTarget.textContent = `Allocated: ${this._formatMoney(allocated)}`
    this.budgetRemainingTarget.textContent = `${this._formatMoney(remaining)} remaining`

    // Also disable Optimize button when no budget
    if (this.hasOptimizeBtnTarget) {
      this.optimizeBtnTarget.disabled = budget <= 0
    }
  }

  runOptimizer() { /* implemented in Tasks 5–6 */ }
}
