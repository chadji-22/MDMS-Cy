# C6 — the build on the course servers' log cap (24-25/11/2026)

**Problem.** Both course SQL Servers cap the transaction log: `mssql.cs.ucy.ac.cy` (SQL Server 2022, the target) at
12 MB, `mssql.cs.ucy.ac.cy\SQL2025` at 20 MB; data is capped at 27 MB; recovery model SIMPLE, RCSI on. A rehearsal with
these caps on a local SQL Server 2022 showed `build_all.sql` failing with error 9002 ("transaction log is full due to
ACTIVE_TRANSACTION"). The procedures catch the error (e.g. one telemetry packet counted under `errors`, a meter-day not
finalized), so the build goes on and stops later at `sp_BuildTransformerAggregates` ("readings that are not final").

**Cause (measured, `probe_ranking_populated.txt`, `runs/probe_build*.txt`).** No single statement is too large: with a
checkpoint before each call the whole build needs 9-10 MB of log (empty database) or 13-14 MB (populated re-run); the
biggest single calls are `sp_RunVEE` (up to 5.9 MB) and `sp_FinalizeReadings` (1.4-1.6 MB). Without explicit checkpoints
the log of many small transactions piles up faster than the automatic checkpoint frees it (SIMPLE recovery reuses the
log only after a checkpoint).

**Change (this branch).** `BEGIN TRY CHECKPOINT; END TRY BEGIN CATCH END CATCH;` at the start of each of the 10 steps
of `import.sql`, at the top of its 5 loop bodies, and once in `create.sql` after the drop. No procedure, table or data
change. A login without the right to checkpoint skips it.

**Same data as before.** Original `io` (25928a6) built from a separate worktree and this branch give identical row
counts in every table, reading statuses and audit actions (`runs/snap_orig.txt` = `runs/snap_base.txt`).

**Results** (`matrix_summary.txt`, script `matrix.sh`; each database starts with a dummy lab table `EMPLOYEE`):

| Log cap | build 1 | C1 large set, then build 2 | build 3 | tests.sql | telemetry/VEE | select.sql | final build | lab table kept |
|---|---|---|---|---|---|---|---|---|
| 20 MB (= SQL2025) | OK | OK | OK | 82/82 | 26/26 | UC-01..20 | OK | yes |
| none | OK | OK | OK | 82/82 | 26/26 | UC-01..20 | OK | yes |
| 12 MB (= 2022 target) | **FAIL** | OK | OK | 82/82 | 26/26 | UC-01..20 | **FAIL** | yes |

Every OK build has exactly the rows of the uncapped baseline.

**Still open (12 MB).** The two failures are always `sp_FinalizeReadings` for 31 October (last day of the month, so it
also builds the MONTH aggregates), run for all meters in one transaction (`runs/c12_b1.txt`, `runs/c12_b4_final.txt`).
Next: combine these checkpoints with finalizing one meter per call (`next_import_per_meter_finalize.patch`), re-run
the matrix and compare with original `io` again (the per-meter order d1, d2 per meter differs from all meters d1 then
d2, so the MONTH aggregates must be checked).

**Other notes.** `evidence/C1/c1_large_set.sql` exits 1 even without a cap ("not final" in its aggregate step); it is an
evidence script, not a deliverable, to look at separately (it ran near midnight UTC). The populated rehearsal reached
about 19-20 MB of data, less than the real course databases (24-25.7 MB).

## 25/11: drop only MDMS-Cy objects (lab tables keep their foreign keys)

`create.sql` and `drop.sql` used to drop **every** foreign key of the `dbo` schema. On the SQL2025 database that would
have removed the 21 foreign keys of the lab tables (`L8_*`). Both files now keep the 62 MDMS-Cy table names in one list,
drop only the foreign keys that touch those tables, then drop the tables one per statement (smaller transactions).

`matrix_labfk.sh` (lab tables `DEPARTMENT`, `EMPLOYEE`, `L8_ORDERS` linked by 3 foreign keys, `labcheck.sql`) →
`matrix_labfk_summary.txt`: with a 20 MB log and uncapped, build x4 (two re-runs on a populated DB) identical to the
baseline, tests.sql 82/82, telemetry/VEE 26/26, select.sql UC-01..20, 3 lab FKs and 3 lab rows kept, and the baseline
equals the original `io` data.
