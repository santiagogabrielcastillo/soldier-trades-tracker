# Sector-Specific Adjustments

Consult this file when analyzing companies in non-standard sectors where the default framework needs modification.

---

## Financials (banks, insurance, asset managers)

**Why the standard framework breaks:**
Banks are leveraged by design — Net Debt / EBITDA is meaningless because their "debt" is their raw material (deposits). EBITDA itself is not a useful metric for financials since interest is a core operating cost, not a financing cost.

**Substitute metrics:**
- CET1 capital ratio (Common Equity Tier 1): > 10% is strong, < 8% is concerning
- Tangible book value per share: primary valuation anchor. P/TBV < 1.0 = potentially undervalued
- Net interest margin (NIM): tracks profitability of lending operations
- Efficiency ratio: lower is better (< 55% = well-run bank)
- Credit loss reserves / total loans: tracks provisioning adequacy
- Return on tangible common equity (ROTCE): > 15% = exceptional

**Moat indicators for banks:**
- Deposit franchise value (low-cost funding advantage)
- Regulatory licenses and compliance moats
- Scale in specific geographies or product lines

---

## Insurance and managed care (health insurers, P&C insurers)

**Why the standard framework needs adjustment:**
Insurance companies carry large float (premiums collected but not yet paid out as claims) and premium-funded liabilities that inflate balance sheet debt beyond what corporate leverage metrics capture. Net Debt / EBITDA can be calculated but must be interpreted carefully — a 2.0x ratio for an insurer is not the same risk as 2.0x for a tech company. EBITDA itself is less useful because insurance profitability is driven by the spread between premiums and claims, not by operating earnings in the traditional sense.

**Key metrics for health insurers / managed care:**
- Medical cost ratio (MCR) / Medical loss ratio (MLR): percentage of premiums paid out as medical claims. This is the single most important operating metric. Below 83% = strong; 83–86% = acceptable; above 86% = margin compression. Trend direction matters more than absolute level.
- Operating margin: health insurers typically operate at 4–9% GAAP operating margins. This is normal and not a sign of weakness — it reflects the nature of intermediation businesses at massive scale.
- Cash flows from operations / net income: should be >1.2x. Insurance generates strong operating cash flow relative to reported earnings because of float timing. If this ratio drops below 1.0x, investigate reserve adequacy.
- Membership / lives covered trends: growing membership = growing premium base. Declining membership may be strategic (exiting underpriced markets) or concerning (competitive loss). Always ask which it is.
- Interest coverage (EBIT / interest expense): should be >4x. Below 3x is a warning.
- Debt-to-capital (total debt / (total debt + equity)): context-dependent but >50% is elevated for an insurer.

**Key metrics for P&C insurers:**
- Combined ratio: claims + expenses as a percentage of premiums. Below 100% = underwriting profit. Above 100% = underwriting loss (may still be profitable via investment income). Trend matters.
- Reserve development: favorable = prior-year reserves were over-estimated (good). Adverse = under-estimated (bad, can cascade).

**Moat indicators for insurers:**
- Scale-driven negotiating leverage with providers (hospitals, drug manufacturers)
- State-by-state regulatory licenses as barriers to entry
- Employer and government contract stickiness (multi-year relationships)
- Data and actuarial advantages from decades of claims history
- Vertical integration (insurer + PBM + care delivery) — creates internal cost advantages but attracts antitrust scrutiny

**Valuation anchors:**
- P/E in the 12–22x range is typical for large managed care companies. Above 25x is aggressive.
- EV/Revenue is less useful because revenue includes premium pass-through at near-zero margin. Use EV/operating earnings or P/E.
- Dividend yield and payout ratio as percentage of FCF (not earnings — insurance FCF is more reliable than reported income).

---

## REITs (Real Estate Investment Trusts)

**Why the standard framework breaks:**
REITs are required to distribute 90%+ of taxable income as dividends. GAAP net income includes depreciation of real estate assets, which overstates the economic cost of maintaining properties. Net Debt / EBITDA should be replaced by Net Debt / EBITDA or Debt / Gross Asset Value.

**Substitute metrics:**
- FFO (Funds From Operations): net income + depreciation − gains on property sales. The primary earnings metric.
- AFFO (Adjusted FFO): FFO minus maintenance CapEx. The best proxy for sustainable cash flow.
- P/FFO: primary valuation multiple (replaces P/E). Compare to sector average and the REIT's own history.
- Dividend yield and payout ratio (as % of AFFO): sustainable if < 85% of AFFO
- Occupancy rate: should be > 90% for most property types
- Same-store NOI growth: organic growth indicator
- Debt/Gross Assets: < 40% is conservative, > 50% is aggressive

**Moat indicators for REITs:**
- Irreplaceable locations (urban infill, ports, data center clusters)
- Long-term lease structures with embedded escalators
- Specialized property types with high barriers to entry (data centers, life science labs, cell towers)

---

## Energy (oil & gas, utilities, renewables)

**Why standard valuation is tricky:**
Earnings are highly cyclical and commodity-dependent. Valuing on current-year earnings at a cycle peak will overstate fair value; valuing at a trough will understate it.

**Adjustments:**
- Normalize earnings across the full cycle (use 5–7 year average, or mid-cycle price assumptions)
- Reserve replacement ratio: for E&P companies, tracks whether they're replacing depleted reserves
- Finding and development costs (F&D): $ per barrel of proved reserves added
- Breakeven price: what oil/gas price does the company need to cover costs? Lower = more resilient.
- Debt / EBITDAX: the energy-specific version of Net Debt / EBITDA (X = exploration expenses added back)
- For utilities: regulated vs. unregulated revenue mix, rate case outcomes, allowed ROE

**Moat indicators for energy:**
- Low-cost production position (Permian Basin vs. deep-water offshore)
- Long-lived reserves in low-geopolitical-risk jurisdictions
- Pipeline/midstream infrastructure with take-or-pay contracts
- Regulated utility monopolies with predictable rate structures

---

## Healthcare (pharma, biotech, medtech)

**Adjustments for large pharma:**
- Patent cliff analysis: when do key drugs lose exclusivity? Revenue at risk?
- Pipeline value: late-stage (Phase 3) pipeline is more reliable than early-stage
- Drug pricing and regulatory risk: varies by geography and political cycle

**Adjustments for pre-revenue biotech:**
- The standard P/E, EBITDA, and revenue frameworks do not apply
- Focus on: cash runway (months at current burn), pipeline probability-adjusted NPV, binary catalysts (FDA decisions, trial readouts)
- Apply maximum margin of safety (40%+) — most biotechs fail
- Key moat: proprietary platform technology, first-mover in a validated mechanism

**Adjustments for medtech/devices:**
- Razor/blade model: low-margin device placement + high-margin consumables/services
- Regulatory approval as moat (510(k), PMA pathways create barriers)
- Hospital purchasing cycle: long sales cycles, GPO contracts

---

## Consumer staples and retail

**Adjustments:**
- Same-store sales growth: the most important organic growth metric for retail
- Inventory turnover: higher is generally better (efficient supply chain)
- Brand strength: pricing power evidenced by gross margin stability despite input cost inflation
- Private label penetration risk: tracks vulnerability to store-brand substitution

**Moat indicators:**
- Shelf-space dominance and retailer relationships
- Brand loyalty measurable through repeat purchase rates
- Distribution network density (especially for beverages, snacks)
- Habit-forming products with high purchase frequency

---

## Technology (SaaS, platforms, hardware)

**Adjustments for SaaS:**
- ARR (Annual Recurring Revenue) or MRR as primary revenue metric
- Net revenue retention / net dollar retention: > 110% = strong expansion, > 130% = exceptional
- Rule of 40: revenue growth rate + FCF margin > 40% = healthy SaaS
- CAC payback period and LTV/CAC ratio
- Gross margin: > 75% expected for pure SaaS; < 70% suggests significant hosting/services cost
- SBC as % of revenue: > 20% is a yellow flag for dilution

**Adjustments for hardware/semiconductor:**
- Cyclical — normalize across the inventory cycle
- Gross margin trajectory through the cycle
- Inventory days: rising inventory relative to revenue = demand risk
- Design wins and backlog as forward indicators
- CapEx intensity is high and expected — use EV/EBITDA − CapEx for cleaner comparison

**Moat indicators for tech:**
- Developer ecosystem lock-in (APIs, SDKs, marketplace)
- Data network effects (more users → more data → better product)
- High switching costs from integration depth and workflow embedding
- Patent portfolios (less durable than commonly assumed — monitor expiry and challenge risk)
