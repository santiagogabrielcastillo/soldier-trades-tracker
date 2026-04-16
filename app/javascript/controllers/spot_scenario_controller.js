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
  _renderSliderRows() { /* implemented in Task 4 */ }
  _updateBudgetBar() { /* implemented in Task 4 */ }
  runOptimizer() { /* implemented in Tasks 5–6 */ }
}
