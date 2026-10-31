/* ============================================================================================================
   03_views.sql - analytical views for Power BI
   Every view is a straight aggregation/join over dbo.FactForecast / dbo.FactDemandRisk and the three
   dimensions - no risk logic, threshold or weight is recomputed here; they are read from FactDemandRisk exactly
   as Phase 5 produced them. Power BI should import these views (or DirectQuery them), not the raw fact tables,
   so every report uses the same governed definition of "active series", "growth %", etc.
   ============================================================================================================ */

USE FavoritaRetailBI;
GO

/* ---------------------------------------------------------------------------------------- vw_ExecutiveOverview
   Business question: "Give me the 30-second state of the business" - one row, the numbers Page 1's KPI cards
   bind to directly. active_series_count excludes dormant/never-sold (Phase 3's rule_zero definition) because
   those series are always forecast at 0 and have nothing to review. forecast_model_rmsle / baseline_rmsle are
   the mean across Phase 4's five validation folds, read from FactModelPerformance (never recomputed here). */
CREATE OR ALTER VIEW dbo.vw_ExecutiveOverview AS
SELECT
    (SELECT SUM(predicted_sales) FROM dbo.FactForecast)                                                   AS total_forecasted_sales,
    (SELECT SUM(predicted_sales) FROM dbo.FactForecast) / 16.0                                             AS average_daily_forecast,
    (SELECT COUNT(*) FROM dbo.DimStore)                                                                    AS store_count,
    (SELECT COUNT(*) FROM dbo.FactDemandRisk WHERE activity_status NOT IN (N'dormant', N'never sold'))     AS active_series_count,
    (SELECT COUNT(*) FROM dbo.FactDemandRisk)                                                              AS total_series_count,
    (SELECT COUNT(*) FROM dbo.FactDemandRisk WHERE risk_category IN (N'High', N'Critical'))                AS high_critical_risk_count,
    (SELECT COUNT(*) FROM dbo.FactDemandRisk WHERE action_priority = N'P1 - Immediate review')              AS p1_count,
    (SELECT AVG(demand_risk_score) FROM dbo.FactDemandRisk)                                                AS average_risk_score,
    (SELECT AVG(model_rmsle)    FROM dbo.FactModelPerformance)                                              AS forecast_model_rmsle,
    (SELECT AVG(baseline_rmsle) FROM dbo.FactModelPerformance)                                              AS baseline_rmsle;
GO

/* ----------------------------------------------------------------------------------------- vw_StoreRiskSummary
   Business question: "Which stores need the most attention, and how much demand do they represent?" - the
   Page-1 "top stores by risk" visual and Page-3 store view both read from this. largest_growth_pct /
   largest_decline_pct are computed only over non-sparse-history series in that store, matching the Phase 5
   leaderboard rule (a jump from 0.02 to 0.3 units/day is not a meaningful "largest increase"). */
CREATE OR ALTER VIEW dbo.vw_StoreRiskSummary AS
SELECT
    s.store_nbr, s.city, s.state, s.store_type, s.cluster,
    SUM(r.forecast_16d_total)                                                          AS total_forecast_demand,
    COUNT(*)                                                                            AS series_count,
    SUM(CASE WHEN r.risk_category IN (N'High', N'Critical') THEN 1 ELSE 0 END)          AS high_critical_count,
    SUM(CASE WHEN r.action_priority = N'P1 - Immediate review' THEN 1 ELSE 0 END)       AS p1_count,
    AVG(r.demand_risk_score)                                                            AS average_risk_score,
    MAX(CASE WHEN r.sparse_history = 0 THEN r.forecast_growth_pct END)                  AS largest_growth_pct,
    MIN(CASE WHEN r.sparse_history = 0 THEN r.forecast_growth_pct END)                  AS largest_decline_pct
FROM dbo.FactDemandRisk r
JOIN dbo.DimStore s ON s.store_nbr = r.store_nbr
GROUP BY s.store_nbr, s.city, s.state, s.store_type, s.cluster;
GO

/* ---------------------------------------------------------------------------------------- vw_FamilyRiskSummary
   Business question: "Which product families carry the most demand risk, portfolio-wide?" - feeds Page 1's
   "top families" visual and Page 3's family-level breakdown. average_growth_pct excludes sparse-history series
   for the same reason as vw_StoreRiskSummary. */
CREATE OR ALTER VIEW dbo.vw_FamilyRiskSummary AS
SELECT
    p.family,
    SUM(r.forecast_16d_total)                                                           AS total_forecast_demand,
    COUNT(*)                                                                             AS series_count,
    AVG(CASE WHEN r.sparse_history = 0 THEN r.forecast_growth_pct END)                   AS average_growth_pct,
    AVG(r.demand_risk_score)                                                             AS average_risk_score,
    SUM(CASE WHEN r.risk_category IN (N'High', N'Critical') THEN 1 ELSE 0 END)           AS high_critical_count,
    SUM(CASE WHEN r.action_priority = N'P1 - Immediate review' THEN 1 ELSE 0 END)        AS p1_count
FROM dbo.FactDemandRisk r
JOIN dbo.DimProductFamily p ON p.family = r.family
GROUP BY p.family;
GO

/* -------------------------------------------------------------------------------------- vw_HighPriorityActions
   Business question: "What exactly should a planner look at first, today?" - the literal row source for
   Page 4's action queue. Power BI applies the default sort (demand_risk_score desc within P1); every row here
   is already P1 by definition, so the view itself needs no further filter. */
CREATE OR ALTER VIEW dbo.vw_HighPriorityActions AS
SELECT
    r.action_priority, r.store_nbr, s.city, s.state, r.family,
    r.forecast_16d_total   AS forecast_demand,
    r.historical_28d_avg   AS historical_demand_28d,
    r.forecast_growth_pct  AS growth_pct,
    r.demand_risk_score, r.risk_category, r.demand_surge_risk, r.demand_decline_risk,
    r.forecast_uncertainty, r.recommended_action, r.priority_score
FROM dbo.FactDemandRisk r
JOIN dbo.DimStore s ON s.store_nbr = r.store_nbr
WHERE r.action_priority = N'P1 - Immediate review';
GO

/* ------------------------------------------------------------------------------------------- vw_ForecastTrend
   Business question: "What does total expected demand look like day by day over the next 16 days?" - the
   Page-1/Page-2 daily trend line. One row per forecast date (16 rows). */
CREATE OR ALTER VIEW dbo.vw_ForecastTrend AS
SELECT
    f.[date],
    d.day_name,
    d.is_weekend,
    MIN(f.forecast_horizon)                                                    AS forecast_horizon,
    SUM(f.predicted_sales)                                                     AS total_forecast,
    SUM(CASE WHEN f.onpromotion > 0 THEN f.predicted_sales ELSE 0 END)         AS promo_forecast,
    SUM(CASE WHEN f.onpromotion = 0 THEN f.predicted_sales ELSE 0 END)         AS non_promo_forecast,
    COUNT(DISTINCT CASE WHEN f.onpromotion > 0 THEN CONCAT(f.store_nbr, N'|', f.family) END) AS series_on_promo
FROM dbo.FactForecast f
JOIN dbo.DimDate d ON d.[date] = f.[date]
GROUP BY f.[date], d.day_name, d.is_weekend;
GO
