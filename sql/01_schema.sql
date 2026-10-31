/* ============================================================================================================
   Phase 6 - SQL Server analytics layer
   Retail Demand Forecasting & Inventory Intelligence (Corporacion Favorita)
   01_schema.sql - database, tables, primary keys, foreign keys, indexes

   Design notes (read this before the DDL - it's the "explain it in an interview" summary):
   - A small star schema: 3 dimensions (DimStore, DimProductFamily, DimDate) and 2 fact tables at two different
     grains sharing those dimensions (a "fact constellation", the natural shape once you have both a daily
     forecast and a per-series risk score) plus one tiny reference table for the model's own validation score.
   - Natural keys throughout (store_nbr, family, date) - no surrogate integer keys. With 54 stores, 33 families
     and a handful of dates this stays small and every join reads the way a planner already thinks about the
     business ("store 26, BEVERAGES, 2017-08-20"), which is deliberately simpler than adding surrogate keys that
     buy nothing at this scale.
   - FactForecast is the daily grain (one row per date x store x family, 28,512 rows for the 16-day forecast).
   - FactDemandRisk is the per-series grain (one row per store x family, 1,782 rows) - Phase 5's risk output.
     It is NOT additive across dates (it already summarises 16 days), so it is deliberately a separate fact
     table rather than columns bolted onto FactForecast, which would repeat the same risk score on 16 rows.
   - Every value in every table is loaded as produced by the Python pipeline (Phases 3-5) - this script creates
     structure only; no forecast or risk figure is computed, re-derived or changed here.
   ============================================================================================================ */

IF DB_ID(N'FavoritaRetailBI') IS NULL
    CREATE DATABASE FavoritaRetailBI;
GO
USE FavoritaRetailBI;
GO

/* ---------------------------------------------------------------------------------------------- dimensions */

IF OBJECT_ID(N'dbo.DimStore', N'U') IS NOT NULL DROP TABLE dbo.DimStore;
GO
CREATE TABLE dbo.DimStore (
    store_nbr   SMALLINT      NOT NULL,
    city        NVARCHAR(50)  NOT NULL,
    state       NVARCHAR(50)  NOT NULL,
    store_type  NVARCHAR(5)   NOT NULL,          -- Favorita's store type code (A-E)
    cluster     TINYINT       NOT NULL,          -- Favorita's store cluster (1-17)
    CONSTRAINT PK_DimStore PRIMARY KEY CLUSTERED (store_nbr)
);
GO

IF OBJECT_ID(N'dbo.DimProductFamily', N'U') IS NOT NULL DROP TABLE dbo.DimProductFamily;
GO
CREATE TABLE dbo.DimProductFamily (
    family      NVARCHAR(40)  NOT NULL,
    CONSTRAINT PK_DimProductFamily PRIMARY KEY CLUSTERED (family)
);
GO

IF OBJECT_ID(N'dbo.DimDate', N'U') IS NOT NULL DROP TABLE dbo.DimDate;
GO
CREATE TABLE dbo.DimDate (
    [date]        DATE         NOT NULL,
    [year]        SMALLINT     NOT NULL,
    quarter       TINYINT      NOT NULL,
    [month]       TINYINT      NOT NULL,
    month_name    NVARCHAR(10) NOT NULL,
    week          TINYINT      NOT NULL,         -- ISO week number
    [day]         TINYINT      NOT NULL,
    day_of_week   TINYINT      NOT NULL,         -- 1 = Monday .. 7 = Sunday
    day_name      NVARCHAR(10) NOT NULL,
    is_weekend    BIT          NOT NULL,
    CONSTRAINT PK_DimDate PRIMARY KEY CLUSTERED ([date])
);
GO

/* ---------------------------------------------------------------------------------------------- fact tables */

IF OBJECT_ID(N'dbo.FactForecast', N'U') IS NOT NULL DROP TABLE dbo.FactForecast;
GO
CREATE TABLE dbo.FactForecast (
    [date]              DATE          NOT NULL,
    store_nbr           SMALLINT      NOT NULL,
    family              NVARCHAR(40)  NOT NULL,
    predicted_sales     DECIMAL(12,4) NOT NULL,  -- Phase 4's forecast, units, never rounded, clipped at 0 upstream
    onpromotion         SMALLINT      NOT NULL,  -- items in that Store x Family on promotion that day
    forecast_horizon    TINYINT       NOT NULL,  -- 1..16 days ahead of the 2017-08-15 origin
    activity_status     NVARCHAR(15)  NOT NULL,  -- regular / intermittent / dormant / never sold (from Phase 2/3)
    CONSTRAINT PK_FactForecast PRIMARY KEY CLUSTERED ([date], store_nbr, family),
    CONSTRAINT FK_FactForecast_DimDate    FOREIGN KEY ([date])    REFERENCES dbo.DimDate ([date]),
    CONSTRAINT FK_FactForecast_DimStore   FOREIGN KEY (store_nbr) REFERENCES dbo.DimStore (store_nbr),
    CONSTRAINT FK_FactForecast_DimFamily  FOREIGN KEY (family)    REFERENCES dbo.DimProductFamily (family),
    CONSTRAINT CK_FactForecast_sales_nonneg CHECK (predicted_sales >= 0),
    CONSTRAINT CK_FactForecast_horizon      CHECK (forecast_horizon BETWEEN 1 AND 16)
);
GO
CREATE NONCLUSTERED INDEX IX_FactForecast_Store  ON dbo.FactForecast (store_nbr) INCLUDE (predicted_sales, [date]);
CREATE NONCLUSTERED INDEX IX_FactForecast_Family ON dbo.FactForecast (family)    INCLUDE (predicted_sales, [date]);
GO

IF OBJECT_ID(N'dbo.FactDemandRisk', N'U') IS NOT NULL DROP TABLE dbo.FactDemandRisk;
GO
CREATE TABLE dbo.FactDemandRisk (
    store_nbr                  SMALLINT       NOT NULL,
    family                     NVARCHAR(40)   NOT NULL,
    activity_status            NVARCHAR(15)   NOT NULL,
    forecast_16d_total         DECIMAL(14,4)  NOT NULL,
    forecast_daily_avg         DECIMAL(12,4)  NOT NULL,
    forecast_max_day           DECIMAL(12,4)  NOT NULL,
    forecast_min_day           DECIMAL(12,4)  NOT NULL,
    forecast_std               DECIMAL(12,4)  NOT NULL,
    promotion_days             TINYINT        NOT NULL,   -- of 16
    historical_28d_avg         DECIMAL(12,4)  NOT NULL,
    historical_91d_avg         DECIMAL(12,4)  NOT NULL,
    forecast_growth_pct        DECIMAL(10,4)  NOT NULL,   -- (forecast_daily_avg - historical_28d_avg) / floor(historical_28d_avg, 1.0)
    sparse_history              BIT           NOT NULL,   -- historical_28d_avg < 1 unit/day -> excluded from growth/decline leaderboards
    volatility                 DECIMAL(10,4)  NOT NULL,   -- historical coefficient of variation, 28 days
    demand_surge_risk          DECIMAL(6,1)   NOT NULL,   -- 0-100
    demand_decline_risk        DECIMAL(6,1)   NOT NULL,   -- 0-100
    demand_volatility_risk     DECIMAL(6,1)   NOT NULL,   -- 0-100
    forecast_uncertainty_score DECIMAL(6,1)   NOT NULL,   -- 0-100
    forecast_uncertainty       NVARCHAR(10)   NOT NULL,   -- 'High' / 'Normal'
    demand_risk_score          DECIMAL(6,1)   NOT NULL,   -- 0-100, the overall score
    risk_category               NVARCHAR(10)  NOT NULL,   -- Low / Medium / High / Critical
    volume_tier                 NVARCHAR(10)  NOT NULL,   -- Low / Medium / High tercile of forecast_16d_total (active series)
    action_priority              NVARCHAR(25) NOT NULL,   -- P1 - Immediate review / P2 - Monitor / P3 - Routine
    priority_score              DECIMAL(6,1)  NOT NULL,   -- risk percentile x volume percentile x 100, for sorting within a tier
    recommended_action          NVARCHAR(200) NOT NULL,
    CONSTRAINT PK_FactDemandRisk PRIMARY KEY CLUSTERED (store_nbr, family),
    CONSTRAINT FK_FactDemandRisk_DimStore  FOREIGN KEY (store_nbr) REFERENCES dbo.DimStore (store_nbr),
    CONSTRAINT FK_FactDemandRisk_DimFamily FOREIGN KEY (family)    REFERENCES dbo.DimProductFamily (family),
    CONSTRAINT CK_FactDemandRisk_score_range CHECK (demand_risk_score BETWEEN 0 AND 100),
    CONSTRAINT CK_FactDemandRisk_category    CHECK (risk_category IN (N'Low', N'Medium', N'High', N'Critical')),
    CONSTRAINT CK_FactDemandRisk_priority    CHECK (action_priority IN (N'P1 - Immediate review', N'P2 - Monitor', N'P3 - Routine'))
);
GO
CREATE NONCLUSTERED INDEX IX_FactDemandRisk_Category ON dbo.FactDemandRisk (risk_category)   INCLUDE (demand_risk_score, store_nbr, family);
CREATE NONCLUSTERED INDEX IX_FactDemandRisk_Priority ON dbo.FactDemandRisk (action_priority)  INCLUDE (priority_score, store_nbr, family);
GO

/* Tiny reference table (5 rows: one per Phase 4 validation fold) so the Executive Overview's RMSLE KPI comes
   from a governed table, not a number typed into a DAX measure. */
IF OBJECT_ID(N'dbo.FactModelPerformance', N'U') IS NOT NULL DROP TABLE dbo.FactModelPerformance;
GO
CREATE TABLE dbo.FactModelPerformance (
    model_name      NVARCHAR(80)  NOT NULL,
    fold            NVARCHAR(5)   NOT NULL,
    model_rmsle     DECIMAL(8,4)  NOT NULL,
    baseline_rmsle  DECIMAL(8,4)  NOT NULL,
    improvement_pct DECIMAL(6,4)  NOT NULL,
    CONSTRAINT PK_FactModelPerformance PRIMARY KEY CLUSTERED (fold)
);
GO
