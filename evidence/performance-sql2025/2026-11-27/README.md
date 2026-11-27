# Performance on the real server (SQL2025): does every function answer in under 2 s?

Date: 27/11/2026 (12:38-13:30 UTC). Commit of the app: `5415192`, deployed at
`https://students.cs.ucy.ac.cy/~ichara09/mdms/` (PHP 8.0.30); database `ichara09` on `mssql.cs.ucy.ac.cy\SQL2025`.
Asked by the user, who authorised this run explicitly. It goes beyond TESTING_PLAN §2 ("no perf tests on S"): the
writes ran in transactions that were always rolled back, and the demo data was verified unchanged afterwards.

**Answer: yes, on the demo data every function measured answers in under 2 s.** All functions except one stay under
1.1 s. The exception is the DSO's batch ingest: one meter-day (95 packets) takes about **1.8 s** end to end, once the
commit cost is included. It grows by about 15.6 ms per packet, so batches of more than about 105 packets go over 2 s
(see "Limits").

## How it was measured

| Part | What | Result |
|---|---|---|
| 1. Pages, end to end | `time_pages.py`: Connect, then log in as 9 accounts (all 8 roles) and open every page reachable by links. Also opens heavier variants: 31-day readings, reports for the whole grid, market levels 1-3, map points, JSON. Each URL 3 times, timed from the user's PC over the VPN | 190 distinct requests, 564 timed: **max 0.581 s**, median 0.311 s, 0 over 1 s |
| 2. Read procedures | `reads.sql`: 55 calls covering every read procedure, run as the web app does (`EXECUTE AS USER = 'mdms_php'`), 3 times each, timed on the server | **max 158 ms** |
| 3. Write procedures | `writes.sql`: 21 chains run twice, covering every write procedure including the SQL-only ones. Each chain is one transaction, always rolled back. They walk through the real flows: registration, documents and approvals, work orders, meter installation and approval, commands, load shedding, telemetry → VEE → suspects → finalize → transformer totals, GDPR to execution, billing, catalogs | **max 1,237 ms** (batch ingest); everything else ≤ 487 ms |

Coverage: 109 of the 110 procedures that are not internal helpers were measured; together they serve all 106 web
functions and the 17 SQL-only procedures. Not run: `sp_GenerateSyntheticData`, the bulk data generator. It is not a
user function, and its default run (2,000 consumers) would overflow the 27 MB data cap.

**From procedure time to what a user waits.** Any page that uses the database costs about **0.30 s** before the
procedure itself: the web server opens a TLS connection to SQL2025, logs in, switches to `mdms_php`, and the request
crosses the VPN. Pages with fast procedures have a median of 0.30 s; `home.php`, which does not touch the database,
takes 0.04 s.
* A read page ≈ 0.30 s + its procedures.
* A form ≈ 0.30 s + the procedure for the POST, then the page it redirects to. For the heavy DSO forms
  (`dso/ingest.php`, `vee.php`, `finalize.php`) that page costs only 0.05 s, because their GET calls no procedure.
  Other result pages cost 0.3–0.45 s.

**Commit cost.** Inside the rolled-back transaction, the procedures' own `COMMIT`s are nested, so no log flush happens.
In real use each one writes the log to disk. `commit_probe.sql` measured that on SQL2025: **2.6 ms per commit**. It
compares 100 one-row inserts with 100 commits against 100 with 1 commit, over 3 rounds, on a probe table that was
created and dropped again; the 25 tables were unchanged afterwards. That cost is added below:
* batch ingest commits once per packet plus once for the summary;
* VEE and finalize commit once per meter;
* issuing bills commits once per bill.

## Results: slowest functions end to end

Estimate = POST overhead 0.30 s + SQL max + commits × 2.6 ms + result page.

| Function (page) | SQL max | Commits | Result page | User waits about |
|---|---|---|---|---|
| Ingest a batch of 95 packets, one meter-day (`dso/ingest.php`) | 1.24 s | 96 → 0.25 s | 0.05 s | **1.84 s** (median 1.79 s) |
| Run VEE for a meter-day (`dso/vee.php`) | 0.49 s | 1 | 0.05 s | 0.84 s |
| Build transformer totals for a day (`dso/finalize.php`) | 0.47 s | few | 0.05 s | 0.83 s |
| Finalize a day (`dso/finalize.php`) | 0.34 s | 1 | 0.05 s | 0.69 s |
| Refresh transformer state (`tso/`) | 0.33 s | 1 | ≈ 0.35 s | 0.98 s |
| Issue the October bills, 6 premises (`market/bills.php`) | 0.06 s | 6 | ≈ 0.35 s | 0.73 s |
| Phase unbalance report with events (`dso/reports.php`) | 0.19 s | few | ≈ 0.45 s | 0.95 s |
| Slowest read page measured: phase unbalance report for the whole grid | in the page | – | – | 0.58 s |

## Limits: read before relying on these numbers

* **Data volume.** SQL2025 holds the demo data: 12 meters, 8,063 readings (2 days), 4,701 totals, 402 audit rows. The
  27 MB cap does not allow the large data set. Procedures that scan readings or totals get slower with more data.
* **Batch ingest grows with its size.** Each packet costs about 13 ms of SQL plus 2.6 ms for its commit, 15.6 ms in
  all. The fixed part is about 0.35 s, so a batch of more than about **105 packets** passes 2 s. The page accepts up to
  2 MB, which is thousands of packets.
  * Possible fixes, **not applied**: each is a code change, needs the gate and a redeploy, and deploying is the user's
    job.
    1. Limit the page to about 100 packets per batch (one meter-day).
    2. Run the whole batch in one transaction, which saves the 0.25 s of commits.
    3. Make the ingest set-based instead of one packet at a time.
* Logout and Disconnect (functions 4 and 2) were not timed: they call no procedure. `home.php`, which also calls none,
  took 0.04 s.
* **Time depends on where you are.** The page times include the VPN from this PC. On campus they should be lower.
* The first call of a procedure is slower: its plan is compiled and its data read from disk. For example
  `sp_GetDayAheadAggregates` takes 158 ms the first time and 46 ms after; VEE took 487 ms the first time and 72 ms in
  the second pass. The max column keeps those first calls.

## Safety: the demo data was not changed

* Before anything ran, all 25 MDMS tables were exported in full (kept outside the repo) and recorded in
  `snapshot-before.txt` (row count + `CHECKSUM_AGG(BINARY_CHECKSUM(*))` per table).
* Every write chain ran as one transaction that ends in `ROLLBACK`. After every call the script checks `@@TRANCOUNT`.
  Some procedures catch errors per item and roll back, so a lost outer transaction stops the run (error 50999,
  `sqlcmd -b`). This never happened.
* Destructive steps (right to be forgotten, password change, deactivation, meter status, meter replacement) used only
  accounts and meters created inside the same transaction.
* A pilot chain plus a snapshot comparison was done first.
* After both full passes the snapshot of all 25 tables is **identical** to the one before (`snapshot-after.txt`).
* Only the file statistics moved: data space in use went from 20.00 to 20.44 MB, because pages taken during the
  rolled-back work stay allocated empty for a while. The log went from 3.44 to 1.67 MB used.
* Two chains end on a refusal by design: a wrong password (`sp_Login`, 50006) and `sp_BootstrapAdmin` when an
  administrator exists (50003). Their times are the error path.
* Side effects that remain: identity values used inside the rolled-back transactions are skipped, so the next new
  user, bill, etc. gets a higher id. The page run added login rows to `AUDIT_LOG`, as any login does.

## Files

| File | What |
|---|---|
| `../time_pages.py` | the page timer (read-only) |
| `../make_sql.py` | generates `reads.sql`, `writes.sql` and `pilot.sql` (the guards are described in its header) |
| `pages-S.csv`, `pages-S.txt` | every page: min / median / max seconds |
| `sql-reads-raw.txt`, `sql-writes-raw.txt` | every timed call (`RES|…|ms|note`) |
| `snapshot.sql`, `snapshot-before.txt`, `snapshot-after.txt` | the data check |
| `commit_probe.sql`, `commit-probe-result.txt` | cost of one commit on SQL2025 (2.6 ms) |

The full export of the 25 tables taken before the run is in the session scratchpad, not in the repository because it
contains the password hashes: `C:\Users\ioann\AppData\Local\Temp\claude\01188d643f296ad0\f11363e0-2be0-43d0-9115-2fe67fa543cb\scratchpad\perf\export-before\`.

Re-run (repository root, Git Bash, VPN on; the password comes from the Windows user variable and is never printed):

```bash
export DB_FORM_PASS="$(powershell.exe -NoProfile -Command "[Console]::Out.Write([Environment]::GetEnvironmentVariable('SQLCMDPASSWORD','User'))" | tr -d '\r\n')"
export SQLCMDPASSWORD="$DB_FORM_PASS"; T=<a scratch folder>
python evidence/performance-sql2025/time_pages.py https://students.cs.ucy.ac.cy/~ichara09/mdms pages.csv 3
python evidence/performance-sql2025/make_sql.py "$T"
Q() { /c/Users/ioann/tools/sqlcmd/sqlcmd.exe -S 'mssql.cs.ucy.ac.cy\SQL2025' -U ichara09 -d ichara09 -C -I -b -W -s '|' "$@"; }
Q -i evidence/performance-sql2025/2026-11-27/snapshot.sql > before.txt
Q -i "$T/reads.sql" | grep '^RES|'; Q -i "$T/pilot.sql" | grep '^RES|'; Q -i "$T/writes.sql" | grep '^RES|'
Q -i evidence/performance-sql2025/2026-11-27/snapshot.sql > after.txt; diff <(head -28 before.txt) <(head -28 after.txt) && echo unchanged
```

## Every timed call (server-side, sorted by the slowest)

| Call (as run) | R/W | Samples | Median ms | Max ms | Web page? |
|---|---|---|---|---|---|
| `sp_IngestTelemetryBatch (95 packets, 1 meter-day)` | W | 2 | 1185.8 | 1236.6 | yes |
| `sp_RunVEE (meter 1, the day)` | W | 2 | 279.6 | 487.3 | yes |
| `sp_BuildTransformerAggregates (the day)` | W | 2 | 389.8 | 472.0 | yes |
| `sp_PurgeExpiredReadings (SQL only)` | W | 2 | 271.4 | 367.6 | SQL only |
| `sp_FinalizeReadings (meter 1, the day)` | W | 2 | 301.2 | 338.3 | yes |
| `sp_RefreshTransformerState` | W | 2 | 319.1 | 332.0 | yes |
| `sp_ReportPhaseUnbalance (raise events)` | W | 2 | 125.2 | 189.3 | yes |
| `sp_GetDayAheadAggregates level 1` | R | 3 | 46.2 | 158.4 | yes |
| `sp_GetIntradayProvisional` | R | 3 | 46.1 | 124.2 | yes |
| `sp_GetTransformerTree` | R | 3 | 41.7 | 117.2 | yes |
| `sp_AdvanceGdprRequest APPROVED (2nd officer)` | W | 2 | 58.1 | 110.0 | yes |
| `sp_RefreshTransformerAncestors` | W | 2 | 60.8 | 99.7 | yes |
| `sp_EditReading` | W | 2 | 52.2 | 99.1 | yes |
| `sp_ReportSystemStatistics` | R | 3 | 40.4 | 90.8 | yes |
| `sp_IssueMonthlyBills (October, supplier 1: 6 premises)` | W | 2 | 64.5 | 83.7 | yes |
| `sp_ReportPhaseUnbalance root` | R | 3 | 52.0 | 77.4 | yes |
| `sp_UpsertTransformer (new)` | W | 2 | 40.5 | 71.5 | yes |
| `sp_GetMeter (technician)` | R | 3 | 4.2 | 68.3 | yes |
| `sp_GetWorkOrderHistory (consumer)` | R | 3 | 4.2 | 68.2 | yes |
| `sp_ListSuspectReadings (the day)` | W | 2 | 33.9 | 65.8 | yes |
| `sp_ListCommands (TSO)` | W | 2 | 34.2 | 64.9 | yes |
| `sp_CheckConsumptionThresholds (SQL only; raises event + notifications)` | W | 2 | 33.9 | 59.8 | SQL only |
| `sp_ReportVoltageEvents root` | R | 3 | 50.9 | 58.1 | yes |
| `sp_FindAvailableTechnicians` | R | 3 | 4.2 | 54.0 | yes |
| `sp_GetDayAheadAggregates level 3` | R | 3 | 44.0 | 46.4 | yes |
| `sp_GetDayAheadAggregates level 2` | R | 3 | 43.4 | 46.1 | yes |
| `sp_ReportTechnicalLosses (raise events)` | W | 2 | 33.3 | 46.0 | yes |
| `sp_ShedTransformerLoad root (all meters)` | W | 2 | 32.8 | 34.4 | yes |
| `sp_GetTechnicianReview` | R | 3 | 4.8 | 32.0 | yes |
| `sp_ListUsers (SQL only)` | R | 3 | 3.8 | 29.4 | SQL only |
| `sp_DispatchCommands (all, after root shed)` | W | 2 | 25.0 | 27.6 | yes |
| `sp_MarkOverdueBills (SQL only, as of 2027-02-01)` | W | 2 | 24.3 | 27.1 | SQL only |
| `sp_DecideDocument REJECTED` | W | 2 | 16.0 | 25.7 | yes |
| `sp_GetPremiseReadings p3 31 days` | R | 3 | 21.4 | 22.7 | yes |
| `sp_RegisterTechnician` | W | 2 | 12.8 | 20.6 | yes |
| `sp_AddTechnicianDocument` | W | 2 | 13.6 | 20.6 | yes |
| `sp_ReportTechnicalLosses tx15` | R | 3 | 16.3 | 17.9 | yes |
| `sp_ListMyDocuments (new technician)` | W | 2 | 10.2 | 17.5 | yes |
| `sp_UpsertTransformer (edit)` | W | 2 | 13.9 | 17.3 | yes |
| `sp_GetTechnicianReview (new technician)` | W | 2 | 10.3 | 16.5 | yes |
| `sp_ResubmitDocument` | W | 2 | 10.7 | 16.0 | yes |
| `sp_UpsertObisCode` | W | 2 | 11.7 | 15.9 | yes |
| `sp_GetPremiseAggregates DAY` | R | 3 | 15.5 | 15.8 | yes |
| `sp_AssignWorkOrder (installation)` | W | 2 | 14.6 | 15.3 | yes |
| `sp_Login (right password)` | W | 2 | 10.5 | 15.2 | yes |
| `sp_GetPremiseAggregates MONTH` | R | 3 | 13.8 | 14.8 | yes |
| `sp_AssignWorkOrder (2nd)` | W | 2 | 13.6 | 14.4 | yes |
| `sp_AssignWorkOrder` | W | 2 | 13.8 | 13.8 | yes |
| `sp_AssignWorkOrder (replacement)` | W | 2 | 13.8 | 13.8 | yes |
| `sp_ExecuteGdprRequest (SQL only)` | W | 2 | 11.9 | 13.7 | SQL only |
| `sp_GetPremiseReadings p3 2 days` | R | 3 | 13.2 | 13.3 | yes |
| `sp_IngestTelemetryPacket` | W | 2 | 12.6 | 13.1 | yes |
| `sp_DecideTechnician REJECTED` | W | 2 | 8.5 | 12.8 | yes |
| `sp_ReplaceMeter (SQL only)` | W | 2 | 11.9 | 12.8 | SQL only |
| `sp_ShedTransformerLoad tx15` | W | 2 | 11.4 | 12.4 | yes |
| `sp_DecideDocument APPROVED` | W | 2 | 8.2 | 12.2 | yes |
| `sp_SimulateCommandAcknowledgment` | W | 2 | 10.3 | 12.2 | yes |
| `sp_DecideDocument APPROVED (licence)` | W | 2 | 8.1 | 11.9 | yes |
| `sp_DecideTechnician APPROVED` | W | 2 | 9.3 | 11.7 | yes |
| `sp_AcceptSuspectReading` | W | 2 | 7.9 | 11.7 | yes |
| `sp_AddTechnicianDocument (training)` | W | 2 | 7.9 | 11.6 | yes |
| `sp_AddTechnicianDocument (licence)` | W | 2 | 8.6 | 10.8 | yes |
| `sp_DecideDocument APPROVED (training)` | W | 2 | 8.0 | 10.5 | yes |
| `sp_ResubmitTechnician` | W | 2 | 7.3 | 10.5 | yes |
| `sp_RecordTransformerReading` | W | 2 | 8.1 | 10.1 | yes |
| `sp_InstallMeter` | W | 2 | 9.9 | 10.0 | yes |
| `sp_RaiseTamperEvent` | W | 2 | 8.2 | 9.5 | yes |
| `sp_FindGeofenceForPoint` | R | 3 | 6.3 | 9.0 | yes |
| `sp_BuyHistoricalAccess` | W | 2 | 8.4 | 8.8 | yes |
| `sp_CreateWorkOrder REPLACEMENT (SQL only)` | W | 2 | 6.3 | 8.4 | SQL only |
| `sp_DispatchCommands (all approved)` | W | 2 | 7.8 | 8.4 | yes |
| `sp_SetPremiseAggregator (SQL only)` | W | 2 | 7.2 | 8.2 | SQL only |
| `sp_CancelWorkOrder` | W | 2 | 6.8 | 8.0 | yes |
| `sp_SubmitServiceRequest TECHNICAL_CHECK` | W | 2 | 6.9 | 7.8 | yes |
| `sp_DeclineWorkOrder` | W | 2 | 6.9 | 7.5 | yes |
| `sp_SetMeterStatus (SQL only)` | W | 2 | 7.0 | 7.5 | SQL only |
| `sp_AcknowledgeCommand (device ACK, SQL only)` | W | 2 | 7.2 | 7.5 | SQL only |
| `sp_DecideRemoteCommand REJECTED` | W | 2 | 6.9 | 7.5 | yes |
| `sp_SubmitGdprRequest RIGHT_TO_BE_FORGOTTEN` | W | 2 | 5.8 | 7.5 | yes |
| `sp_GetGridOverview` | R | 3 | 6.3 | 7.4 | yes |
| `sp_UpdatePremise (SQL only)` | W | 2 | 6.7 | 7.4 | SQL only |
| `sp_AcceptWorkOrder (replacement)` | W | 2 | 6.4 | 7.3 | yes |
| `sp_PayBill (part payment)` | W | 2 | 6.8 | 7.2 | yes |
| `sp_GetPremiseReadings p1 not bought (50008)` (refusal, as expected) | R | 3 | 5.5 | 7.1 | yes |
| `sp_GetMyBillsAndPayments` | R | 3 | 4.2 | 7.0 | yes |
| `sp_CreateWorkOrder ANTI_TAMPER (SQL only)` | W | 2 | 6.5 | 7.0 | SQL only |
| `sp_UpsertMeterType` | W | 2 | 6.3 | 6.8 | yes |
| `sp_AddMeterDocument ENCRYPTION_CERT` | W | 2 | 5.2 | 6.7 | yes |
| `sp_CancelBill (bill 2)` | W | 2 | 5.4 | 6.6 | SQL only |
| `sp_CreateWorkOrder INSTALLATION` | W | 2 | 6.0 | 6.5 | SQL only |
| `sp_DecideDocument meter doc 2` | W | 2 | 5.3 | 6.5 | yes |
| `sp_UpdateMeterTechnicalData (SQL only)` | W | 2 | 6.4 | 6.5 | SQL only |
| `sp_UpsertServiceType` | W | 2 | 5.4 | 6.5 | yes |
| `sp_ListMyWorkOrders (consumer)` | R | 3 | 4.2 | 6.4 | yes |
| `sp_ListWorkOrders` | R | 3 | 4.2 | 6.4 | yes |
| `sp_RegisterConsumer` | W | 2 | 5.2 | 6.4 | yes |
| `sp_ListGdprRequests (officer)` | R | 3 | 6.3 | 6.3 | yes |
| `sp_GetTransformerState` | R | 3 | 6.3 | 6.3 | yes |
| `sp_CreateOrganization` | W | 2 | 5.2 | 6.3 | yes |
| `sp_AddPremise` | W | 2 | 5.7 | 6.3 | yes |
| `sp_ChangeSupplier (SQL only)` | W | 2 | 5.7 | 6.3 | SQL only |
| `sp_PayServiceFee` | W | 2 | 6.3 | 6.3 | yes |
| `sp_SetPremiseThreshold (premise 2, 10 kWh)` | W | 2 | 5.7 | 6.3 | yes |
| `sp_SubmitServiceRequest FAULT_REPAIR` | W | 2 | 6.3 | 6.3 | yes |
| `sp_AcceptWorkOrder` | W | 2 | 6.1 | 6.3 | yes |
| `sp_AddPremise (for the new meter)` | W | 2 | 5.2 | 6.3 | yes |
| `sp_AcceptWorkOrder (installation)` | W | 2 | 5.2 | 6.3 | yes |
| `sp_AddMeterDocument CALIBRATION_CERT` | W | 2 | 5.2 | 6.3 | yes |
| `sp_RequestRemoteCommand (SQL only)` | W | 2 | 5.4 | 6.3 | SQL only |
| `sp_DecideRemoteCommand APPROVED` | W | 2 | 5.2 | 6.3 | yes |
| `sp_DispatchCommands (one command)` | W | 2 | 5.2 | 6.3 | yes |
| `sp_DecideRemoteCommand APPROVED (2nd)` | W | 2 | 4.5 | 6.3 | yes |
| `sp_DispatchCommands (2nd)` | W | 2 | 5.2 | 6.3 | yes |
| `sp_RequestRemoteCommand (3rd)` | W | 2 | 5.3 | 6.3 | SQL only |
| `sp_UpsertTariff` | W | 2 | 5.5 | 6.3 | yes |
| `sp_RegisterConsumer (throw-away)` | W | 2 | 5.2 | 6.3 | yes |
| `sp_AdvanceGdprRequest UNDER_REVIEW` | W | 2 | 5.2 | 6.3 | yes |
| `sp_CancelBill (bill 4)` | W | 2 | 5.2 | 6.3 | SQL only |
| `sp_CancelBill (bill 7)` | W | 2 | 5.5 | 6.3 | SQL only |
| `sp_ConfirmMeter` | W | 2 | 6.0 | 6.1 | yes |
| `sp_ListMyNotifications` | R | 3 | 4.7 | 6.0 | yes |
| `sp_ChangePassword` | W | 2 | 5.2 | 6.0 | yes |
| `sp_SetUserActive off (SQL only)` | W | 2 | 5.1 | 6.0 | SQL only |
| `sp_AddMeterDocument CE_DECLARATION` | W | 2 | 5.1 | 5.9 | yes |
| `sp_DecideDocument meter doc 3` | W | 2 | 5.1 | 5.9 | yes |
| `sp_SetAvailability (install day)` | W | 2 | 5.2 | 5.8 | yes |
| `sp_ListSupplierBills (after issuing)` | W | 2 | 4.7 | 5.8 | yes |
| `sp_ListSupplierBills` | R | 3 | 5.4 | 5.7 | yes |
| `sp_SetPremiseThreshold` | W | 2 | 5.5 | 5.6 | yes |
| `sp_CompleteWorkOrder` | W | 2 | 4.8 | 5.5 | yes |
| `sp_GetEvents` | R | 3 | 4.3 | 5.4 | yes |
| `sp_SetAvailability` | W | 2 | 5.1 | 5.4 | yes |
| `sp_RequestRemoteCommand (2nd)` | W | 2 | 4.8 | 5.4 | SQL only |
| `sp_CreateStaffUser` | W | 2 | 5.0 | 5.3 | yes |
| `sp_AdvanceGdprRequest PRE_APPROVED` | W | 2 | 4.8 | 5.3 | yes |
| `sp_ListGdprRequests (consumer)` | R | 3 | 4.2 | 5.2 | yes |
| `sp_UpdateMyProfile (notification preferences)` | W | 2 | 4.8 | 5.2 | yes |
| `sp_ListCommands` | R | 3 | 4.2 | 5.1 | yes |
| `sp_CancelBill (bill 6)` | W | 2 | 4.7 | 5.1 | SQL only |
| `sp_ListSuspectReadings` | R | 3 | 4.8 | 5.0 | yes |
| `sp_SubmitGdprRequest RETENTION_REDUCTION` | W | 2 | 4.6 | 5.0 | yes |
| `sp_CancelBill (bill 3)` | W | 2 | 4.9 | 5.0 | SQL only |
| `sp_CancelBill (bill 5)` | W | 2 | 4.8 | 5.0 | SQL only |
| `sp_GetMeter (officer)` | R | 3 | 4.2 | 4.9 | yes |
| `sp_ListMyWorkOrders (technician)` | R | 3 | 4.2 | 4.8 | yes |
| `sp_ListReferenceCatalog obis` | R | 3 | 3.9 | 4.8 | yes |
| `sp_SetUserActive on (SQL only)` | W | 2 | 4.5 | 4.8 | SQL only |
| `sp_StartWorkOrder` | W | 2 | 4.5 | 4.8 | yes |
| `sp_ListSuppliers` | R | 3 | 4.5 | 4.6 | yes |
| `sp_ListMyDocuments` | R | 3 | 4.3 | 4.6 | yes |
| `sp_DecideDocument meter doc 1` | W | 2 | 4.4 | 4.6 | yes |
| `sp_GetAuditLog page 1` | R | 3 | 4.2 | 4.4 | yes |
| `sp_ListMeters (map)` | R | 3 | 2.6 | 4.4 | yes |
| `sp_GetPortfolioSummary supplier` | R | 3 | 4.2 | 4.4 | yes |
| `sp_ListReferenceCatalog tariffs` | R | 3 | 2.1 | 4.3 | yes |
| `sp_SetAvailability (for the jobs)` | W | 2 | 3.5 | 4.3 | yes |
| `sp_GetPremiseEvents` | R | 3 | 2.1 | 4.2 | yes |
| `sp_ListServiceTypes` | R | 3 | 2.7 | 4.2 | yes |
| `sp_GetWorkOrderHistory (technician)` | R | 3 | 2.1 | 4.2 | yes |
| `sp_GetMyAvailability` | R | 3 | 3.3 | 4.2 | yes |
| `sp_GetAuditLog page 5` | R | 3 | 4.2 | 4.2 | yes |
| `sp_ListPendingTechnicians` | R | 3 | 3.1 | 4.2 | yes |
| `sp_GetPortfolioSummary aggregator` | R | 3 | 4.2 | 4.2 | yes |
| `sp_UpdateMyProfile` | W | 2 | 3.8 | 4.2 | yes |
| `sp_CreateOrganizationUser` | W | 2 | 4.2 | 4.2 | yes |
| `sp_Login (wrong password, error path)` (refusal, as expected) | W | 2 | 4.2 | 4.2 | yes |
| `sp_DeleteAvailability` | W | 2 | 4.2 | 4.2 | yes |
| `sp_GetMeter (pending meter)` | W | 2 | 3.2 | 4.2 | yes |
| `sp_ListMyPremises 12` | R | 3 | 2.3 | 3.9 | yes |
| `sp_ListMeters (officer)` | R | 3 | 3.2 | 3.8 | yes |
| `sp_BootstrapAdmin (error path)` (refusal, as expected) | W | 2 | 2.9 | 3.7 | SQL only |
| `sp_ListReferenceCatalog meter-types` | R | 3 | 3.0 | 3.6 | yes |
| `sp_ListReferenceCatalog service-types` | R | 3 | 3.0 | 3.3 | yes |
| `sp_GetMyProfile 12` | R | 3 | 3.0 | 3.2 | yes |
| `sp_GetHistoricalAccessQuote` | R | 3 | 2.1 | 2.1 | yes |
| `sp_ListOrganizations` | R | 3 | 2.1 | 2.1 | yes |
| `sp_FindAvailableTechnicians (with the slot)` | W | 2 | 2.1 | 2.1 | yes |
