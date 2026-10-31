# Source lineage and chronology

All 27 user-supplied files were inspected. Machine-readable audit includes byte sizes, SHA-256, tabular columns, inferred CSV types, null counts, exact duplicate counts and date coverage. Parquet metadata files preserve original physical/logical types; CSV-converted inspection types are inferred. Notebooks were parsed with their saved text/HTML outputs; HTML exports and Python code were read for methods and provenance. Notebook 01 and 01_1 have identical hashes and are redundant.

- `01_EDA` establishes panel, geography, inactivity and initial decisions; CSV activity status is a final-origin snapshot, not a current inventory status.
- `02_Feature_Engineering` / favorita.py / dictionary / model_config establish origin-safe features, calendar availability, coded lookups, five folds and embargo. Training shards and 2,000-row sample were profiled for provenance only and are not imported.
- `03_Model_Forecasting` supersedes README.md's earlier “no model trained” statement. README_1 confirms the blend and validation. Saved notebook table and executive summary supply rounded candidate means, selected fold scores and four gain shares. These are documented fixed results, not independently rerun experiments.
- `04_Inventory_Risk_Engine` and risk_engine_config supersede README_1's “risk phase not started” statement. The final risk CSV is authoritative for risk components, classifications, priorities and recommendations.
- `final_forecast.parquet` supplies every daily prediction and promotion count. `test_features.parquet` maps dates/store/family to submission IDs for a one-to-one audit. Submission predictions reconcile by ID, not incidental row order.
- `inventory_risk_engine.csv` supplies the snapshot. Store and family dimensions come from its actual metadata and source lookups. Family codes are preserved.
- `high_priority_actions` and the two risk summaries are reconciled supporting extracts. They are not loaded as extra facts because this would duplicate metrics.
- `store_family_activity_status` agrees with risk activity labels. Some history windows differ (90-day EDA versus later origin features); these are not interchangeable historical observations.

The two available training shards cover only part of the documented modeling table. Full retraining also references forecasting.py and model/cache outputs not supplied. Neither is needed for this report's refresh. No absent model binaries, row-level validation predictions or complete feature importance tables were fabricated.

Power Query imports the prepared compact tables. Original filenames, schema profiles, configuration copies, source hashes and rebuild scripts maintain traceability. Native model data types are specified in Data_Dictionary.csv.

Source consistency note: notebook prose says the four leading feature gains total 95.3%, but its listed shares (54.1%, 26.4%, 7.6%, 5.5%) sum to 93.6%. The report displays the four documented individual shares and does not repeat the inconsistent total.

## Final implementation versus earlier design artifacts

Earlier Phase 6 planning files in the wider project history describe a 4-page / 20-measure Power BI specification and a smaller SQL-oriented semantic design. The delivered PBIX/PBIP in this package supersedes that planning state. The final implementation contains **7 business pages plus one hidden tooltip, 41 DAX measures, 11 tables and 7 active single-direction relationships**. The earlier SQL scripts remain useful as a reconciled analytical/reference layer and define **5 analytical views**, not four.

A historical narrative also described the top-10 forecast-volume stores and top-10 High/Critical-count stores as having “zero overlap.” With deterministic store-number tie-breaking that displayed top ten has zero overlap, but the High/Critical ranking has a six-way tie at **9 cases** for positions 7–12 (Stores 14, 20, 22, 32, 43 and 48); Store 48 is also a top-volume store. Therefore the durable business conclusion is: **the highest-volume and highest-risk stores are largely different, with only limited overlap depending on tie handling**. At product-family level, CLEANING is the only overlap between the top-10 volume and top-10 High/Critical lists.
