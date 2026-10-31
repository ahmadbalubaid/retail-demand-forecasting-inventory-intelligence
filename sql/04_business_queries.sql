/* ============================================================================================================
   04_business_queries.sql - standalone business queries
   Each query is self-contained (no dependency on 03_views.sql) and is preceded by the business question it
   answers. These are ad-hoc / analyst queries, not Power BI's data source - the four views cover that.
   ============================================================================================================ */

USE FavoritaRetailBI;
GO

/* ------------------------------------------------------------------------------------------------------- Q1
   Business question: "Which 10 stores carry the most forecast demand over the next 16 days?" - sizes the
   stores that matter most operationally, independent of risk. */
SELECT TOP 10
    r.store_nbr, s.city, s.state,
    SUM(r.forecast_16d_total) AS forecast_demand,
    RANK() OVER (ORDER BY SUM(r.forecast_16d_total) DESC) AS demand_rank
FROM dbo.FactDemandRisk r
JOIN dbo.DimStore s ON s.store_nbr = r.store_nbr
GROUP BY r.store_nbr, s.city, s.state
ORDER BY forecast_demand DESC;

/* ------------------------------------------------------------------------------------------------------- Q2
   Business question: "Which 10 product families carry the most forecast demand?" - the categories that would
   move the P&L most if the forecast is materially wrong. */
SELECT TOP 10
    family,
    SUM(forecast_16d_total) AS forecast_demand,
    RANK() OVER (ORDER BY SUM(forecast_16d_total) DESC) AS demand_rank
FROM dbo.FactDemandRisk
GROUP BY family
ORDER BY forecast_demand DESC;

/* ------------------------------------------------------------------------------------------------------- Q3
   Business question: "Which stores have the most P1 - Immediate review cases?" - where a regional or store-
   level review (rather than one-off item review) is likely to be worth scheduling. */
SELECT
    r.store_nbr, s.city, s.state,
    COUNT(*) AS p1_count,
    COUNT(*) * 1.0 / (SELECT COUNT(*) FROM dbo.FactDemandRisk r2 WHERE r2.store_nbr = r.store_nbr) AS p1_share_of_store
FROM dbo.FactDemandRisk r
JOIN dbo.DimStore s ON s.store_nbr = r.store_nbr
WHERE r.action_priority = N'P1 - Immediate review'
GROUP BY r.store_nbr, s.city, s.state
ORDER BY p1_count DESC;

/* ------------------------------------------------------------------------------------------------------- Q4
   Business question: "Which families have the highest average demand risk?" - a family-level signal that a
   category (not just one store) needs attention, e.g. because it is structurally hard to forecast or highly
   promotional. */
SELECT TOP 10
    family,
    COUNT(*)                                                      AS series_count,
    AVG(demand_risk_score)                                        AS average_risk_score,
    SUM(CASE WHEN risk_category IN (N'High', N'Critical') THEN 1 ELSE 0 END) AS high_critical_count
FROM dbo.FactDemandRisk
GROUP BY family
ORDER BY average_risk_score DESC;

/* ------------------------------------------------------------------------------------------------------- Q5
   Business question: "Where is demand expected to increase the most?" - candidates for a replenishment
   increase. Sparse-history series are excluded (CTE) because a ratio computed off a near-zero base is not a
   meaningful "largest increase", exactly as in the Phase 5 leaderboard. */
WITH Reliable AS (
    SELECT * FROM dbo.FactDemandRisk WHERE sparse_history = 0
)
SELECT TOP 15
    store_nbr, family, forecast_growth_pct, historical_28d_avg, forecast_daily_avg, promotion_days, risk_category,
    RANK() OVER (ORDER BY forecast_growth_pct DESC) AS growth_rank
FROM Reliable
ORDER BY forecast_growth_pct DESC;

/* ------------------------------------------------------------------------------------------------------- Q6
   Business question: "Where is demand expected to decline the most?" - candidates for a replenishment
   decrease / inventory rebalance. Same sparse-history exclusion as Q5. */
WITH Reliable AS (
    SELECT * FROM dbo.FactDemandRisk WHERE sparse_history = 0
)
SELECT TOP 15
    store_nbr, family, forecast_growth_pct, historical_28d_avg, forecast_daily_avg, risk_category,
    RANK() OVER (ORDER BY forecast_growth_pct ASC) AS decline_rank
FROM Reliable
ORDER BY forecast_growth_pct ASC;

/* ------------------------------------------------------------------------------------------------------- Q7
   Business question: "Which High/Critical-risk cases also represent a lot of forecast volume?" - the
   combinations where getting it wrong has the largest operational impact; "high volume" = top tercile of
   forecast_16d_total among active series, computed with NTILE so the threshold is derived from the data, not
   hard-coded. */
WITH ActiveVolume AS (
    SELECT store_nbr, family, forecast_16d_total, risk_category,
           NTILE(3) OVER (ORDER BY forecast_16d_total) AS volume_tercile
    FROM dbo.FactDemandRisk
    WHERE activity_status NOT IN (N'dormant', N'never sold')
)
SELECT store_nbr, family, forecast_16d_total, risk_category
FROM ActiveVolume
WHERE volume_tercile = 3 AND risk_category IN (N'High', N'Critical')
ORDER BY forecast_16d_total DESC;

/* ------------------------------------------------------------------------------------------------------- Q8
   Business question: "How much of the surge risk we are seeing is explained by promotions?" - separates
   promotion-driven spikes (planned, expected) from organic surges (unplanned, worth a closer look). */
SELECT
    CASE WHEN promotion_days >= 8 THEN N'Promotion-heavy (8+ of 16 days)' ELSE N'Low/no promotion' END AS promo_band,
    COUNT(*)                                              AS series_count,
    AVG(demand_surge_risk)                                AS avg_surge_risk,
    SUM(CASE WHEN demand_surge_risk >= 50 THEN 1 ELSE 0 END) AS high_surge_count
FROM dbo.FactDemandRisk
GROUP BY CASE WHEN promotion_days >= 8 THEN N'Promotion-heavy (8+ of 16 days)' ELSE N'Low/no promotion' END;

/* ------------------------------------------------------------------------------------------------------- Q9
   Business question: "How much of the portfolio is even active, and how is risk distributed between active
   and dormant/never-sold series?" - a sanity/coverage check as much as a business one: dormant series should
   show up as low risk and low priority, never high. */
SELECT
    CASE WHEN activity_status IN (N'dormant', N'never sold') THEN N'Inactive (dormant / never sold)' ELSE N'Active' END AS series_state,
    COUNT(*)                                                          AS series_count,
    AVG(demand_risk_score)                                            AS average_risk_score,
    SUM(CASE WHEN action_priority = N'P1 - Immediate review' THEN 1 ELSE 0 END) AS p1_count,
    SUM(forecast_16d_total)                                           AS forecast_demand
FROM dbo.FactDemandRisk
GROUP BY CASE WHEN activity_status IN (N'dormant', N'never sold') THEN N'Inactive (dormant / never sold)' ELSE N'Active' END;
GO
