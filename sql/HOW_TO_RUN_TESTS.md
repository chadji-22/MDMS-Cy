# Running the telemetry tests in SQL Server Management Studio (SSMS)

## 1. Connect

1. Open SSMS, **Connect > Database Engine**.
2. Server name: `mssql.cs.ucy.ac.cy` (the SQL Server 2022 server; not `...\SQL2025`).
3. Authentication: **SQL Server Authentication**, your UCY login and password.
4. Click **Options >>** → tab **Connection Properties** → *Connect to database*: your database
   (e.g. `ichara09`). Tick **Trust server certificate** if SSMS complains about the certificate.
5. Connect. The database drop-down in the toolbar must show your database whenever you run a script
   (a script run on `master` fails with "Invalid object name").

## 2. Build the database (once)

The schema must exist before the tests. `build_all.sql` **drops and recreates every MDMS-Cy table**,
so run it only on your own database.

* Easiest: from a terminal in the `phaseB` folder (the `io` branch):

      sqlcmd -S "mssql.cs.ucy.ac.cy" -U <user> -d <database> -C -I -b -W -i build_all.sql

  (the password is read from the `SQLCMDPASSWORD` environment variable, or add `-P <password>`).
* In SSMS: open `build_all.sql`, switch on **Query > SQLCMD Mode**, and make sure SSMS's working
  directory is the `phaseB` folder (the `:r create.sql` lines are relative paths). If that is awkward,
  open and run the files one by one in the order listed inside `build_all.sql`
  (`create.sql`, `functions.sql`, `views.sql`, `procedures_00_internal.sql`, `triggers.sql`,
  `procedures_01 ... procedures_12`, `indexes.sql`, `security.sql`, `import.sql`).

It ends with a table of object counts (24 tables, 23 triggers, 110 procedures ...) and
`build_all.sql finished.`

## 3. Run the tests

For every file: **File > Open > File...**, check the database drop-down, press **F5** (Execute).
Run them in this order:

| # | File | What it does | Writes data? |
|---|------|--------------|--------------|
| 1 | `seed_grid.sql` | creates the demo transformers `DEMO_TX_L2` > `DEMO_TX_L1` | yes (kept) |
| 2 | `seed_telemetry_demo.sql` | creates the ACTIVE demo meter `DEMO-NET-001` through the real procedures | yes (kept) |
| 3 | `test_telemetry_parsing.sql` | read-only demo of how a JSON packet is read | no |
| 4 | `test_telemetry_ingest.sql` | `sp_IngestTelemetryPacket`: valid, re-sent, unknown meter, wrong unit | cleaned afterwards |
| 5 | `test_telemetry_storage.sql` | what is stored: slot flooring, late packet, unknown/duplicate OBIS | cleaned afterwards |
| 6 | `test_vee_range.sql` | `sp_RunVEE` range rule | cleaned afterwards |
| 7 | `test_vee_delta.sql` | negative energy, gap estimation | cleaned afterwards |

The seeds are the fixture: run them once. They can be run again safely (they say "nothing to do").
The four tests delete their own events, readings and packets at the end (see the *CLEAN-UP* block).
The only trace left is in the audit log, which is append-only by design (TR03).
`cleanup_test_data.sql` removes any leftovers if a test was aborted half way.

## 4. Read the result

After **F5** look at the **Results** pane (bottom). Each test file produces several tabs in the
*Results* grid, plus a **Messages** tab:

1. **First grid: the verdict.** One row per check.

   | column | meaning |
   |--------|---------|
   | `seq` | order of the check |
   | `result` | `PASS` or `FAIL` |
   | `test` | what was checked, with the expected result in the text, e.g. *"T3 wrong unit -> MATCHED, 1 reading stored as SUSPECT (UNIT_MISMATCH)"* |
   | `detail` | what was actually observed, e.g. `MATCHED / readings 1`. Read this on a FAIL: it shows the status or error that came out instead |

2. **Second grid:** the totals (`PASS | 4`). Anything other than only `PASS` needs attention.
3. **Further grids:** the rows the test left in `TELEMETRY_PACKET`, `EVENT` and `METER_READING`
   (status, `vee_rule`, `delta_value`...). Use them to see *why* something failed. They are shown
   *before* the clean-up deletes them.
4. **Messages tab:** the last lines are
   `test_xxx.sql: 4 tests, 0 not passed.` and `clean-up: 2 events, 3 readings, 4 packets deleted.`
   Red text here is an error (see below).

**Success** = every row `PASS` and `0 not passed`. The four tests together are 4 + 8 + 5 + 9 = 26 checks.

### Reading the data columns

* `status` of a reading: `PENDING` (just ingested), `VALID` / `SUSPECT` (after `sp_RunVEE`),
  `ESTIMATED` (a missing slot filled by interpolation).
* `vee_rule`: why it got that status: `RANGE`, `NEGATIVE_DELTA`, `UNIT_MISMATCH`, `AUTO` (passed everything),
  `LINEAR_INTERPOLATION`.
* `delta_value`: the energy of that 15-minute slot (cumulative registers only; `NULL` when the previous slot is missing).
* `match_status` of a packet: `MATCHED` (meter exists and is ACTIVE), `UNMATCHED` (unknown network id),
  `QUARANTINED` (meter exists but is not ACTIVE), `COMM_ERROR` (not valid JSON).

## 5. Common messages

| Message | Meaning / fix |
|---------|---------------|
| `Msg 54000 ... run import.sql first` / `DEMO-NET-001 is not ACTIVE` | a prerequisite is missing: run the build (which includes `import.sql`), then `seed_grid.sql`, then `seed_telemetry_demo.sql` |
| `seed_telemetry_demo.sql: DEMO-NET-001 exists but is not ACTIVE` | an earlier seed run stopped half way; follow the text of the message |
| `Invalid object name 'dbo.METER'` | wrong database in the toolbar drop-down, or the build was not run |
| `FAIL` in a row | read `test` (expected) against `detail` (observed) and the data grids below |
| a `FAIL` with `detail` = an error text | the error came from the procedure itself; run the procedure by hand (e.g. `EXEC dbo.sp_RunVEE ...`). Error 3915 hides the real error behind `INSERT ... EXEC` |
| `The audit log is append-only` | you tried to delete from `AUDIT_LOG`; leave it, it is meant to keep its rows |

The project's own suite is `tests.sql` (in the `phaseB` folder, run after the build): it must also end with
`tests.sql: 71 tests, 0 not passed.`
