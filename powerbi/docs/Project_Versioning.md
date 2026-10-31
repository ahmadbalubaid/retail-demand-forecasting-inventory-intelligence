# Project versioning and authoritative implementation

## Final Power BI implementation (authoritative)

- 7 visible business pages + 1 hidden Risk Snapshot Tooltip page
- 11 semantic-model tables
- 7 active single-direction relationships
- 41 DAX measures
- Executive Overview saved as the opening page
- Action Priority & Decision Support saved with P1 + P2 selected; P3 remains available
- Final fresh-launch verification passed on 24 October 2026

## Earlier Phase 6 design artifacts

Earlier project documents describe an initial 4-page / 20-measure Power BI specification based on a smaller SQL-oriented star-schema design. Keep those files only for design lineage or archive purposes. They should not be presented as the final report architecture.

The initial SQL layer itself contains **5 analytical views** (`vw_ExecutiveOverview`, `vw_StoreRiskSummary`, `vw_FamilyRiskSummary`, `vw_HighPriorityActions`, `vw_ForecastTrend`) and 9 business queries. Some older prose says “4 views”; that count is outdated.

## Store-volume versus store-risk wording

Avoid the unconditional claim that the two top-10 store lists have “zero overlap.” The High/Critical count ranking has a six-way tie at 9 cases around the top-10 cutoff, and Store 48 belongs to that tie while also being a top-volume store. Use this wording instead:

> The highest-volume and highest-risk stores are largely different, with only limited overlap depending on tie handling.

At product-family level, CLEANING is the only overlap between the top-10 forecast-volume and top-10 High/Critical-count lists.

## Feature-importance wording

The four documented LightGBM gain shares are 54.1%, 26.4%, 7.6% and 5.5%, which sum to **93.6%**. Do not repeat the older notebook prose stating 95.3%. The final dashboard correctly shows the individual shares only.
