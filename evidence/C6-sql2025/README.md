# C6 — MDMS-Cy built and tested on the course server SQL2025 (25/11/2026)

Server `mssql.cs.ucy.ac.cy\SQL2025` (`ntheva\SQL2025`, SQL Server 2025), database `ichara09`: data capped at 27 MB,
log at 20 MB, SIMPLE recovery, RCSI on. The database also holds the lab tables (25 tables, 21 foreign keys), which must
not change. Code under test: branch `ioannis/C6-log-cap` (`commit.txt`), i.e. `io` + checkpoints during the build
(evidence/C6-logcap) + drop of MDMS-Cy objects only.

Preparation (with Ioannis's approval): Query Store cleared and turned OFF (it used 6 MB of the 27 MB quota and could grow;
data used 25.69 -> 20.00 MB). Read-only checks: no schema-bound modules, no database triggers; the only non-MDMS
procedures are the 8 SSMS diagram helpers, left alone. A local rehearsal with the same caps and 13 MB of other data
peaked at 25.6 of 27 MB.

Run (`run_on_sql2025.sh`, output `run_log.txt`; it checks the server name and the committed code, and stops at the first
failure):

| Step | Result | File |
|---|---|---|
| lab inventory before | identical to the 25/11 inventory | lab_inventory_start.txt |
| build_all.sql #1 / #2 | OK, 25 tables, 24 triggers, 118 procedures; data 20.38 MB | build1.txt, build2.txt |
| tests.sql | 82/82 | tests.txt |
| telemetry / VEE tests | 26/26 | sql_*.txt |
| select.sql | UC-01..UC-20, no error | select.txt |
| final build_all.sql | OK, data 20.00 MB of 27 MB; the database holds the import.sql demo data | build_final.txt |
| lab inventory after | identical (25 tables with the same rows, 21 FKs) | lab_inventory_after.txt |
| Query Store | OFF | run_log.txt |

Not covered on this server: the web pages (they were tested on a local SQL Server 2022, evidence/C6-integration).
