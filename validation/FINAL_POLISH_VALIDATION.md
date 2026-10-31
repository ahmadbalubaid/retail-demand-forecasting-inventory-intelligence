# Final release candidate validation

Validation date: 22 October 2026. Native Power BI Desktop PBIX and editable PBIP.

## Post-restart recovery verification — 24 October 2026 — PASS

The final polished PBIX and ZIP were located in `Downloads/the AI pROJECT` and copied back into the expected outputs locations. They were relocated, not corrupted or rebuilt. The PBIX is 1,144,626 bytes; SHA-256 `e42f5df7ce5e902abaecc598ad19dcd280b8caf18449f22678340a11e790dc86` exactly matches the validated release. Both recovered archives passed CRC checks. All 207 existing release-manifest entries matched; PBIP, report definitions, model.bim, data and documentation were complete.

The final PBIX opened successfully in a fresh Desktop process directly on **Executive Overview**, before navigation. It displayed page 1 of 8 and was first in the seven-button bottom navigator. All seven business pages rendered normally. Native navigation worked. Action Priority opened with P1/P2 checked, displaying 123 P1 and 1,122 P2; P3 was present and unchecked in the dropdown. No priority selections were changed during this recovery verification. Risk Snapshot Tooltip remains HiddenInViewMode and absent from normal navigation. Report was returned to Executive Overview without saving edits.

No report design, DAX, relationships, model, data or analytical logic changed. All reconciled results below remain unchanged. Existing 152 static passes and 23 Desktop DAX assertion passes were retained rather than rerun. No final file was corrupted or unrecoverable. The missing expected-path PBIX and ZIP were recovered intact from their relocated copies. The ZIP was updated only to include this verification evidence; the original recovered ZIP and preceding validation files were backed up outside the release folder. The Downloads originals were preserved. The 22 October launch limitation described below is now resolved by the successful 24 October launch.

Floating tooltip hover, cloud publication, mobile layouts and exports were not independently tested in this recovery pass. See RECOVERY_VERIFICATION.json for machine-readable evidence.

## Original 22 October verification record

### Opening page and saved state

**Saved opening-page checks PASS; fresh-launch rendering remains INCOMPLETE.** Executive Overview was selected and saved in Desktop before native Save As PBIX. The final PBIX was opened in a separate Desktop session without navigating to another page, but the initial attempt raised System.OutOfMemoryException. After closing saved temporary sessions while preserving recovery files, a retry reached Preparing report and did not finish rendering during verification. Closing another baseline session was blocked by automatic approval review because of possible unsaved work. A separate backup was attempted, but native input repeatedly failed with: point is over msedgewebview2.exe Chrome Legacy Window, not target window PBIDesktop.exe. The older baseline and its unsaved state were left intact. Therefore this report does not certify successful fresh-launch rendering. Resolve Desktop memory pressure, reopen the final PBIX and confirm Executive Overview before treating the release candidate as fully signed off.

Executive Overview is p01, page 1 and the first button in each of the seven business-page bottom navigators. PBIP pages.json and the native PBIX embedded pages.json both contain activePageName p01 and pageOrder beginning p01. Every report-definition JSON in the PBIX matches the final PBIP source.

Action Priority & Decision Support retains P1 + P2 as its saved slicer selection. Desktop testing showed P1 123, P2 1,122 and P3 0 in that context. P3 was manually selected and showed 537, then deselected to restore P1 + P2 before the final save. The slicer has no permanent P3 exclusion; DimPriority and FactInventoryRisk retain P3. P1 + P2 context contains 1,245 series.

Risk Snapshot Tooltip remains HiddenInViewMode with Tooltip page type. It is excluded from the normal seven-page navigator. Desktop Format > General > Tooltips explicitly showed Risk Snapshot Tooltip assigned to the risk matrix. Hidden pages remain accessible in Desktop editing tabs, as expected.

## Analytical integrity and verification

- 152/152 static checks passed after the final native save and portable-source reset.
- 23/23 DAX assertions returned TRUE in the Desktop engine. The included Final_Polish_Desktop_Validation.dax checks all 41 measures for errors, reconciled results, date context and P1 + P2 context.
- All 41 DAX expressions and model format strings match the original validated model.
- All seven relationships match the original, with valid unique dimension keys, referential integrity and single-direction filtering.
- All 11 prepared CSV data files have identical SHA-256 hashes to the original release. No model retraining, recalculation of source predictions or analytical logic changes.
- All seven business pages were rendered and visually reviewed in Desktop. Both ordered risk bars display Low, Medium, High, Critical; forecast cards show 12.56M; exposure shows 658.7K; RMSLE displays .3942 and .4693.
- Seven equal-sized native navigators were checked. Desktop keyboard activation navigated successfully across the reviewed pages. No broken field bindings or out-of-canvas visuals were found.
- Filters, priority selection and matrix cross-filtering were tested and cleared/restored before final save. No unresolved broken visuals, navigation, slicers or filters were identified in the tested scope.
- Tooltip assignment and hidden state passed. A floating tooltip hover was not independently exercised by the automation interface; no blanket claim of every hover interaction is made.
- DimDate is marked as the date table, date is its key, month_name sorts by month and automatic date tables remain disabled.
- PBIX ZIP CRC passed, embedded DataModel exists, and every report-definition JSON matches the final source. The PBIX was created through native Desktop Save As, not by rewriting its archive.

## Reconciled results — unchanged

| Metric | Validated value |
|---|---:|
| Total forecasted units | 12,563,212.295 |
| Stores | 54 |
| Product families | 33 |
| Store × Product Family series | 1,782 |
| Daily forecast records | 28,512 |
| Low | 537 |
| Medium | 941 |
| High | 286 |
| Critical | 18 |
| High + Critical | 304 |
| P1 | 123 |
| P2 | 1,122 |
| P3 | 537 |
| Average risk score | 48.657 |
| High/Critical forecast exposure | 658,722.289 units |
| High/Critical exposure share | approximately 5.24% |
| Ensemble RMSLE | 0.3942 |
| Baseline RMSLE | 0.4693 |
| Relative improvement | approximately 16.0% |

## Release and portability

The self-contained PBIX includes imported data and opens without source files. Before opening/refreshing the portable PBIP source, run Configure_Data_Path.ps1 to resolve DataRoot to the extracted data folder. The source-controlled model parameter uses __SET_DATA_ROOT__; this is intentional and does not change the native PBIX. Personal absolute source paths were removed from portable authoring files. Machine-specific .pbi session/cache files and the original baseline PBIX are excluded from the complete ZIP. The original release and temporary backups remain outside this release package.

Cloud publication, Power BI Service, mobile layouts and export behavior were not tested. Leading Stores/Families titles deliberately avoid promising ten simultaneously visible bars at small canvas zoom. No further design or analytical changes were made during final opening-page verification.

Evidence: final_static_checks.json, pbix_verification.json, Final_Polish_Desktop_Validation.dax, reconciled_metrics.json and release_manifest.json. Historical validation files retain their original scope and dates; this report describes the final polish pass.
