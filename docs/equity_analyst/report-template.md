# Report Template — Owner-Mentality Equity Analysis

Use this exact structure for every analysis report. All sections are mandatory unless noted. Adapt the depth of each section to the complexity of the company — a straightforward utility doesn't need 2,000 words on moat, while a platform business might.

---

## Required report structure

```markdown
# [Company Name] ([TICKER]) — Owner-Mentality Value Investment Analysis

**Date:** [date of analysis]
**Ticker:** [TICKER] ([exchange])
**Price at analysis:** ~$[price] [note if post-split, adjusted, etc.]
**Market cap:** ~$[market cap]
**Verdict:** [Buy / Accumulate on weakness / Watch / Hold / Sell]

> **Disclaimer.** This report is for informational and research purposes only and does not constitute investment advice, a recommendation, or an offer to buy or sell securities. All financial figures should be cross-checked against the company's primary SEC filings before being relied upon for investment decisions.

---

## Executive Summary

[3–5 sentences. State what the company does, the core thesis, the current valuation context, and the verdict. This should be readable standalone — someone who reads only this paragraph should understand your position.]

---

## 1. Business Model & Moat Analysis

### Core business model
[What does the company actually do? How does it make money? What's the revenue mix (subscription vs. one-time, product vs. services, etc.)? Who are the customers?]

### Asset classification: [Asset Light / Asset Heavy]
[Justify with CapEx/Revenue ratio and business model characteristics. State how this affects acceptable valuation multiples.]

### Economic moat

| Moat dimension | Score (0–5) | Evidence |
|---|---|---|
| Switching costs | [X]/5 | [specific evidence] |
| Scale advantage | [X]/5 | [specific evidence] |
| Network effect | [X]/5 | [specific evidence] |
| Intangibles | [X]/5 | [specific evidence] |

**Overall moat assessment:** [Wide / Narrow / None]

**Primary moat threat:** [Name the specific vulnerability — be concrete, not vague]

---

## 2. Quantitative Health & Solvency

### Net Debt / EBITDA — solvency check

| Component | Value |
|---|---|
| Total debt | $[X] |
| Cash & short-term investments | $[X] |
| Net debt (or net cash) | $[X] |
| TTM EBITDA (GAAP) | $[X] |
| **Net Debt / EBITDA** | **[X]x** |
| Framework rating | [Excellent / Acceptable / Warning / Red flag] |

### Revenue vs. earnings trend (5-year)

| Metric | FY[Y-4] | FY[Y-3] | FY[Y-2] | FY[Y-1] | FY[Y] |
|---|---|---|---|---|---|
| Revenue | | | | | |
| Revenue growth YoY | | | | | |
| Net income (GAAP) | | | | | |
| Free cash flow | | | | | |
| FCF margin | | | | | |
| Operating margin (GAAP) | | | | | |

**Revenue stability assessment:** [stable/improving/volatile/declining]

**Earnings divergence explanation:** [If earnings diverge from revenue, explain why — reinvestment, margin compression, one-time items, etc.]

### Most recent earnings

- **Quarter:** [Q? FY????]
- **Revenue:** $[X] — [beat/miss] consensus by [X]%
- **EPS:** $[X] — [beat/miss] consensus by [X]%
- **Guidance:** [raised/maintained/lowered/not provided]
- **Within ±5% tolerance?** [Yes / No — if no, explain significance]

---

## 3. Valuation & Sentiment

### Current multiples

| Metric | Current | 5-year avg | Sector median | Assessment |
|---|---|---|---|---|
| Trailing P/E | | | | |
| Forward P/E | | | | |
| EV/Revenue | | | | |
| EV/EBITDA | | | | |
| PEG ratio | | | | |
| EV/FCF | | | | |

### Value trap check

**Is the current valuation a trap or an opportunity?**

[Answer these three questions in prose:]
1. What is the market's specific reason for the discount?
2. Do current fundamentals show actual deterioration (declining revenue, rising churn, margin collapse)?
3. Is the fear about actual deterioration or anticipated future deterioration?

**Conclusion:** [Value trap / Not a value trap — with reasoning]

### Margin of safety assessment

[Calculate margin of safety using at least two methods. Show your math.]

- Method 1: [e.g., FCF yield vs. required return]
- Method 2: [e.g., EV/Revenue vs. historical median]

**Required margin of safety:** [15–20% standard / 25%+ high uncertainty / 30%+ no moat / 40%+ speculative]
**Current margin of safety:** [X]% [sufficient / insufficient]

---

## 4. Portfolio Fit

- **Beta:** [X] — [interpretation for position sizing]
- **Classification:** [Pure appreciation / Income / Hybrid]
- **Dividend yield:** [X]% (or none)
- **Sharpe ratio contribution:** [assessment of risk-adjusted return potential]

---

## 5. Red Flags — Explicitly Listed

[Number each red flag. Be specific. Quantify where possible. Each should be 2–3 sentences.]

1. **[Red flag name].** [Description with data.]
2. **[Red flag name].** [Description with data.]
[... as many as needed, but at least 3]

---

## 6. What to Watch

[3–5 specific upcoming events or metrics that would change the thesis. Include dates where known.]

1. [Event/metric + date + why it matters]
2. ...

---

## 7. Thesis Summary

[A synthesis paragraph that ties everything together. Restate the verdict with conviction. Mention the key condition that would change your mind.]

**Bottom line:** [One-sentence actionable conclusion.]

---

## Sources

[List key URLs and documents consulted. Group by type if helpful.]

---

*Prepared [date]. Not investment advice. Verify all figures against primary SEC filings before acting.*
```

---

## Style notes

- Write in direct, analytical prose. Avoid hedging language ("it could potentially maybe..."). State your assessment and explain why.
- Use the company's actual product names and customer references where known.
- Quantify everything you can. "Significant federal exposure" is weak; "federal segment estimated at ~15% of revenue" is strong.
- Show calculations explicitly: "Net Debt / EBITDA = ($2.4B - $6.3B) / $2.6B = net cash" is better than just stating "net cash position."
- Flag anything you couldn't verify with `[unverified]`.
- Don't pad the report. If a section doesn't apply (e.g., dividend analysis for a growth stock), say so briefly and move on.
