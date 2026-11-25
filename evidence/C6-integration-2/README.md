# C6 — proof of ioannis/integration-2 (25/11/2026)

`ioannis/integration-2` = Kostis's `68a26f9` (ODBC connection pooling off in `sources/src/Db.php`) merged with
`ioannis/C6-log-cap` (build checkpoints, drop of MDMS-Cy objects only, SQL2025 evidence). Merge commit `92f4fe0`; the SQL
files are identical to the code that passed on the SQL2025 course server (evidence/C6-sql2025) and `sources/` is
identical to Kostis's branch. Run with `prove.sh` on the local SQL Server 2022 container, fresh database `mdms2`.

| Check | Result |
|---|---|
| build_all.sql x2 | OK, 25 tables, 24 triggers, 118 procedures, 15 indexes |
| tests.sql / telemetry+VEE / select.sql | 82/82 / 26/26 / UC-01..20 |
| smoke / consumer_pages (WRITE=1) / accounts | 23/23 / 63/63 / 47/47 |
| market_dso_tso read-only / WRITE=1 | 152/152 / 160/160 |
| errors_test, db_integration / audit_pages | passed / 116 calls checked, 0 errors |
| role crawl, 59 pages x 8 roles + anonymous | 531 requests, 0 failed |
| detail pages with real ids | 11/11 (first run 10/11: the test used technician id 27, which exists only after extra test runs; now id 9 from import.sql) |
| application error log | 0 entries |

Kostis's pooling fix cannot be shown failing here (the container runs Linux, where the Windows ODBC pool issue does not
occur); his commit message has his Windows measurements.
