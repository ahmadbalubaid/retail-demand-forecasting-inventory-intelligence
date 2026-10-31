# Phase 6 - Power BI data model

> **Historical design note.** This file records an earlier Phase 6 design state. The final delivered Power BI implementation supersedes it and is authoritative: **7 business pages + 1 hidden tooltip, 41 DAX measures, 11 semantic-model tables and 7 active single-direction relationships**. Retain this document for design lineage; use the final package README and `docs/Semantic_Model.md` for the current implementation.


## Shape: a fact constellation (two stars sharing dimensions), not a single star

The project has two things worth reporting on at two different grains, so it needs two fact tables:

- **FactForecast** - daily grain: one row per `(date, store_nbr, family)`, 28,512 rows. Additive across every
  dimension - safe to `SUM` under any filter.
- **FactDemandRisk** - series grain: one row per `(store_nbr, family)`, 1,782 rows. This is Phase 5's own
  16-day summary (it already *is* an aggregate - `forecast_16d_total`, `demand_risk_score`, etc.), so it is
  **not** additive across date and is **not related to DimDate**. Trying to slice a risk score by a single day
  would silently produce a meaningless number, so that relationship is deliberately left out rather than added
  and marked inactive - the safest way to prevent a wrong slice is to make it structurally impossible.

Both fact tables share two dimensions (DimStore, DimProductFamily), which is what makes this a valid,
easy-to-explain model rather than two disconnected tables: filtering by store or family on any visual filters
both facts consistently.

## Tables loaded into Power BI

| Table | Source | Rows | Role |
|---|---|---|---|
| DimStore | `phase6/star_schema_csv/DimStore.csv` | 54 | Dimension |
| DimProductFamily | `phase6/star_schema_csv/DimProductFamily.csv` | 33 | Dimension |
| DimDate | `phase6/star_schema_csv/DimDate.csv` | 1,704 | Dimension (mark as **Date table** in Power BI) |
| FactForecast | `phase6/star_schema_csv/FactForecast.csv` | 28,512 | Fact (daily grain) |
| FactDemandRisk | `phase6/star_schema_csv/FactDemandRisk.csv` | 1,782 | Fact (series grain) |
| FactModelPerformance | `phase6/star_schema_csv/FactModelPerformance.csv` | 5 | Small reference table (one row per Phase 4 validation fold) - not related to anything; only its own two columns are aggregated (`AVERAGE(model_rmsle)`, `AVERAGE(baseline_rmsle)`) for the Page-1 RMSLE KPI |

Import mode (not DirectQuery) is appropriate here: the whole model is under 1 MB and refreshes on a schedule
tied to the (offline, batch) forecasting pipeline, not in real time - consistent with Phase 5's own statement
that this is a decision-support system, not a real-time operational one.

## Relationships

| From (one) | To (many) | Cardinality | Cross-filter direction | Active |
|---|---|---|---|---|
| DimStore[store_nbr] | FactForecast[store_nbr] | 1:* | Single (Dim → Fact) | Yes |
| DimProductFamily[family] | FactForecast[family] | 1:* | Single (Dim → Fact) | Yes |
| DimDate[date] | FactForecast[date] | 1:* | Single (Dim → Fact) | Yes |
| DimStore[store_nbr] | FactDemandRisk[store_nbr] | 1:* | Single (Dim → Fact) | Yes |
| DimProductFamily[family] | FactDemandRisk[family] | 1:* | Single (Dim → Fact) | Yes |

**No relationship exists between FactForecast and FactDemandRisk directly** - they are only ever connected
*through* DimStore / DimProductFamily, which is exactly what keeps this a star (not a snowflake or a tangle of
fact-to-fact joins). **No bidirectional relationship is used anywhere**: every relationship filters from the
one-side dimension down to the many-side fact, which is the correct and only direction needed here - nothing
in this model requires a fact table to filter a dimension backwards (e.g. "only show stores that appear in a
filtered FactDemandRisk" is achieved by the visual's own selection, not by a bidirectional relationship, which
would risk ambiguous filter paths once a second fact table is in the model).

## Column formatting set in the model (not just in visuals)

| Column | Format |
|---|---|
| `FactForecast[predicted_sales]`, `FactDemandRisk[forecast_16d_total]`, `historical_28d_avg`, `historical_91d_avg` | Whole/decimal number, thousands separator |
| `FactDemandRisk[forecast_growth_pct]`, `[promo_intensity_hist_28d]` (and any DAX `%` measure) | Percentage, 1 decimal |
| `FactDemandRisk[demand_risk_score]`, `[demand_surge_risk]`, `[demand_decline_risk]`, `[demand_volatility_risk]`, `[forecast_uncertainty_score]`, `[priority_score]` | Decimal number, **1 decimal place** |
| `FactModelPerformance[model_rmsle]`, `[baseline_rmsle]` | Decimal number, 4 decimal places (a small, technical metric shown once on Page 1, not throughout) |
| `FactDemandRisk[risk_category]`, `[action_priority]` | Text, used to drive conditional formatting (see `dashboard_pages.md`) |

## Business-friendly field names

Power BI's "Name" property is renamed for every field a viewer sees (the underlying `snake_case` column name
stays for lineage/reconciliation, but visuals never display it):

| Technical column | Displayed as |
|---|---|
| `forecast_16d_total` | Forecast Demand (16-Day) |
| `forecast_daily_avg` | Avg. Daily Forecast |
| `historical_28d_avg` | Historical Demand (28-Day Avg) |
| `historical_91d_avg` | Historical Demand (91-Day Avg) |
| `forecast_growth_pct` | Forecast Growth % |
| `promotion_days` | Promotion Days (of 16) |
| `demand_surge_risk` | Demand Surge Risk |
| `demand_decline_risk` | Demand Decline Risk |
| `demand_volatility_risk` | Demand Volatility Risk |
| `forecast_uncertainty` / `forecast_uncertainty_score` | Forecast Uncertainty / Forecast Uncertainty Score |
| `demand_risk_score` | Demand Risk Score |
| `risk_category` | Risk Category |
| `action_priority` | Action Priority |
| `recommended_action` | Recommended Action |
| `store_nbr` | Store |
| `family` | Product Family |

## Why not more dimensions

A `DimActivityStatus` or `DimRiskCategory` table was considered and deliberately skipped: both are short,
already-clean text columns living on FactDemandRisk (4 and 3 distinct values), so snowflaking them into their
own tables would add joins without adding any analytical capability - exactly the "additional dimensions only
if they improve the model" test the brief sets. `DimDate` earns its place because date intelligence (day name,
weekend flag, week) is genuinely reused across two pages.
