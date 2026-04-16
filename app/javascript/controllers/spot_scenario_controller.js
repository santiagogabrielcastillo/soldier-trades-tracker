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

  _calcNewBreakeven(pos, injection) {
    const balance = parseFloat(pos.balance)
    const netUsd = parseFloat(pos.net_usd_invested)
    const currentPrice = parseFloat(pos.current_price)
    if (!currentPrice) return null
    const newBalance = balance + injection / currentPrice
    if (!newBalance) return null
    return (netUsd + injection) / newBalance
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

  _renderCheckboxes() {
    const eligible = this.positionsValue.filter(p => p.current_price && !this._isRiskFree(p))
    this.checkboxContainerTarget.innerHTML = eligible.map(pos => `
      <label class="flex cursor-pointer items-center gap-1.5 rounded-md border border-indigo-100 bg-indigo-50 px-3 py-1.5 text-sm hover:bg-indigo-100">
        <input type="checkbox" checked
               data-token="${this._escapeAttr(pos.token)}"
               class="rounded accent-indigo-600"
               style="accent-color:#6366f1" />
        <span class="font-medium text-slate-800">${this._escapeAttr(pos.token)}</span>
      </label>
    `).join("")
  }

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

  runOptimizer() {
    const budget = this.budget
    if (budget <= 0) return

    const selectedTokens = new Set(
      [...this.checkboxContainerTarget.querySelectorAll("input[type=checkbox]:checked")]
        .map(cb => cb.dataset.token)
    )
    const allPositions = this.positionsValue.filter(p => p.current_price && !this._isRiskFree(p))
    const selected = allPositions.filter(p => selectedTokens.has(p.token))
    const unselected = allPositions.filter(p => !selectedTokens.has(p.token))

    let results
    if (this._optimizerMode === "fixed") {
      results = this._runFixedTargetOptimizer(selected, budget)
    } else {
      results = this._runBestFloorOptimizer(selected, budget)
    }

    // Merge unselected positions as $0/no-badge rows
    const unselectedResults = unselected.map(pos => ({
      pos,
      injection: 0,
      newRoi: this._calcCurrentRoi(pos),
      status: null,
      selected: false,
    }))

    this._renderOptimizeResults([...results, ...unselectedResults], budget)
  }

  _runFixedTargetOptimizer(positions, budget) {
    const targetRoi = parseFloat(this.targetRoiTarget.value) || -30

    // Compute needed injection for each; skip positions already past target
    const needs = positions.map(pos => {
      const currentRoi = this._calcCurrentRoi(pos)
      if (currentRoi !== null && currentRoi >= targetRoi) {
        return { pos, needed: 0, alreadyPast: true }
      }
      return { pos, needed: this._calcInjectionNeeded(pos, targetRoi), alreadyPast: false }
    })

    // Prioritize deepest (most needed) first
    needs.sort((a, b) => b.needed - a.needed)

    let remaining = budget
    return needs.map(({ pos, needed, alreadyPast }) => {
      if (alreadyPast) {
        return { pos, injection: 0, newRoi: this._calcCurrentRoi(pos), status: "past", selected: true }
      }
      const injection = Math.min(needed, remaining)
      remaining = Math.max(0, remaining - injection)
      const newRoi = this._calcProjectedRoi(pos, injection)
      const metTarget = needed > 0 && Math.abs(injection - needed) < 0.01
      const status = needed === 0 ? "past" : (metTarget ? "met" : "exhausted")
      return { pos, injection, newRoi, status, selected: true }
    })
  }

  _runBestFloorOptimizer(positions, budget) {
    if (positions.length === 0) return []

    // Find the worst current ROI as lower bound
    const rois = positions.map(p => this._calcCurrentRoi(p)).filter(r => r !== null)
    if (rois.length === 0) return []
    let low = Math.min(...rois, -99)
    let high = Math.max(...rois.map(r => Math.min(r, 0)), -0.01) // floor ≤ 0

    // Binary search for highest floor r* where total injection ≤ budget
    for (let i = 0; i < 60; i++) {
      const mid = (low + high) / 2
      const totalNeeded = positions.reduce((sum, pos) => {
        const currentRoi = this._calcCurrentRoi(pos)
        if (currentRoi !== null && currentRoi >= mid) return sum // already past this floor
        return sum + this._calcInjectionNeeded(pos, mid)
      }, 0)

      if (totalNeeded <= budget) {
        low = mid // achievable, try a better floor
      } else {
        high = mid // too expensive, lower the floor
      }

      if (high - low < 0.01) break // converged
    }

    const floorRoi = low
    // Allocate exactly, respecting budget
    let remaining = budget
    return positions.map(pos => {
      const currentRoi = this._calcCurrentRoi(pos)
      if (currentRoi !== null && currentRoi >= floorRoi) {
        return { pos, injection: 0, newRoi: currentRoi, status: "past", selected: true }
      }
      const needed = this._calcInjectionNeeded(pos, floorRoi)
      const injection = Math.min(needed, remaining)
      remaining = Math.max(0, remaining - injection)
      const newRoi = this._calcProjectedRoi(pos, injection)
      const status = injection >= needed - 0.01 ? "equalized" : "exhausted"
      return { pos, injection, newRoi, status, selected: true }
    })
  }

  _renderOptimizeResults(results, budget) {
    const totalInjected = results.reduce((s, r) => s + r.injection, 0)
    const metCount = results.filter(r => r.status === "met" || r.status === "equalized").length
    const selectedCount = results.filter(r => r.selected).length

    const badgeHtml = (status) => {
      if (!status) return ""
      const map = {
        met:       ["bg-amber-100 text-amber-700",   "Target met"],
        past:      ["bg-emerald-100 text-emerald-700","Already past target"],
        exhausted: ["bg-orange-100 text-orange-700",  "Budget exhausted"],
        equalized: ["bg-indigo-100 text-indigo-700",  "Equalized"],
      }
      const [cls, label] = map[status] || ["bg-slate-100 text-slate-500", status]
      return `<span class="rounded-full px-2 py-0.5 text-xs font-semibold ${cls}">${label}</span>`
    }

    const rows = results.map(({ pos, injection, newRoi, status, selected }) => {
      const currentRoi = this._calcCurrentRoi(pos)
      const isRiskFree = this._isRiskFree(pos)
      const rowClass = selected ? "" : "opacity-40"
      const injectStr = injection > 0 ? this._formatMoney(injection) : "$0"
      const injectClass = injection > 0 ? "font-semibold text-indigo-600" : "text-slate-400"
      const newBreakevenRaw = injection > 0 ? this._calcNewBreakeven(pos, injection) : null
      const newBreakevenStr = newBreakevenRaw != null ? this._formatMoney(newBreakevenRaw) : "—"
      const newRoiStr = this._formatRoi(newRoi, isRiskFree)
      const newRoiClass = this._newRoiColorClass(currentRoi, newRoi, isRiskFree)

      return `
        <tr class="border-b border-slate-100 ${rowClass}">
          <td class="whitespace-nowrap px-4 py-3 font-semibold text-slate-900">${this._escapeAttr(pos.token)}</td>
          <td class="whitespace-nowrap px-4 py-3 text-right font-semibold ${this._roiColorClass(currentRoi, isRiskFree)}">${this._formatRoi(currentRoi, isRiskFree)}</td>
          <td class="whitespace-nowrap px-4 py-3 text-right ${injectClass}">${injectStr}</td>
          <td class="whitespace-nowrap px-4 py-3 text-right text-slate-600">${newBreakevenStr}</td>
          <td class="whitespace-nowrap px-4 py-3 text-right font-semibold ${newRoiClass}">${newRoiStr}</td>
          <td class="whitespace-nowrap px-4 py-3 text-right">${badgeHtml(status)}</td>
        </tr>
      `
    }).join("")

    this.optimizeResultsTarget.innerHTML = `
      <div class="overflow-hidden rounded-lg border border-indigo-100 bg-white">
        <div class="border-b border-indigo-100 bg-indigo-50/60 px-4 py-2 text-xs font-semibold text-indigo-600">
          Result — ${this._optimizerMode === "fixed"
            ? `Fixed target ${this.targetRoiTarget.value}%`
            : "Best achievable floor"} · Budget ${this._formatMoney(budget)} · ${selectedCount} position${selectedCount !== 1 ? "s" : ""} selected
        </div>
        <table class="w-full border-collapse text-sm">
          <thead>
            <tr class="border-b border-indigo-100 bg-indigo-50/30">
              <th class="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-indigo-500">Token</th>
              <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-indigo-500">Current ROI</th>
              <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-indigo-500">Inject $</th>
              <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-indigo-500">New breakeven</th>
              <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-indigo-500">New ROI</th>
              <th class="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wide text-indigo-500">Status</th>
            </tr>
          </thead>
          <tbody>${rows}</tbody>
        </table>
        <div class="flex items-center gap-3 border-t border-indigo-100 bg-indigo-50/60 px-4 py-2.5 text-xs">
          <span class="font-semibold text-indigo-600">Total injected: ${this._formatMoney(totalInjected)}</span>
          <span class="text-slate-400">·</span>
          <span class="text-slate-500">${metCount} of ${selectedCount} position${selectedCount !== 1 ? "s" : ""} reached target</span>
        </div>
      </div>
    `
  }
}
