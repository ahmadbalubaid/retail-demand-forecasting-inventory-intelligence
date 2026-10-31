# Semantic model and filter contract

DimStore (store_nbr, 54) → DimSeries (series_key, 1,782) ← DimFamily (family_id, 33).
DimRiskCategory (4) and DimPriority (3) also filter DimSeries.
DimSeries filters FactForecast (daily, 28,512 rows) and FactInventoryRisk (origin snapshot, 1,782 rows).
DimDate (16 days) filters only FactForecast.
Every relationship is active, single direction, one-to-many. There are no fact-to-fact relationships and no many-to-many paths. The snowflaked series dimension permits severity, priority and activity filters to restrict forecast rows without duplicating risk scores across daily rows.

FactForecast grain: date × store × family. FactInventoryRisk grain: store × family at origin 2017-08-15. The unique series key is store number + pipe + source family ID. All date rows are forecast dates. No daily actual-sales fact is invented from rolling historical features.

ModelPerformance, ValidationFolds and FeatureImportance are intentionally disconnected fixed validation result tables. Store/family slicers do not recalculate model performance. Store and family RMSLE columns in the risk source are pooled validation segment diagnostics, not means of newly calculated row errors.

Scores use arithmetic averages. Forecast units sum only daily predictions. High/Critical exposure filters daily forecast rows through DimSeries; snapshot forecast totals are explicitly full-horizon measures. Promotion-associated units sum all forecast sales on promoted store-family-date rows; onpromotion is a promoted-item count, not a percentage.

Forecast growth compares full-horizon average daily forecast against historical_28d_avg, excluding inactive and sparse-history series. It is a ratio of sums, not an average of percentage changes. History indicators were captured at origin, not affected by the forecast date slicer.

Technical IDs are hidden where appropriate. Measure display folders separate forecast, risk, actions, snapshot, labels, validation and coverage. Readable DAX and per-field types are exported separately. M imports typed CSV with UTF-8 and en-US numeric/date conversion. Source missing diagnostics remain null.

No forecast fact is physically joined to the snapshot fact. Reconciliation compares grouped sums before loading. This prevents 16-fold duplication of snapshot volume.
