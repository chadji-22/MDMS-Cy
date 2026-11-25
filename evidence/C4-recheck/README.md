# C4 re-check — Eliana's .dat files and bulk_import.sql on today's schema (25/11/2026)

C4 was done by Eliana on 18/11 (commit `188505e`: 24 `data/*.dat` files exported with `bcp -w -k -E`, `bulk_import.sql`).
Since then the schema gained one table, `NOTIFICATION` (B11, 22/11); the other 24 table definitions are unchanged.
This re-check loads her files into the current code (branch `ioannis/integration-2`).

Steps (local SQL Server 2022 container, login `sa`, which has the bulk-load right the course servers do not give):
1. empty database `c4test`; `build_all.sql` with the `:r import.sql` line removed, so the tables are empty
   (25 tables, 118 procedures: `schema_build_summary.txt`);
2. the 24 files copied into the container at `/var/opt/mssql/import`;
3. `sqlcmd -d c4test -b -v DataPath="/var/opt/mssql/import" -i bulk_import.sql` (in Git Bash with
   `MSYS_NO_PATHCONV=1`, otherwise the Linux path is rewritten).

Result (`bulk_import_output.txt`): exit 0, no error, all 24 tables loaded; the row counts equal the `import.sql` demo data
(USER_ACCOUNT 21, TELEMETRY_PACKET 2,305, METER_READING 8,063, AGGREGATE 4,701, AUDIT_LOG 364, ...).

Open, for Eliana to decide: `NOTIFICATION` is not in the list of `bulk_import.sql`. The demo data has 0 notifications, so no
data is lost; adding an empty `NOTIFICATION.dat` and one line would make the script cover all 25 tables.
`bulk_import.sql` cannot run on the course servers (no bulk-load permission), as its header says.
