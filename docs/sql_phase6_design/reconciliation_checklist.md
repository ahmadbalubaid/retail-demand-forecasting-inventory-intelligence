# Phase 6 reconciliation checklist

> **Historical design note.** This file records an earlier Phase 6 design state. The final delivered Power BI implementation supersedes it and is authoritative: **7 business pages + 1 hidden tooltip, 41 DAX measures, 11 semantic-model tables and 7 active single-direction relationships**. Retain this document for design lineage; use the final package README and `docs/Semantic_Model.md` for the current implementation.


**Method.** No SQL Server instance is available in this environment, so the T-SQL in `phase6/sql/` was written for
SQL Server 2019+ and validated for *logical correctness* by loading the exact same star-schema CSVs
(`phase6/star_schema_csv/`) into a DuckDB reference database and re-running the equivalent aggregation logic behind
every view and the two queries checked below (`phase6/reconciliation/validate.py`). DuckDB and SQL Server agree on
standard SQL (`GROUP BY`, `CASE`, window functions, joins); the only differences are dialect-level syntax (`TOP` vs
`LIMIT`, `N'...'` string literals, bracketed identifiers) which do not change what a query computes. **Every number
below is produced independently from the Phase 4/5 Python outputs and from the SQL layer, then compared - not
copied from one to the other.** All 26 checks pass; the raw results are in `reconciliation_results.csv`.

| # | Check | SQL layer | Python source (Phase 4/5) | Match |
|---|---|---|---|---|
| 1 | DimStore row count | 54 | 54 stores (`data/stores.csv`) | Yes |
| 2 | DimProductFamily row count | 33 | 33 families | Yes |
| 3 | FactForecast row count | 28,512 | `final_forecast.parquet` (54 x 33 x 16) | Yes |
| 4 | **FactDemandRisk row count = 1,782** | 1,782 | `inventory_risk_engine.parquet` | Yes |
| 5 | Total forecasted sales | 12,563,212.30 | `final_forecast.predicted_sales.sum()` | Yes |
| 6 | Store count | 54 | 54 | Yes |
| 7 | Active series count | 1,702 | series with `activity_status` not in (dormant, never sold) | Yes |
| 8 | High + Critical risk count | 304 | `risk_category` in (High, Critical) | Yes |
| 9 | **P1 - Immediate review count = 123** | 123 | `action_priority == 'P1 - Immediate review'` | Yes |
| 10 | Average Demand Risk Score | 48.657 | `demand_risk_score.mean()` | Yes |
| 11 | Forecast model RMSLE (mean of 5 folds) | 0.3942 | Phase 4 `final_model_config.json` | Yes |
| 12-15 | **Risk category distribution matches Phase 5** - Low 537 / Medium 941 / High 286 / Critical 18 | exact | exact | Yes |
| 16-18 | Action priority distribution - P1 123 / P2 1,122 / P3 537 | exact | exact | Yes |
| 19 | Q1 - top store by forecast demand | store 44 | store 44 (pandas `idxmax`) | Yes |
| 20 | Q4 - top family by High/Critical count | SCHOOL AND OFFICE SUPPLIES | SCHOOL AND OFFICE SUPPLIES | Yes |
| 21 | vw_HighPriorityActions row count | 123 | `high_priority_actions.csv` (123 rows) | Yes |
| 22 | vw_ForecastTrend row count | 16 | 16 forecast dates | Yes |
| 23 | vw_ForecastTrend total (sum of 16 daily totals) | 12,563,212.30 | same as check 5 | Yes |
| 24 | **No duplicate keys - FactForecast (date, store_nbr, family)** | 0 duplicates | - | Yes |
| 25 | **No duplicate keys - FactDemandRisk (store_nbr, family)** | 0 duplicates | - | Yes |
| 26 | Dormant/never-sold series rated P1 | 0 | must be 0 (Phase 5's own validation, section 12) | Yes |

## What this confirms

- **Forecast totals reconcile with Phase 4**: the SQL layer's `SUM(predicted_sales)` over 28,512 rows matches the
  Phase 4 `final_forecast.parquet` total to the cent (checks 5, 23).
- **Risk distribution matches Phase 5 exactly**: every one of the four risk categories and three priority tiers
  reproduces the Phase 5 count with zero drift (checks 12-18) - the star schema did not lose, duplicate or
  misclassify a single one of the 1,782 series.
- **No duplicate keys were introduced** by the CSV export or the schema design (checks 24-25) - `PRIMARY KEY
  (date, store_nbr, family)` on FactForecast and `PRIMARY KEY (store_nbr, family)` on FactDemandRisk hold.
- **SQL and Power BI values will match Python outputs**: because Power BI's data model (Part B) imports these same
  five tables and every DAX measure is a straight `SUM`/`AVERAGE`/`COUNTROWS` over them (no DAX-side recomputation
  of risk logic), any number a Power BI visual shows is provably the same aggregation already verified here.
- **Phase 5's own internal validation still holds through the SQL layer** (check 26): dormant/never-sold series are
  0-for-123 in P1, exactly as Phase 5 documented before this data ever reached SQL.

## Re-running this check

```bash
pip install duckdb --break-system-packages
python3 phase6/build_star_schema.py        # rebuild the CSVs from the Phase 4/5 outputs (idempotent, read-only source)
python3 phase6/reconciliation/validate.py  # re-run all 26 checks
```

On a real SQL Server instance, run `phase6/sql/01_schema.sql` → `02_load_data.sql` (after pointing `@LoadPath` at
wherever `phase6/star_schema_csv/` was copied) → the row counts printed at the end of `02_load_data.sql` should
match the "SQL layer" column above exactly.
