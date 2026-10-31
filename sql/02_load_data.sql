/* ============================================================================================================
   02_load_data.sql - load workflow
   Loads the 6 star-schema CSVs (exported once, read-only, from the Phase 4/5 Python outputs - see
   phase6/build_star_schema.py) into the tables created by 01_schema.sql.

   This project's CSVs live outside the SQL Server machine (they were produced in the Python/Jupyter
   environment), so the realistic path is: copy phase6/star_schema_csv/*.csv to a folder the SQL Server service
   account can read (or a container-mounted volume), then run this script with that path substituted for
   'C:\FavoritaBI\'. BULK INSERT is used because it is the standard, fast, dependency-free way to load a flat
   file in SQL Server without a separate ETL tool - appropriate for a batch, not-real-time, portfolio pipeline
   like this one (Phase 5 is explicit that this is not a real-time system).

   Order matters: dimensions first (fact tables have FOREIGN KEY constraints against them), then facts.
   ============================================================================================================ */

USE FavoritaRetailBI;
GO

DECLARE @LoadPath NVARCHAR(260) = N'C:\FavoritaBI\';   -- <-- point this at wherever phase6/star_schema_csv was copied

TRUNCATE TABLE dbo.FactForecast;
TRUNCATE TABLE dbo.FactDemandRisk;
TRUNCATE TABLE dbo.FactModelPerformance;
DELETE FROM dbo.DimDate;
DELETE FROM dbo.DimStore;
DELETE FROM dbo.DimProductFamily;
GO

BULK INSERT dbo.DimStore
FROM 'C:\FavoritaBI\DimStore.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);

BULK INSERT dbo.DimProductFamily
FROM 'C:\FavoritaBI\DimProductFamily.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);

BULK INSERT dbo.DimDate
FROM 'C:\FavoritaBI\DimDate.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);

BULK INSERT dbo.FactForecast
FROM 'C:\FavoritaBI\FactForecast.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);

BULK INSERT dbo.FactDemandRisk
FROM 'C:\FavoritaBI\FactDemandRisk.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);

BULK INSERT dbo.FactModelPerformance
FROM 'C:\FavoritaBI\FactModelPerformance.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);
GO

/* ---------------------------------------------------------------------------------------------- load checks
   Mirrors the reconciliation checklist in phase6/reconciliation/reconciliation_checklist.md - run this block
   right after loading and compare every row to the documented Python figure before trusting the database. */
SELECT 'DimStore'            AS table_name, COUNT(*) AS row_count FROM dbo.DimStore
UNION ALL SELECT 'DimProductFamily',        COUNT(*) FROM dbo.DimProductFamily
UNION ALL SELECT 'DimDate',                 COUNT(*) FROM dbo.DimDate
UNION ALL SELECT 'FactForecast',            COUNT(*) FROM dbo.FactForecast
UNION ALL SELECT 'FactDemandRisk',          COUNT(*) FROM dbo.FactDemandRisk
UNION ALL SELECT 'FactModelPerformance',    COUNT(*) FROM dbo.FactModelPerformance;
-- expected: DimStore 54 | DimProductFamily 33 | DimDate 1,704 | FactForecast 28,512 | FactDemandRisk 1,782 | FactModelPerformance 5

SELECT risk_category, COUNT(*) AS series, action_priority, COUNT(*) OVER (PARTITION BY action_priority) AS priority_total
FROM dbo.FactDemandRisk
GROUP BY risk_category, action_priority
ORDER BY risk_category;
-- expected totals: Low 537 | Medium 941 | High 286 | Critical 18  ||  P1 123 | P2 1,122 | P3 537
GO
