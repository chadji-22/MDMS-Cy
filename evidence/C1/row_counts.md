# C1 — Large data set: parameters, pipeline, row counts

[project.pdf §IV p.12: two data sets, a small one to check the implementation and a large one "of the order of
thousands of rows" to present the system; producing it is part of the grade]

## Where and how big
- **Server:** the course database `ichara09` on `mssql.cs.ucy.ac.cy` (SQL Server 2022), by Ioannis's decision of
  22/11/2026 (no local SQL Server on this PC). Its caps are **data 27 MB, log 12 MB**, so the size was **measured, not guessed**:
  - trial `sp_GenerateSyntheticData(@consumers = 2, @days = 2, @chunk_meters = 2)` → 1,532 readings, +0.55 MB in
    `METER_READING` (≈ 370 bytes per reading with its indexes), 1.4 s;
  - then the C1 batch below, sized to leave ≥ 2.5 MB free for the team and the test runs.
- **Generator call (batch SYN2):** `@consumers = 8, @days = 2, @seed = 342, @chunk_meters = 2` (script `c1_large_set.sql`,
  output `c1_output.txt`). Each synthetic consumer gets a premise, an ACTIVE meter with 3 approved certificates, 15-minute
  readings (1.8.0, 1.8.1, 1.8.2, 32.7.0; 2.8.0 for prosumers; currents for three-phase), final history and a raw last day.
- On a server without the cap the same script scales by changing `@consumers` / `@days` (≈ 383–437 readings per meter-day).

## Pipeline on the large set (raw day 2026-11-21), all steps OK
| Step | Result | ms |
|---|---|---:|
| `sp_GenerateSyntheticData` | 6,508 readings, 26 aggregates, 4 transformers | 1,557 |
| `sp_RunVEE` (raw day) | 10 meters, 0 failed: 4,008 VALID, 0 SUSPECT, 18 ESTIMATED (gaps filled) | 1,593 |
| `sp_FinalizeReadings` (raw day) | 10 / 10 meters FINALIZED; all 4,026 readings of the day final (4,008 VALID + 18 ESTIMATED); meter DAY aggregates built | 2,199 |
| `sp_BuildTransformerAggregates` (raw day) | 1,152 quarter-hour + 12 DAY transformer aggregates | 485 |
| `sp_RefreshTransformerState` (whole tree) | 50 state rows at 2026-11-21 23:45 | 185 |

## Row counts (`sys.partitions`, after the pipeline)
| Table | Before C1 | After C1 | Added |
|---|---:|---:|---:|
| METER_READING | 9,601 | **16,127** | 6,526 |
| AGGREGATE | 4,707 | **5,929** | 1,222 |
| TELEMETRY_PACKET | 2,349 | 2,349 | 0 |
| AUDIT_LOG | 828 | 899 | 71 |
| DOCUMENT | 58 | 82 | 24 |
| EVENT | 60 | 60 | 0 |
| TRANSFORMER_CURRENT_STATE | 34 | 50 | 16 |
| USER_ACCOUNT | 32 | 40 | 8 |
| TRANSFORMER | 21 | 25 | 4 |
| METER | 17 | 25 | 8 |
| PREMISE | 16 | 24 | 8 |
| WORK_ORDER | 30 | 30 | 0 |

("Before" already includes the 2 × 2 trial batch SYN1 and the small set of `import.sql` + test runs.)
Data file after C1: 24.38 MB used of 27 MB; log 1.20 MB of 12 MB.

## Honest limits
- 16 thousand readings meet "of the order of thousands of rows", but it is not a stress-size set. The course DB cannot hold
  more; `REPORT.md`'s plan of ~29 million readings needs a local server.
- A rebuild of `ichara09` (`build_all.sql`) removes this set; rerun `c1_large_set.sql` (about 6 s) afterwards.
