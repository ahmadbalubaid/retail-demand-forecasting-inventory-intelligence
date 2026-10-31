# Reproducibility and release scope

This repository is the public portfolio release of the project, not a dump of the full development workspace.

## Included
- Four analysis notebooks covering EDA, feature engineering, forecasting, and the demand-risk engine.
- The shared `favorita.py` utilities available in the final supplied archive.
- Compact feature metadata and a 2,000-row modeling-table sample.
- Final forecast and demand-risk outputs.
- SQL Server schema, load scripts, analytical views, business queries, and star-schema CSVs.
- The final Power BI PBIX plus editable PBIP/PBIR semantic-model source.
- Dashboard screenshots and final validation evidence.

## Intentionally excluded
- The 117 MB raw `train.csv` and other source data that can be obtained from Kaggle.
- Heavy modeling-table shards, caches, and trained model binaries.
- Historical build screenshots and superseded documentation.

## Important source note
The Phase 4 forecasting notebook imports a development helper module named `forecasting.py`. That helper file was referenced by the historical project documentation but was **not present in the supplied final archive**, so it is not fabricated in this public release. The executed notebook, recorded model outputs, final forecast, Power BI data, and validation evidence are preserved for review.

The final Power BI deliverable does not depend on that missing development helper: the `.pbix` is self-contained and the PBIP source uses the included dashboard-ready CSVs.
