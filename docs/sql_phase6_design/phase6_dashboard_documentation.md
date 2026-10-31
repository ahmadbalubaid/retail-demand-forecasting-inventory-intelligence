# Phase 6 - SQL Server + Power BI Decision Dashboard

> **Historical design note.** This file records an earlier Phase 6 design state. The final delivered Power BI implementation supersedes it and is authoritative: **7 business pages + 1 hidden tooltip, 41 DAX measures, 11 semantic-model tables and 7 active single-direction relationships**. Retain this document for design lineage; use the final package README and `docs/Semantic_Model.md` for the current implementation.


**Project positioning.** An executive retail decision-support dashboard integrating machine-learning demand
forecasts with explainable demand-risk indicators and prioritized management actions. It is **not** a
real-time operational system and **not** a stockout or overstock prediction tool - the underlying data has no
inventory-on-hand, reorder point, lead-time or purchase-order information, so every output is demand risk, not
a stock-event prediction (carried over unchanged from Phase 5).

**What Phase 6 does.** Takes the Phase 4 forecast (28,512 rows, RMSLE 0.3942 vs a 0.4693 baseline) and the
Phase 5 risk engine output (1,782 Store x Family series, 4 risk dimensions, a 0-100 Demand Risk Score, risk
category and action priority) and reshapes them - unchanged - into a small SQL Server star schema, four
governed analytical views, nine business queries, and a fully specified 4-page Power BI dashboard with 20 DAX
measures. **No ML model is retrained, no Phase 4 prediction is modified, and no Phase 5 risk rule, weight or
threshold is altered** - every number in this phase traces back to a Phase 4/5 output file.

## Architecture

```
Phase 4 (final_forecast.parquet, test_predictions.parquet)  ─┐
                                                               ├─► phase6/build_star_schema.py ─► 6 CSVs ─► SQL Server (BULK INSERT)
Phase 5 (inventory_risk_engine.parquet, risk_engine_config)  ─┘                                        │
                                                                                                          ▼
                                                                                   5 views + 9 business queries (phase6/sql/)
                                                                                                          │
                                                                                                          ▼
                                                                                   Power BI star-schema model + 20 DAX measures
                                                                                                          │
                                                                                                          ▼
                                                                                   4-page dashboard (phase6/powerbi/dashboard_pages.md)
```

A real SQL Server instance is not available in this environment, so `phase6/sql/*.sql` is written for SQL
Server 2019+ syntax and its logic is validated against a DuckDB reference build of the same CSVs
(`phase6/reconciliation/validate.py`) - 26/26 checks pass exactly against the Python outputs. See
`phase6/reconciliation/reconciliation_checklist.md` for the full comparison. A Power BI Desktop file (.pbix)
similarly cannot be produced headlessly here; `phase6/powerbi/` instead gives a complete, unambiguous build
spec (data model, every DAX measure with its explanation, every page's visuals and formatting) that reproduces
the same numbers, already reconciled against Python.

## Tables

| Table | Grain | Rows | Keys |
|---|---|---|---|
| DimStore | store | 54 | PK `store_nbr` |
| DimProductFamily | family | 33 | PK `family` |
| DimDate | calendar day (2013-01-01 .. 2017-08-31) | 1,704 | PK `date` |
| FactForecast | date x store x family | 28,512 | PK `(date, store_nbr, family)`; FK to all 3 dimensions |
| FactDemandRisk | store x family (16-day summary) | 1,782 | PK `(store_nbr, family)`; FK to DimStore, DimProductFamily - **not related to DimDate** (it is not a daily fact) |
| FactModelPerformance | validation fold | 5 | PK `fold`; standalone reference table for the RMSLE KPI |

Full DDL with data types, constraints and indexes: `phase6/sql/01_schema.sql`. Load workflow (BULK INSERT from
the CSVs Phase 5 already produced): `phase6/sql/02_load_data.sql`.

## Relationships (Power BI / conceptually identical to the SQL foreign keys)

Single-direction, Dim → Fact, every one of them - no bidirectional relationship anywhere in the model:

- `DimStore[store_nbr]` → `FactForecast[store_nbr]`, `DimStore[store_nbr]` → `FactDemandRisk[store_nbr]`
- `DimProductFamily[family]` → `FactForecast[family]`, `DimProductFamily[family]` → `FactDemandRisk[family]`
- `DimDate[date]` → `FactForecast[date]` only

Full rationale (including *why* FactDemandRisk deliberately has no date relationship, and why no extra
dimensions were added) is in `phase6/powerbi/data_model.md`.

## Measures

20 DAX measures covering core demand, risk counts, action priority, growth/promotion, portfolio mix, model
performance and 4 dynamic ranking measures - every one explained inline. Full list with explanations:
`phase6/powerbi/dax_measures.dax`.

## Dashboard pages

| Page | Answers | Planner action |
|---|---|---|
| 1. Executive Overview | What is expected to happen, at a glance? | Routes attention to the other 3 pages |
| 2. Demand Forecast Analysis | What does expected demand look like vs recent history? | Sanity-check a forecast before acting on a risk flag |
| 3. Demand Risk Intelligence | Where is risk concentrated, and how trustworthy is the forecast there? | Flag a store/family for deeper review |
| 4. Action Center | What should a planner review first, today? | Work the P1 queue, then bring in inventory/lead-time context this data doesn't have |

Full visual-by-visual specification, KPI list, slicers, tooltip fields, conditional-formatting rules and the
cross-page design system: `phase6/powerbi/dashboard_pages.md`.

## The story the dashboard tells (and why it needed 4 pages, not 1)

Two things are checked directly in the data to make sure this story is true, not just asserted:

- **The biggest stores by forecast volume are not the riskiest stores.** The top-10 stores by forecast demand
  (44, 45, 47, 3, 49, 46, 51, 48, 52, 8) and the top-10 stores by High/Critical risk count (26, 25, 30, 35, 13,
  10, 20, 14, 22, 32) **are largely different**. With deterministic store-number tie-breaking, the displayed top ten has zero overlap; however, the High/Critical ranking has a six-way tie at 9 cases around the cutoff (Stores 14, 20, 22, 32, 43 and 48), and Store 48 is also a top-volume store. The durable conclusion is therefore limited overlap depending on tie handling. A dashboard that only showed "biggest stores" (Page 1's volume
  visual) would point a planner at entirely the wrong place - which is exactly why Page 1 deliberately shows
  *both* a "top by volume" and a "top by risk" visual side by side, and why Page 3 exists at all.
- **Volume and risk overlap only weakly at the family level too.** Of the top-10 families by forecast volume
  (led by GROCERY I, BEVERAGES, PRODUCE) and the top-10 by High/Critical risk count (led by SCHOOL AND OFFICE
  SUPPLIES, BEAUTY, LINGERIE), only **CLEANING** appears in both lists.
- **44 series are both High/Critical risk and in the top volume tercile** (Page 3's scatter, Page 4's queue) -
  these are the cases where getting the forecast wrong matters most, and they are a small, specific list, not
  "most of the business."
- **Promotion-heavy series (8+ of 16 days on promotion) score meaningfully higher average Demand Surge Risk**
  (57.5) **than low/no-promotion series** (41.5) - confirming the surge dimension is picking up a real,
  explicable pattern rather than noise.

## Validation

26/26 reconciliation checks pass (row counts, KPI totals, risk-category and priority distributions, top-store/
top-family rankings, no duplicate keys, dormant series correctly excluded from P1) - see
`phase6/reconciliation/reconciliation_checklist.md`. Every SQL-layer number in that checklist is independently
computed from the star-schema CSVs and compared against the corresponding Phase 4/5 Python output; none are
copied from one side to the other.

## Files in this phase

```
phase6/
  build_star_schema.py                         # Phase 4/5 outputs -> 6 star-schema CSVs (read-only source)
  star_schema_csv/{DimStore,DimProductFamily,DimDate,FactForecast,FactDemandRisk,FactModelPerformance}.csv
  sql/01_schema.sql                             # tables, PK/FK, indexes, CHECK constraints
  sql/02_load_data.sql                          # BULK INSERT load workflow + post-load row-count checks
  sql/03_views.sql                              # vw_ExecutiveOverview, vw_StoreRiskSummary, vw_FamilyRiskSummary,
                                                 # vw_HighPriorityActions, vw_ForecastTrend
  sql/04_business_queries.sql                   # 9 standalone business queries, each with its business question
  powerbi/data_model.md                         # tables, relationships, formatting, business-friendly names
  powerbi/dax_measures.dax                      # 20 DAX measures, every one explained
  powerbi/dashboard_pages.md                    # 4-page visual-by-visual specification
  reconciliation/validate.py                    # DuckDB reference build + 26 automated checks
  reconciliation/reconciliation_checklist.md    # the 26 checks, documented
  reconciliation/reconciliation_results.csv     # raw check output
  phase6_dashboard_documentation.md             # this file
```

## Constraints honored

No ML model retrained; no Phase 4 prediction modified (`FactForecast.predicted_sales` is Phase 4's own
`final_forecast.parquet` value, byte-for-byte); no Phase 5 risk rule, weight or threshold altered
(`FactDemandRisk` is Phase 5's `inventory_risk_engine.parquet`, reshaped only); SQL Server is the analytical
layer, Power BI is the presentation/decision-support layer; the schema and model stay simple enough to explain
in an interview (natural keys, 3 dimensions, 2 fact tables at their natural grains, no bidirectional
relationships, no dimension added without a reuse case); every KPI and visual in `dashboard_pages.md` is tied
to a named business question; every number is validated against the Python outputs before being called
complete.
