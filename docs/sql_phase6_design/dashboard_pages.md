# Phase 6 - Dashboard page specification

> **Historical design note.** This file records an earlier Phase 6 design state. The final delivered Power BI implementation supersedes it and is authoritative: **7 business pages + 1 hidden tooltip, 41 DAX measures, 11 semantic-model tables and 7 active single-direction relationships**. Retain this document for design lineage; use the final package README and `docs/Semantic_Model.md` for the current implementation.


**Positioning.** An executive retail decision-support dashboard integrating machine-learning demand forecasts
with explainable demand-risk indicators and prioritized management actions. **Not** a real-time operational
system (the model refits and the risk engine recomputes on a batch/scheduled cadence, not continuously) and
**not** a stockout or overstock prediction tool - every risk label is a demand-risk label, because the source
data has no inventory, lead-time or reorder information.

**The story across the four pages**, in the order a reader moves through them: *What will demand look like?*
(Page 1 orients, Page 2 explains) → *Where is risk concentrated?* (Page 3) → *What requires attention now?*
(Page 4, the work queue). A viewer who only has 30 seconds stops at Page 1; a planner starting their day lands
on Page 4.

**Design system.** One accent per risk level, used consistently everywhere a risk category appears (cards,
bars, conditional formatting) - never re-mapped page to page:

| Risk level | Color | Hex (placeholder - swap for house brand) |
|---|---|---|
| Low | Neutral grey | `#C3C2B7` |
| Medium | Blue | `#2A78D6` |
| High | Orange | `#EB6834` |
| Critical | Red | `#C0392B` |

Everything else (bars, lines, axes) uses a single neutral ink/grey scale - color is reserved for risk, never
spent on decoration. One font family, one size scale (28pt card numbers, 14pt titles, 10-11pt body/axis).
Every page keeps a consistent 1-inch-equivalent margin and the same top strip (title, page purpose sub-title,
global slicers) so the four pages read as one product, not four different exports.

---

## Page 1 - Executive Overview

**Question answered:** *What is expected to happen, at a glance?*
**Decision it supports:** whether leadership needs to dig further today, and which stores/families to ask
about first.
**Planner action:** none directly - this page routes attention to Pages 2-4.

**KPI row (6 cards, top of page):**

| Card | Measure | Format |
|---|---|---|
| Total Forecast Demand | `[Total Forecast Demand]` | `#,##0,,"K"` / `,,"M"` auto |
| Average Daily Forecast | `[Average Daily Forecast]` | `#,##0` units/day |
| High + Critical Risk Cases | `[High + Critical Count]` | whole number, colored by the High/Critical accents |
| P1 Immediate Review Cases | `[P1 Count]` | whole number, Critical-red accent (it is the most urgent single figure on the page) |
| Average Demand Risk Score | `[Average Risk Score]` | 1 decimal, "/100" suffix |
| Forecast Model RMSLE | `[Forecast Model RMSLE]` with `[Baseline RMSLE]` and `[Model Improvement %]` as a small sub-label ("vs 0.469 baseline, -16.0%") | 4 decimals for RMSLE, 1 decimal % for improvement |

**Visuals:**

1. **Daily forecast trend (line chart)** - X: `DimDate[date]` (filtered to the 16 forecast days via `vw_ForecastTrend` / FactForecast), Y: `[Total Forecast Demand]`. One reference line for the portfolio average day. Answers "is demand flat, ramping or falling across the window."
2. **Risk category distribution (bar chart, not a pie)** - X: `risk_category` (fixed order Low→Critical), Y: `COUNTROWS(FactDemandRisk)`, bars colored by the risk palette above. A pie was deliberately avoided per the brief's own guidance and because four ordered categories read faster as a bar.
3. **Top 10 stores by forecast volume (bar chart)** - `[Total Forecast Demand]` by `DimStore[store_nbr] & " - " & city`, sorted by `[Store Rank by Forecast Demand]`.
4. **Top 10 families by forecast volume (bar chart)** - `[Total Forecast Demand]` by `DimProductFamily[family]`, sorted by `[Family Rank by Forecast Demand]`.
5. **Top 10 stores by High/Critical risk count (bar chart)** - a measure `CALCULATE([High + Critical Count])` by store, sorted descending - deliberately a *different* top-10 from visual 3, so a reader immediately sees that "biggest by volume" and "riskiest" are not the same stores (they aren't - see `phase6_dashboard_documentation.md`).

**Slicers (page-level, top strip):** Store (`DimStore[store_nbr]`, searchable list), Product Family
(`DimProductFamily[family]`), Risk Category (`FactDemandRisk[risk_category]`, buttons). These three slicers are
repeated identically on Pages 2-3 (Power BI "sync slicers") so a filter set on Page 1 carries through the story.

---

## Page 2 - Demand Forecast Analysis

**Question answered:** *What does expected demand actually look like, and how does it compare with the recent
past?*
**Decision it supports:** whether the forecast level itself looks reasonable for a given store/family before
acting on any risk flag.
**Planner action:** sanity-check a forecast against history and promotion activity before trusting the number.

**Visuals:**

1. **Forecast by day (line/area chart)** - same as Page 1's trend but larger, with promotion split: two series, `[Total Forecast Demand]` filtered to `onpromotion > 0` vs `= 0` (stacked area or two lines), directly answering "promotion vs non-promotion demand."
2. **Forecast by store (bar chart)** - `[Total Forecast Demand]` by store, same measure as Page 1 but paired here with...
3. **Forecast by product family (bar chart)** - `[Total Forecast Demand]` by family.
4. **Forecast growth vs historical demand (scatter/clustered column)** - X or category = Store x Family (or aggregated by family), showing `historical_28d_avg` next to `forecast_daily_avg` side by side (clustered column) *or*, for a compact executive view, a scatter with `historical_28d_avg` on X and `forecast_daily_avg` on Y, a 45-degree reference line - points above the line are growing, below are declining. Colored by `risk_category`.
5. **Top demand increases (table, Top 15)** - built from `[Average Forecast Growth %]` at row level (i.e. `FactDemandRisk[forecast_growth_pct]` filtered `sparse_history = FALSE`), sorted descending. Columns: Store, Family, Historical 28-Day Avg, Forecast Daily Avg, Growth %, Promotion Days.
6. **Top demand declines (table, Top 15)** - same columns, sorted ascending on growth %.

**Tooltips (report-page tooltip or default tooltip on visuals 2-6):** a small tooltip page showing, for the
hovered Store x Family: Historical 28-Day Avg, Forecast Daily Avg, Growth %, Promotion Days (of 16) - exactly
the four fields the brief asks for, kept together so a reader never has to leave the visual to get context.

---

## Page 3 - Demand Risk Intelligence

**Question answered:** *Where is demand risk concentrated, and how much can the underlying forecast be
trusted there?*
**Decision it supports:** which stores or families warrant a category-level review, not just a single-row fix.
**Planner action:** flag a store or family for a deeper look; treat a "High Forecast Uncertainty" series with
extra caution regardless of what its risk score says.

**KPI row:** High Risk Count, Critical Risk Count, Average Risk Score, High Forecast Uncertainty Count (all
four measures defined above) - the same card style as Page 1, scoped to whatever the page's slicers select.

**Visuals:**

1. **Risk distribution by store (matrix or heatmap)** - rows = store, columns = `risk_category`, values =
   `COUNTROWS(FactDemandRisk)`, cell background colored by the risk palette (a small multiple / heatmap makes
   54 stores scannable at once, which a bar chart of 54 bars would not).
2. **Risk distribution by family (matrix or heatmap)** - same shape, rows = family (33 rows fits directly, no
   scrolling needed).
3. **Demand Risk Score ranking (bar chart, Top 20)** - `demand_risk_score` by Store x Family (label =
   `store_nbr & " - " & family`), sorted descending, colored by `risk_category` - the single most direct "who's
   highest risk" visual on the page.
4. **Surge Risk vs Decline Risk (scatter)** - X = `demand_surge_risk`, Y = `demand_decline_risk`, one point per
   Store x Family, sized by `forecast_16d_total`, colored by `risk_category`. Because a series scores near-zero
   on whichever dimension does not apply to it (Phase 5's own design), points cluster along the two axes -
   visually separating "surging" from "declining" series at a glance, with size showing which ones matter most
   by volume.
5. **Volatility vs Forecast Uncertainty (scatter)** - X = `demand_volatility_risk`, Y =
   `forecast_uncertainty_score`, colored by `risk_category`. Answers a distinct question from visual 4: is this
   series risky because its *own history* is erratic, because the *model* has historically struggled with its
   family/store, or both (top-right quadrant - the cases needing the most planner judgment).

**Conditional formatting:** every table/matrix on this page applies background-color rules on `risk_category`
(Low/Medium/High/Critical → the four palette colors) and font-bold + red text on any row where
`action_priority = "P1 - Immediate review"`, so High/Critical and P1 rows are never just another row in a long
list - exactly the brief's "should stand out clearly" requirement.

---

## Page 4 - Action Center

**Question answered:** *What should a planner review first, today?*
**Decision it supports:** the literal work order for demand-risk follow-up.
**Planner action:** open each P1/P2 row in priority order, read the recommended action, then bring in
inventory position, lead time and supplier constraints (which this dashboard does not have) before deciding
what to order.

**Central visual - the management action table**, bound to `vw_HighPriorityActions` (P1 rows) with the Store/
Family/Risk Category slicers able to widen it to P2/P3 via the priority filter below. Columns, in order:

| Column | Source | Format |
|---|---|---|
| Priority | `action_priority` | text, with a colored priority chip (P1 red, P2 orange, P3 grey) via conditional formatting |
| Store | `store_nbr` + `city` | text |
| Product Family | `family` | text |
| Forecast Demand | `forecast_16d_total` | `#,##0` |
| Historical Demand | `historical_28d_avg` | `#,##0.0` |
| Growth % | `forecast_growth_pct` | percentage, 1 decimal, data bars (diverging: red for negative, blue for positive) |
| Demand Risk Score | `demand_risk_score` | 1 decimal, data bars 0-100 |
| Risk Category | `risk_category` | conditional background color |
| Forecast Uncertainty | `forecast_uncertainty` | text, bold red when "High" |
| Recommended Action | `recommended_action` | text (wrapped) |

**Default sort:** `action_priority` ascending (P1 → P2 → P3 - text is prefixed "P1 -", "P2 -", "P3 -" so a plain
alphabetical sort already gives the right order) then `demand_risk_score` descending - exactly the brief's
"P1 first, then highest Risk Score" rule, achieved without a hidden helper column.

**Filters:** a slicer for `action_priority` (P1/P2/P3, multi-select, defaulted to P1+P2 so the page opens
already focused on what matters), plus the shared Store, Family and Risk Category slicers from Pages 1-3.

**Framing reminder printed on the page** (small caption under the title, not a disclaimer nobody reads): *"Demand-based inventory risk, not a stockout or overstock prediction. Recommended actions are a starting point for planner review, not an automated purchasing decision - lead times, safety stock and supplier constraints are not in this model."*

---

## Cross-page consistency checklist

- Every visible label uses the business-friendly names from `data_model.md` (e.g. "Forecast Growth %", never
  `forecast_growth_pct`).
- Risk-category colors never change meaning between pages.
- The same three slicers (Store, Family, Risk Category) appear identically on Pages 1-3; Page 4 adds the
  Priority slicer on top of them.
- No pie chart, no gauge, no decorative KPI without a bound measure - every visual on every page is listed
  above with the exact measure/column and the question it answers.
