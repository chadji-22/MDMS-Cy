# MDMS-Cy — Phase B progress report

**Course:** EPL342 Databases, University of Cyprus — Group 10
**System:** Smart National Meter Data Management System (MDMS-Cy)
**Report date:** 11/11/2026 — **Phase B deadline:** Friday 4/12/2026, 12:00
**Sources:** `project.pdf` (the assignment), `MDMS_Cy_SQL_Build_Spec.md` (our build contract), `create.sql` v6 and `MDMS_Cy_ERD_v6.erdplus` (the frozen schema)

---

## 1. Where the project stands

The database side of Phase B is built and running on the course SQL Server. The web interface and the written deliverables are not started.

| Part | State |
|---|---|
| Schema (24 tables, v6) | Done, deployed |
| Functions, views, triggers, stored procedures | Done, deployed |
| Indexes and security script | Done, deployed |
| Small data set, loaded only through the procedures | Done, deployed |
| Demo script, one flow per use case | Done, runs clean |
| Automated tests | Done, 71 of 71 pass |
| Synthetic data generator | Written and verified on a tiny run only |
| Performance run (10,000 calls, index before/after) | Script written, **not run** |
| `.dat` export and reload | Reload script written, **not run**, no `.dat` files yet |
| PHP / HTML interface (`sources/`) | **Not started** |
| User manual and the three documentation topics (`docx/`) | **Not started** |

What is deployed in the database `ichara09` on `mssql.cs.ucy.ac.cy\SQL2025`:

| Object kind | Count |
|---|---|
| Tables | 24 |
| Views | 8 |
| Functions | 10 (8 scalar, 2 table-valued) |
| Triggers | 23 |
| Stored procedures | 110 (102 called by the application, 8 internal helpers) |
| Indexes added by `indexes.sql` | 14 |

Two things block the remaining database work on the course server, and both need a decision (section 7):

- **The database is capped at 27 MB.** About 25 MB is used after the build, the tests and the demos. The large data set does not fit, so the 2-second target and the index before/after case cannot be measured there.
- **The login cannot run `BULK INSERT`**, and `bcp` is not installed on the development PC, so the `data/*.dat` deliverable cannot be produced or reloaded yet.

---

## 2. What is in the folder

All files are in `phaseB/` next to `create.sql`. For the final zip they go into `sql/` (see section 6.7).

| File | Contents |
|---|---|
| `create.sql`, `drop.sql` | Schema v6: tables, CHECKs, foreign keys, filtered unique indexes, reference data |
| `functions.sql` | 10 functions: password hash, 15-minute slot, role check, tree walks, geofence lookup, access rule, tariff, bill balance |
| `views.sql` | 8 views: one per user role, premise with meter, meter location, open work orders, bill balance |
| `procedures_00_internal.sql` | 8 helpers the application must not call (`sp__` prefix) |
| `triggers.sql` | 23 triggers: 12 guards, 7 audit, 4 that create derived rows |
| `procedures_01_accounts.sql` | 22 procedures: login, registration, staff, technician approval, availability |
| `procedures_02_consumer.sql` | 12 procedures: premises, readings, aggregates, thresholds, paid history |
| `procedures_03_workorders.sql` | 11 procedures: requests and field jobs |
| `procedures_04_meters.sql` | 8 procedures: install, certificates, confirm, replace, status |
| `procedures_05_commands.sql` | 6 procedures: remote commands, retries, shedding |
| `procedures_06_telemetry.sql` | 10 procedures: packet ingestion, VEE, finalization, aggregates, purge |
| `procedures_07_grid.sql` | 11 procedures: transformer tree, current state, DSO analytics |
| `procedures_08_billing.sql` | 8 procedures: tariffs, bill run, payments |
| `procedures_09_gdpr.sql` | 4 procedures: GDPR requests and their execution |
| `procedures_10_market.sql` | 3 procedures: Day-Ahead, Intraday, portfolio |
| `procedures_11_admin.sql` | 6 procedures: reference data, audit log, events, management report |
| `procedures_12_generator.sql` | 1 procedure: the synthetic data generator |
| `indexes.sql` | 14 indexes, the three documented ones first |
| `security.sql` | Application role, denies, snapshot reads |
| `import.sql` | The small data set |
| `select.sql` | One demo per use case UC-01 to UC-20 |
| `tests.sql` | 71 tests, each prints PASS or FAIL |
| `perf.sql` | Performance run and index before/after |
| `bulk_import.sql` | Reload from `.dat` files |
| `build_all.sql` | Runs everything from `create.sql` to `import.sql` in order |

---

## 3. How it was built

### 3.1 Design rules we followed

These come from the instructor's requirements and are fixed in the build spec.

- **Everything runs through stored procedures.** The PHP code will only execute `{call dbo.sp_Name(?, ...)}`. The application role is denied direct `SELECT`, `INSERT`, `UPDATE` and `DELETE`.
- **Every application procedure takes `@actor_user_id` first**, checks the role, and records the actor in the session so the triggers can log who did it.
- **Every change of more than one row is one transaction** with `XACT_ABORT`, `TRY/CATCH`, rollback and `THROW`.
- **Status changes are guarded updates.** The expected old status is part of the `WHERE`; if another user got there first the procedure fails with error 50003.
- **Triggers enforce what must never be broken**: final readings and aggregates cannot change, the audit log is append-only, users, bills and payments are never deleted.
- **Cursors only for "for each X, do a workflow step"** (23 cursors, all `LOCAL FAST_FORWARD`); everything else is set-based.
- **No dynamic SQL** in any procedure. The only dynamic statement of the project is in `bulk_import.sql`, because `BULK INSERT` does not accept a variable for the file.
- **Errors use one catalog:** 50001 not found, 50002 permission, 50003 wrong state, 50004 bad input, 50005 duplicate, 50006 login failed, 50007 busy, 50008 history not bought, and `[51001]`–`[51012]` for the guard triggers.

### 3.2 Order of work

1. Checked the ERD against `create.sql`: 24 entities and 48 relationships, matching the 24 tables and 48 foreign keys. The schema was not changed at any point.
2. Wrote functions, views, internal helpers, triggers, the eleven procedure modules, indexes, security and the build script.
3. Listed what was already in the course database, then replaced the old v3/v4 project tables with v6. The lab tables in the same database (`L8_*`, `DEPARTMENT`, `DEPENDENT`, `EMPLOYEE`, `PROJECT`) were not touched.
4. Compiled all files on the server; all compiled on the first run with no broken references.
5. Wrote `import.sql`, which loads the small data set through the procedures. This was the first functional test of every write procedure.
6. Wrote `tests.sql`, `select.sql`, the generator, `perf.sql` and `bulk_import.sql`.
7. Ran `build_all.sql` twice in a row: zero errors and identical object counts both times, about 63 seconds per run.

### 3.3 What running it found

| Finding | What we did |
|---|---|
| A consumer could read past-month data without buying access when the readings were older than the meter's installation date (test D7 failed) | Fixed: the access check now covers every meter that has data in the requested window |
| With the rule "a month closes when every day of it is final", a meter installed or replaced mid-month would never get a monthly total and never a bill | Changed: the month closes when every full day the meter was in service is final |
| Build spec template T4 passes an expression to `EXEC`, which T-SQL rejects | The procedure passes a variable instead |
| The generator's first random formula gave clustered gaps and spikes | Replaced with a better formula; rates now match the intended 0.5 % and 0.1 % |
| `sqlcmd` here rejects the `-f 65001` flag | Not needed: the UTF-8 files with Greek text load correctly without it |

### 3.4 The small data set

`import.sql` creates, through the procedures only:

- 1 administrator, 2 officers, 1 DSO user, 1 TSO user
- 2 suppliers and 1 aggregator, one user each
- 2 meter types and 2 tariff periods
- 15 transformers in a tree of 4 levels (1 → 2 → 4 → 8), each with a rectangle
- 3 technicians, each with 3 approved documents and 7 days of availability
- 10 consumers with 12 premises, 3 of them prosumers
- 12 meters, each taken through the full installation flow to active
- 2 days of telemetry (the last two days of the previous month): 2,305 packets and 8,063 readings, with a planted spike, a missing slot, a 198.5 V reading, an unknown OBIS code, an unknown network id and a malformed packet
- VEE, an officer edit, finalization, daily and monthly totals, transformer aggregates and the tree state
- 12 bills, one paid in two instalments, one history purchase, one right-to-be-forgotten request and one retention reduction, both taken through all stages

All demo accounts use the password `Passw0rd!23`.

---

## 4. How to build and run

Connection (university VPN required). The password is read from the environment variable `SQLCMDPASSWORD`; never type it on the command line.

```
sqlcmd -S "mssql.cs.ucy.ac.cy\SQL2025" -U <user> -d <database> -C -I -b -W -i <file.sql>
```

`-C` trusts the server certificate, `-I` switches on QUOTED_IDENTIFIER (needed by the filtered indexes), `-b` stops at the first error.

| Step | Command | Expected |
|---|---|---|
| 1. Build | `-i build_all.sql` | Ends with the object counts of section 1 and `build_all.sql finished.` |
| 2. Tests | `-i tests.sql` | Last line `tests.sql: 71 tests, 0 not passed.` |
| 3. Demos | `-i select.sql` | Twenty `=== UC-xx ===` headings, then `select.sql finished.` |

In SSMS, open the file, switch on **Query > SQLCMD Mode** for `build_all.sql`, and run.

**Warning:** `build_all.sql` drops and recreates every project table. All testers share one database unless each uses their own, so agree before anyone rebuilds.

---

## 5. Testing instructions for three testers

`project.pdf` asks every member to work on every stage, so this split is only a split of the testing workload; each tester should still read the other two areas. The areas follow the stakeholders of the PDF.

| Tester | Area | PDF sections | Use cases | Code files |
|---|---|---|---|---|
| **Tester 1** | Consumers, billing, GDPR, login | III common principles, 1.1–1.4 | UC-01 to UC-08 | `procedures_01` (login, consumers), `02`, `08`, `09` |
| **Tester 2** | Technicians, meters, field jobs, remote commands, administration | 2.1–2.4, II.B | UC-09 to UC-14, UC-20 | `procedures_01` (technicians, staff), `03`, `04`, `05`, `11` |
| **Tester 3** | Telemetry, VEE, grid, market data, performance, physical design | 3.1–3.2, 4.1–4.2, 5.1–5.2, IV, Appendix | UC-15 to UC-19 | `procedures_06`, `07`, `10`, `12`, `indexes.sql`, `perf.sql` |

### 5.1 Steps every tester does first

1. Run `tests.sql`. Read the first result set at the end (one row per test). Every row of your sections (table below) must say PASS.
2. Run `select.sql` and read the output of your use cases against the expected results in your section.
3. Do the manual checks of your section in SSMS.
4. Record every finding with: the call you made, what you expected, what happened, and the error number and text.

Sections of `tests.sql` per tester:

| Tester | Test ids |
|---|---|
| Tester 1 | B6 (bills), B7 (GDPR), C06, C07, C10, C12 (guards), D1, D5–D8 (permissions), E1–E5 (login), I1–I2 (GDPR result, purge) |
| Tester 2 | A0, B1–B5 (work orders, meter status, documents, technicians, commands), C04, C05, C08, C11 (guards), D3, D4, H1 (tamper job) |
| Tester 3 | B8, C01–C03, C09 (guards), D2, F1–F4 (VEE), G1–G3 (ingestion), H2–H4 (tree, aggregates), J1–J2 (market data) |

To look up ids for the manual checks:

```sql
SELECT user_id, email, role_code, approval_status FROM dbo.USER_ACCOUNT ORDER BY user_id;
SELECT * FROM dbo.view_PREMISE_METER ORDER BY premise_id;
```

### 5.2 Tester 1 — consumers, billing, GDPR, login

**Automated:** all rows B6, B7, C06, C07, C10, C12, D1, D5–D8, E1–E5, I1, I2 must be PASS.

**In the `select.sql` output check:**

| Use case | What to see |
|---|---|
| UC-01 | Login returns one row with `user_id`, `role_code`, `full_name`, `approval_status`, `organization_id` and no password column |
| UC-02 | The DSO call returns 192 rows for premise 3 (96 slots × 2 codes); the events list shows `VOLTAGE_SAG` |
| UC-03 | Daily totals for the two imported days; monthly total for premise 1 |
| UC-04 | A `THRESHOLD_EXCEEDED` event for premise 1 after the threshold is set to 10 kWh |
| UC-06 | Bills with `paid` and `remaining`; the first bill of consumer 1 is `PAID` with two payments |
| UC-07/08 | Both GDPR requests are `EXECUTED` and the `history` column lists every stage with the officer |

**Manual checks:**

```sql
DECLARE @c3 INT = (SELECT user_id FROM dbo.USER_ACCOUNT WHERE email = 'consumer3@example.cy');
DECLARE @c1 INT = (SELECT user_id FROM dbo.USER_ACCOUNT WHERE email = 'consumer1@example.cy');

-- 1. Wrong password and unknown email give the SAME error (50006 'Login failed.')
EXEC dbo.sp_Login 'consumer3@example.cy', N'wrong';
EXEC dbo.sp_Login 'nobody@example.cy', N'Passw0rd!23';

-- 2. The password is not readable in the table: two binary columns, no text
SELECT email, password_hash, password_salt FROM dbo.USER_ACCOUNT WHERE user_id = @c3;

-- 3. A consumer cannot see another consumer's premise (50002)
EXEC dbo.sp_GetPremiseReadings @c3, 1, '2026-11-01', '2026-11-02', N'1.8.0';

-- 4. Past month without buying access (50008); then buy it and repeat
EXEC dbo.sp_GetPremiseAggregates @c3, 5, 'DAY', '2026-10-30', '2026-11-01';
EXEC dbo.sp_GetHistoricalAccessQuote @c3, 5, '2026-10-01', '2026-10-31';
EXEC dbo.sp_BuyHistoricalAccess @c3, 5, '2026-10-01', '2026-10-31', 'CARD', NULL;
EXEC dbo.sp_GetPremiseAggregates @c3, 5, 'DAY', '2026-10-30', '2026-11-01';

-- 5. Paying more than the remaining amount is refused (50004)
EXEC dbo.sp_GetMyBillsAndPayments @c3, NULL, NULL;
```

Adjust the dates to the previous calendar month if you test after November. Premise 5 and meter 5 belong to consumer 3.

**Concurrency check (two SSMS windows)**, with an `ISSUED` bill of consumer 3 and its full remaining amount:

1. Window 1: `BEGIN TRANSACTION; EXEC dbo.sp_PayBill <consumer>, <bill>, <remaining>, 'CARD', NULL;` and do not commit.
2. Window 2: run the same `EXEC`. It must wait.
3. Window 1: `COMMIT;`
4. Window 2 must now fail with 50003 (bill already paid). The bill must show exactly one payment.

**Also verify:** after the right to be forgotten, the forgotten user's row has `full_name = 'FORGOTTEN USER'`, no phone, no IBAN, `is_active = 0`, and their bills and aggregates still exist.

### 5.3 Tester 2 — technicians, meters, field jobs, remote commands, administration

**Automated:** all rows A0, B1–B5, C04, C05, C08, C11, D3, D4, H1 must be PASS.

**In the `select.sql` output check:**

| Use case | What to see |
|---|---|
| UC-05 | The technician's job list has latitude and longitude columns; after the decline the request is back to `SUBMITTED`; the history shows create, assign, decline, cancel |
| UC-09 | The demo technician stays `PENDING` after resubmitting; a rejected document goes back to `PENDING` |
| UC-10 | `sp_GetMeter` returns three rows, one per certificate; `sp_FindGeofenceForPoint` returns 4 rows (level 1 up to level 4) |
| UC-11 | Premise 6 still has its daily totals after the replacement; the old meter is `REMOVED` with `removed_at` set |
| UC-12 | The command list shows `attempt_count = 2`, status `ACKNOWLEDGED`, and a `history` with two `COMMAND_ATTEMPT` entries |
| UC-13 | Shedding returns `commands_created` equal to the active meters under the transformer |
| UC-14 | The tamper call returns an `event_id` and a `work_order_id`; the job is completed with the persons to notify |
| UC-20 | A new service type and a new OBIS code are added without any schema change |

**Manual checks:**

```sql
DECLARE @off1 INT = (SELECT user_id FROM dbo.USER_ACCOUNT WHERE email = 'officer1@mdms.cy');
DECLARE @tech1 INT = (SELECT user_id FROM dbo.USER_ACCOUNT WHERE email = 'tech1@mdms.cy');
DECLARE @tech2 INT = (SELECT user_id FROM dbo.USER_ACCOUNT WHERE email = 'tech2@mdms.cy');

-- 1. A technician under 18 cannot register (50004)
EXEC dbo.sp_RegisterTechnician 'young@example.cy', N'Passw0rd!23', N'Young Tech', NULL, '2015-01-01', '/p.jpg', N'Ηλεκτρολόγος';

-- 2. Approving a technician without the three approved documents is refused (50004)
DECLARE @demo INT = (SELECT user_id FROM dbo.USER_ACCOUNT WHERE email = 'demo.tech@mdms.cy');
EXEC dbo.sp_DecideTechnician @off1, @demo, 'APPROVED', NULL;

-- 3. A technician cannot accept a job that belongs to another technician (50003)
SELECT work_order_id, status, technician_user_id FROM dbo.WORK_ORDER ORDER BY work_order_id DESC;
EXEC dbo.sp_AcceptWorkOrder @tech2, <a work order assigned to tech1>;

-- 4. Assigning outside the technician's availability is refused (50004)
EXEC dbo.sp_AssignWorkOrder @off1, <a SUBMITTED work order>, @tech1, '2027-06-01 03:00', '2027-06-01 04:00';

-- 5. A meter cannot be activated without its three certificates ('[51004]')
EXEC dbo.sp_ConfirmMeter @off1, (SELECT meter_id FROM dbo.METER WHERE serial_number = 'SN-TEST-0001'), 'APPROVE', NULL;

-- 6. Every step of a job is in the audit trail
EXEC dbo.sp_GetWorkOrderHistory @off1, 1;
```

**Also verify:** in `AUDIT_LOG`, a change of `firmware_version` on a meter appears as one `TECHNICAL_CHANGE` row with the old and the new value, and no row anywhere contains a password or an IBAN.

### 5.4 Tester 3 — telemetry, VEE, grid, market data, performance

**Automated:** all rows B8, C01–C03, C09, D2, F1–F4, G1–G3, H2–H4, J1–J2 must be PASS.

**In the `select.sql` output check:**

| Use case | What to see |
|---|---|
| UC-15 | The packet call returns `match_status = MATCHED` and `readings_inserted = 2` |
| UC-17 | The tree prints 15 rows, indented by depth; every parent's `import_kwh` equals the sum of its children |
| UC-18 | Day-Ahead rows only with `meter_count >= 3`; Intraday rows carry `is_provisional = 1` |
| UC-19 | Voltage report shows meter 3 with one sag and minimum 198.5 V; phase unbalance shows meter 8 at about 117 %; the loss report shows input 0.50 against delivered 0.44 with `possible_theft = 1` |

**Manual checks:**

```sql
DECLARE @off1 INT = (SELECT user_id FROM dbo.USER_ACCOUNT WHERE email = 'officer1@mdms.cy');

-- 1. The PDF's own packet (Appendix p.15): unknown meter -> stored as UNMATCHED, with an event
EXEC dbo.sp_IngestTelemetryPacket N'{"Meter_Network_ID":"EAC-NIC-74921","Transmission_Timestamp":"2026-10-30T12:00:00Z","Cell_Signal_Strength_dBm":-92,"Network_Type":"NB-IoT","Telemetry_Payload":[{"obis":"1.8.0","value":14250.32,"unit":"kWh"},{"obis":"72.7.0","value":198.50,"unit":"V"}]}';
SELECT TOP (3) * FROM dbo.TELEMETRY_PACKET ORDER BY packet_id DESC;
SELECT TOP (3) * FROM dbo.EVENT ORDER BY event_id DESC;

-- 2. A reading lands on the start of its 15-minute slot
SELECT dbo.fn_Floor15('2026-10-30 12:07:31');      -- expected 2026-10-30 12:00:00

-- 3. A finalized reading cannot be changed, even directly ('[51001]')
UPDATE dbo.METER_READING SET [value] = 0 WHERE reading_id = (SELECT MIN(reading_id) FROM dbo.METER_READING WHERE is_final = 1);

-- 4. The edited reading keeps the original value and the editor
SELECT reading_timestamp, [value], original_value, status, vee_rule, edited_by_user_id
FROM dbo.METER_READING WHERE status = 'EDITED';

-- 5. A supplier never sees another supplier's customers
DECLARE @s1 INT = (SELECT user_id FROM dbo.USER_ACCOUNT WHERE email = 'billing@eacsupply.cy');
EXEC dbo.sp_GetPortfolioSummary @s1;
```

**Performance work (needs a database with room, see section 7):**

1. On a local SQL Server, run `build_all.sql`, then as the administrator
   `EXEC dbo.sp_GenerateSyntheticData @actor_user_id = <admin id>, @consumers = 2000, @days = 30;`
   (about 29 million readings; lower `@days` on a small machine).
2. Run VEE and finalization on the generator's raw last day, then `sp_BuildTransformerAggregates` and `sp_RefreshTransformerState`.
3. Run `perf.sql` as it is. Record the result table of PART 1 (p95 per procedure, target under 2,000 ms) and the PART 3 table and messages (logical reads and times with and without `IX_METER_READING_obis_slot`).
4. In SSMS, run PART 3 with **Include Actual Execution Plan** on and save the two plans (scan without the index, seek with it) for the documentation.

### 5.5 What "pass" means for the whole team

- `build_all.sql` runs twice in a row with no error.
- `tests.sql` shows 71 PASS on a fresh build and again after `select.sql`.
- Every manual check above gives the stated error number or result.
- No call returns a password, hash or salt.

---

## 6. One-to-one map on `project.pdf`

Status: **Done** = implemented, deployed and exercised by `import.sql`, `select.sql` or `tests.sql`. **Partial** and **Open** are explained in the row.

### 6.1 Section I — goal and general conditions (p.1–2)

| PDF requirement | Where it is | Status |
|---|---|---|
| Everything is recorded in one relational database (p.2) | `create.sql`, 24 tables | Done |
| Operational scenarios through a simple web application (p.2) | `sources/` | Open: not started |
| Reports for management, analytic scenarios (p.2) | `sp_ReportSystemStatistics`, the DSO reports, the aggregates | Done (database side) |
| Design allows new, unknown services later (p.2) | Row-based reference tables: `METER_TYPE`, `OBIS_CODE`, `SERVICE_TYPE`, `TARIFF`; free-text `EVENT.event_type`; see 6.6 | Done |
| Microsoft SQL Server 2025 or 2022 (p.2) | Built and run on SQL Server 2025 | Done |
| Most of the logic lives in the database as stored queries and scripts (p.2) | 110 procedures; the application role cannot touch tables directly | Done |
| Leaflet maps, +10 % (p.2) | `view_METER_LOCATION`, `sp_ListMeters`, `sp_GetTransformerTree` return coordinates and rectangles | Partial: data ready, no map page |
| Phase B: schema in SQL, operations in T-SQL, interface, documentation (p.2) | Sections 6.2–6.7 | Partial: interface and documentation open |

### 6.2 Section II — the five stakeholders (p.3–4)

| PDF requirement | Where it is | Status |
|---|---|---|
| A. Consumers register themselves and their premises, follow 15-minute series, compare import and export, ask for checks, GDPR (p.3) | `procedures_02`, `03`, `09`; UC-01 to UC-08 | Done |
| B. Technicians install, check and maintain meters; record calibration documents, phases, amps, photos, notes (p.3) | `sp_InstallMeter`, `sp_AddMeterDocument`, `METER_TYPE`, `sp_CompleteWorkOrder`; UC-10 | Done |
| B. Jobs tracked with approvals, state and history (p.3) | `WORK_ORDER` state machine, `tr_WORK_ORDER_audit`, `sp_GetWorkOrderHistory` | Done |
| B. Authorised network commands, every action, approval and result logged (p.3) | `procedures_05`, `tr_REMOTE_COMMAND_audit`; UC-12 | Done |
| C. DSO: automated VEE finds missing or invalid readings and estimates or corrects them (p.3) | `sp_RunVEE`, `sp__EstimateGaps`, `sp_EditReading`; UC-16 | Done |
| C. Analytics: voltage sags and swells (p.3) | `sp_ReportVoltageEvents`; events at ingestion | Done |
| C. Analytics: technical losses (p.3) | `sp_ReportTechnicalLosses` | Done |
| C. Analytics: phase unbalance (p.3) | `sp_ReportPhaseUnbalance` | Done |
| C. Analytics: suspicious events that may be theft (p.3) | Loss above 8 % flagged together with tamper alerts in `sp_ReportTechnicalLosses` | Done |
| D. TSO: grid frequency near 50 Hz, deviations recorded (p.3) | `sp_RecordTransformerReading`, OBIS 14.7.0, event `FREQUENCY_DEVIATION` | Done |
| D. TSO: every 15 minutes an overall picture of transformers and loads (p.3) | `sp_GetGridOverview`, `sp_GetTransformerState` | Done |
| D. TSO manages the spatial organisation through Geofences (p.3) | `sp_UpsertTransformer`, `fn_FindGeofence`, `tr_TRANSFORMER_tree_guard` | Done |
| D. Remote shedding on all meters of a transformer (p.3) | `sp_ShedTransformerLoad`; UC-13 | Done |
| E. Consumers choose their supplier (p.4) | `sp_ChangeSupplier`; bills keep the supplier they were issued by | Done |
| E. Suppliers and aggregators pull aggregates per area or transformer through APIs (p.4) | `procedures_10`; the "API" is the procedure call | Done (database side) |

### 6.3 Section III — functional requirements

**Common principles (p.5)**

| PDF requirement | Where it is | Status |
|---|---|---|
| One account per person, identified before every protected function | `USER_ACCOUNT`, `sp_Login`, `sp__AssertRole` in every procedure | Done |
| Passwords only in irreversible form, not visible even with table access | Salted SHA2-512 in `fn_HashPassword`; never returned or logged; tests E1–E5 | Done |
| Administrator is the root role, may be created by hand | `sp_BootstrapAdmin` (works only while no administrator exists) | Done |
| Officers are created by the administrator | `sp_CreateStaffUser` | Done |
| Officers check technician registrations, technical documents and meters | `sp_DecideDocument`, `sp_DecideTechnician`, `sp_ConfirmMeter` | Done |
| Officers define meter models, service types and tariffs | `sp_UpsertMeterType`, `sp_UpsertServiceType`, `sp_UpsertTariff` | Done |
| Every critical state change is traceable: object, user or mechanism, time, old and new state, result or comment | `AUDIT_LOG` with seven audit triggers and `sp__Log`; `tr_AUDIT_LOG_append_only` | Done |
| A function with several related changes is one atomic action | Transaction template in every write procedure; test C04b | Done |

**1. Consumers and premises (p.5–7)**

| PDF | Requirement | Where it is | Status |
|---|---|---|---|
| 1.1 | Self-registration without pre-approval | `sp_RegisterConsumer` | Done |
| 1.1 | One consumer, several premises | `PREMISE.user_id`; `sp_AddPremise` | Done |
| 1.1 | Premise ID, address, WGS84, usage (4 kinds), district, municipality, parish, postal code | `PREMISE` columns and CHECKs | Done |
| 1.1 | Payment / bank details linked to consumer or premise | `USER_ACCOUNT.iban`, `PAYMENT` | Done |
| 1.2 | 15-minute series of the consumer's own active meters | `sp_GetPremiseReadings`; test D1 | Done |
| 1.2 | Prosumers (Net Billing, Net Metering) see import and export separately | `PREMISE.prosumer_scheme`; 2.8.0 returned only for prosumers | Done |
| 1.2 | Undervoltage and overvoltage events shown to the user | `VOLTAGE_SAG` / `VOLTAGE_SWELL` events; `sp_GetPremiseEvents`; test G2 | Done |
| 1.2 | Consumption thresholds | `sp_SetPremiseThreshold`, `tr_AGGREGATE_threshold_alert`, `sp_CheckConsumptionThresholds` | Done |
| 1.2 | Notification preferences, email or SMS | `notify_email`, `notify_sms`; `sp_UpdateMyProfile` | Partial: preference stored and event raised; sending is for the PHP layer |
| 1.2 | Current month free; earlier months for an extra charge | `fn_CanViewReadings`, `sp_GetHistoricalAccessQuote`, `sp_BuyHistoricalAccess`; tests D7, D8 | Done |
| 1.2 | Paid access limited by the user's retention period | Retention check in `fn_CanViewReadings` and in the purchase | Done |
| 1.2 | Daily, monthly, yearly aggregates for history; same access rules | `AGGREGATE`, `sp_GetPremiseAggregates` | Done |
| 1.3 | Check request or fault report with state and history, assigned to a technician | `sp_SubmitServiceRequest` and the work-order flow; UC-05 | Done |
| 1.3 | History of charges and payments | `sp_GetMyBillsAndPayments` | Done |
| 1.3 | Payment links consumer, supplier, charge and any MDMS-Cy service fee | `BILL`, `PAYMENT`, `SERVICE_TYPE`; `sp_PayBill`, `sp_PayServiceFee` | Done |
| 1.3 | No dynamic pricing algorithm required | Bill = kWh × tariff rate; prosumers billed on import minus export | Done |
| 1.4 | Detailed data only for authorised users; aggregates preferred for statistics | Ownership checks; market procedures return only groups of 3 meters or more | Done |
| 1.4 | Right to be forgotten through submission, review, pre-approval, final approval, each logged | `sp_SubmitGdprRequest`, `sp_AdvanceGdprRequest`, `tr_GDPR_REQUEST_audit`; tests B7a–e | Done |
| 1.4 | After approval personal data is removed; accounting data stays | `sp_ExecuteGdprRequest`; `tr_BILL_no_delete`, `tr_PAYMENT_no_delete`; test I1 | Done |
| 1.4 | Raw 15-minute readings kept 3 years, then deleted; aggregates stay | `METER.retention_months = 36`, `sp_PurgeExpiredReadings`; test I2 | Done |
| 1.4 | Retention reduced to 1 month through an approved request; older raw rows deleted | `RETENTION_REDUCTION` request; `sp__PurgeMeter` | Done |
| 1.4 | Transformer measurements kept permanently | `TRANSFORMER_READING` is never purged | Done |

**2. Technicians and meters (p.7–8)**

| PDF | Requirement | Where it is | Status |
|---|---|---|---|
| 2.1 | Self-registration; no jobs before officer approval | `sp_RegisterTechnician` (PENDING); `tr_WORK_ORDER_technician_guard`; tests D3, C05 | Done |
| 2.1 | At least one category by specialty | `USER_ACCOUNT.specialty` | Partial: one specialty per technician (stated limit) |
| 2.1 | Daily availability in time and area | `TECHNICIAN_AVAILABILITY`; `sp_SetAvailability`, `sp_FindAvailableTechnicians` | Done |
| 2.1 | Email, birth date, photo; ID card, installer licence, training certificate | `USER_ACCOUNT` technician columns; `DOCUMENT` | Done |
| 2.1 | Per document: code, issue date, expiry date, electronic copy | `DOCUMENT` columns | Done |
| 2.1 | Approval, rejection and status changes recorded | `tr_USER_ACCOUNT_audit`, `tr_DOCUMENT_audit` | Done |
| 2.2 | Jobs: installation, replacement, technical check, anti-tamper | `WORK_ORDER.work_type` (plus fault repair) | Done |
| 2.2 | Job linked to premise or meter, technician, type, schedule, state, result | `WORK_ORDER` columns | Done |
| 2.2 | Technician accepts jobs and sees the meter's position | `sp_AcceptWorkOrder`, `sp_ListMyWorkOrders` with coordinates | Done |
| 2.2 | Notes, findings and evidence are part of the job history | `findings`, `evidence_path`; `sp_GetWorkOrderHistory` | Partial: one evidence file per job (stated limit) |
| 2.3 | Meter matched to Premise ID with serial, type, firmware, communication type, phases, amps | `sp_InstallMeter`; `METER`, `METER_TYPE` | Done |
| 2.3 | Installation photos and the three equipment certificates | `installation_photo`; `sp_AddMeterDocument` | Done |
| 2.3 | Not active until the officer checks and confirms | `sp_ConfirmMeter`; `tr_METER_activation_guard`; test C04a | Done |
| 2.3 | Only an active meter takes readings | Ingestion marks packets of other meters `QUARANTINED`; test G1 | Done |
| 2.3 | Replacement keeps the older series of the premise | `sp_ReplaceMeter`; old meter kept as `REMOVED`; UC-11 | Done |
| 2.4 | Remote commands: disconnect, reconnect, firmware upgrade | `sp_RequestRemoteCommand` | Done |
| 2.4 | Command record with requester, executor, target, time, state, successive attempts until ACK | `REMOTE_COMMAND`, `sp_DispatchCommands`, `sp_AcknowledgeCommand`; tests B5a–d | Done |
| 2.4 | Anti-tamper checks: technician, date, findings, persons to notify | `sp_CompleteWorkOrder` requires `persons_to_notify` for anti-tamper jobs | Done |
| 2.4 | Critical events link to the Event Log and can create a field job | `EVENT`, `sp_RaiseTamperEvent`, `tr_EVENT_work_order`; test H1 | Done |

**3. DSO — ingestion and VEE (p.8–9)**

| PDF | Requirement | Where it is | Status |
|---|---|---|---|
| 3.1 | Packets carry network id, timestamp, communication info, OBIS/value pairs | `sp_IngestTelemetryPacket` reads the Appendix JSON | Done |
| 3.1 | Match to an existing, active meter, then store with the 15-minute timestamp, unit and code | Algorithm A; `fn_Floor15`; `METER_READING` | Done |
| 3.1 | Unmatched or faulty packets recorded as failures or events, never lost silently | `TELEMETRY_PACKET.match_status`; `tr_TELEMETRY_PACKET_failure_event`; test G1 | Done |
| 3.1 | At least the Appendix OBIS codes | `OBIS_CODE` reference rows | Done |
| 3.1 | Not every packet has every code; new codes without redesign | One row per reading; `sp_UpsertObisCode` | Done |
| 3.2 | Validation: supported code, limits, gaps, inconsistencies | Rules RANGE, NEGATIVE_DELTA, SPIKE, OVER_CAPACITY; unsupported code event; test G3 | Done |
| 3.2 | The example 1.8 / 2.0 / 1.9 / 25.4 is flagged as suspect | Test F1 | Done |
| 3.2 | The missing 10:30 reading is estimated as 2.1 and stored as estimated | Test F3 | Done |
| 3.2 | Editing keeps original value, corrected value and origin | `original_value`, `edited_by_user_id`, `tr_METER_READING_edit_audit`; test F4 | Done |
| 3.2 | After VEE readings are final and immutable | `sp_FinalizeReadings`; `tr_METER_READING_immutable`; tests C01, B8 | Done |
| 3.2 | Finalization triggers the aggregates, computed only from final readings | Daily, monthly, yearly totals written inside finalization | Done |
| 3.2 | Aggregates are final and immutable | `tr_AGGREGATE_immutable`; tests C02a, C02b | Done |

**4. TSO — topology and state (p.9–10)**

| PDF | Requirement | Where it is | Status |
|---|---|---|---|
| 4.1 | Every meter has WGS84 coordinates and hangs on one low-voltage transformer | `METER` columns; `tr_METER_transformer_guard`; test C08 | Done |
| 4.1 | Geofence as polygon or, simpler, a rectangle | Rectangle on `TRANSFORMER` (min/max latitude and longitude) | Done (rectangle) |
| 4.1 | From a meter's coordinates find its Geofence and transformer | `fn_FindGeofence`; used by `sp_InstallMeter` | Done |
| 4.1 | Hierarchy of arbitrary depth L1 … Ln | `TRANSFORMER.parent_transformer_id`; recursive `sp_GetTransformerTree`; tests C09, H4 | Done |
| 4.2 | Latest VEE-verified picture for the whole hierarchy, 15-minute resolution | `sp_RefreshTransformerState` | Done |
| 4.2 | Higher levels include all meters below, whatever the depth | `sp__SumSubtree` (recursive); test H2 | Done |
| 4.2 | SUM only for 1.8.0 and 2.8.0 | CHECK on `TRANSFORMER_CURRENT_STATE.obis_code` | Done |
| 4.2 | Intermediate table with Geofence id, reference slot common to all, OBIS code, SUM | `TRANSFORMER_CURRENT_STATE` | Done |
| 4.2 | Started by hand by an authorised user | Procedure call by TSO or DSO | Done |
| 4.2 | Missing readings are ignored | Only readings that exist at the slot are summed | Done |
| 4.2 | A reading that affects an L1 updates it and all its ancestors | `sp_RefreshTransformerAncestors` | Done |
| 4.2 | Final readings and historical aggregates kept as immutable data | `sp_BuildTransformerAggregates`; test H3 | Done |

**5. Suppliers and aggregators (p.10–11)**

| PDF | Requirement | Where it is | Status |
|---|---|---|---|
| 5.1 | Access only to the customers or portfolios they represent | Organization taken from the user row, never from a parameter; tests D2, J1 | Done |
| 5.1 | No uncontrolled access to raw data | Only aggregated result sets; groups under 3 meters suppressed | Done |
| 5.1 | Per period and Geofence: import, export, net | `sp_GetDayAheadAggregates` | Done |
| 5.2 | Day-Ahead: daily totals from stored, validated data | From final daily aggregates | Done |
| 5.2 | Intraday: straight from the latest readings, before VEE completes | `sp_GetIntradayProvisional`, marked provisional | Done |
| 5.2 | Forecasting algorithms are not required | Not implemented, as allowed | Not required |

### 6.4 Appendix — OBIS codes and packet format (p.15)

| PDF requirement | Where it is | Status |
|---|---|---|
| 1.8.0, 1.8.1, 1.8.2, 2.8.0, 3.8.0, 4.8.0 energy registers | `OBIS_CODE`, kind CUMULATIVE | Done |
| 32.7.0, 52.7.0, 72.7.0 voltages; 31.7.0, 51.7.0, 71.7.0 currents | `OBIS_CODE`, kind INSTANTANEOUS | Done |
| Currents feed the phase-unbalance report | `sp_ReportPhaseUnbalance` | Done |
| The JSON packet structure | Parsed field by field in `sp_IngestTelemetryPacket` | Done |
| The 198.50 V value of the example | Raises `VOLTAGE_SAG` (below 207 V) | Done |

### 6.5 Section IV — implementation topics (p.12–13)

| PDF requirement | Where it is | Status |
|---|---|---|
| Basic interface over PHP and SQLSRV that performs all functions | `sources/` | Open: not started |
| A user must enter the password to get access | `sp_Login` | Done (database side) |
| Small synthetic data set for checking | `import.sql` | Done |
| Large data set, of the order of thousands of rows, part of the grade | `sp_GenerateSyntheticData`. The small set already has about 8,000 readings and 4,700 aggregates. The large run is blocked by the 27 MB quota | Partial |
| State the three main indexes: which, why, how | Documented as IX1–IX3 in `indexes.sql` | Done in code; to copy into `docx/` |
| Avoid and document contention points | Two documented: last-page inserts on identity keys (`OPTIMIZE_FOR_SEQUENTIAL_KEY`) and the current-state table (computed in temp tables, one short write under an application lock) | Done in code; to copy into `docx/` |
| Under 2 seconds for 95 % of OLTP queries over 10,000 requests | `perf.sql` PART 1. A 100-call check on the small data gave p95 of about 34 ms, which proves nothing about the large set | Open: not measured |
| At least one case where an index or a better query lowers the cost | `perf.sql` PART 3 | Open: not measured |
| Unauthorised access | Role `mdms_app` with EXECUTE only and direct table access denied (deployed); role and ownership checks in every procedure | Done |
| SQL injection | Static, parameterised procedures; `{call ...}` with parameters in PHP | Done (database side) |
| Concurrency: intermediate tables, transactions, isolation levels | Guarded updates, row lock when paying, application locks for jobs, temp-table buffering, read-committed snapshot | Done; two-window test is manual (section 5.2) |
| Future extension without changing the structure | See 6.6 | Done |

### 6.6 Future extension (p.13) — how each example is covered

| PDF example | How it is added |
|---|---|
| New meter types | A row in `METER_TYPE` through `sp_UpsertMeterType` |
| New telemetry protocols | `TELEMETRY_PACKET.network_type` is free text; `METER.communication_type` is a CHECK list that grows with one `ALTER` |
| New prosumer classes | `PREMISE.prosumer_scheme` is a CHECK list that grows with one `ALTER` |
| New VEE rules | `METER_READING.vee_rule` is free text; a rule is one more `UPDATE` in `sp_RunVEE` |
| New measured quantities | A row in `OBIS_CODE` through `sp_UpsertObisCode` (shown in UC-20) |
| New services and tariffs | Rows in `SERVICE_TYPE` and `TARIFF` |
| New event kinds | `EVENT.event_type` has no CHECK |

The two CHECK lists are an extension of a constraint, not a change of structure.

### 6.7 Section V — Phase B deliverables (p.13–14)

| Deliverable | State | What is left |
|---|---|---|
| `sources/` — application source | Open | Write the PHP / HTML pages; every page only calls a procedure |
| `sql/` — `create.sql`, `drop.sql`, `import.sql`, `select.sql`, `indexes.sql`, … | Done | Move the files from `phaseB/` into `sql/`; `build_all.sql` works unchanged if run from that folder |
| `data/` — `.dat` files that can be imported | Open | Export with `bcp` and test `bulk_import.sql` on a server where the login may bulk load |
| `docx/` — user manual: usage, design choices, extra functions, difficulties, final ER diagram, data dictionary, limits, improvements | Open | To write; sections 3, 6 and 7 of this report are raw material |
| `docx/` — separate document: (a) contention points, (b) security, (c) future extension | Open | To write; the content exists in `indexes.sql`, `security.sql` and section 6.6 |
| Printed `docx/` for the lab | Open | After the two documents are written |
| Oral examination: every member shows design and implementation | — | `select.sql` is the demo script |

---

## 7. Open items, limits and decisions

### 7.1 Decisions needed

| Decision | Options | Suggestion |
|---|---|---|
| Where to run the large data set and the performance test | Ask for a larger quota; free a few MB on the course server; use a local SQL Server | Local SQL Server: the PDF's target is measured "on your PC", and only this option has room for millions of rows |
| How to produce the `.dat` files | Install the Microsoft command-line tools (`bcp`) and export from the local server | Do it together with the large data set |

### 7.2 Not possible on the course server

- The data file is capped at 27 MB. The generator ran out of space at 200 consumers × 3 days and again at 8 consumers × 3 days; it was verified at 4 consumers × 2 days inside a transaction that was rolled back.
- The login is not allowed to bulk load, so `bulk_import.sql` cannot run there.
- `CREATE ROLE`, the grants and denies, and snapshot reads were all permitted and are live.

### 7.3 Where our implementation differs from the build spec

- Month totals close on "every full day in service", not "every day of the month" (section 3.3).
- Jobs that commit per entity (purge, bill run, tree refresh) hold a session-level lock instead of a transaction-level one.
- `sp_RaiseTamperEvent` and `sp_RecordTransformerReading` take an optional user id first: empty for a device, a user id for a DSO.
- The bill-run atomicity test of the spec is replaced by an atomicity test on meter confirmation, because a bill run could not be made to fail for one premise without breaking another rule.
- The generator writes history days as already validated and leaves only the last day raw for VEE.

### 7.4 Known limits to state in the documentation

- One specialty per technician and one evidence file per job.
- No history of supplier changes other than what the bills keep; no tenant history for a premise.
- A Geofence is a rectangle, not a polygon.
- Events have no "closed" state; the grid overview counts critical events of the last 24 hours.
- Email and SMS are not sent by the database; it records the preference and raises the event.
- The day a meter is installed or removed is not finalized (it cannot have 96 slots), so that day's energy is not billed.

### 7.5 Next steps

1. Set up the local SQL Server, run `build_all.sql`, the generator and `perf.sql`; save the numbers and the two execution plans.
2. Export the `.dat` files and test `bulk_import.sql`.
3. Build the PHP pages per stakeholder, starting from the calls in `select.sql`.
4. Write the user manual and the three-topic document.
5. Assemble the zip (`sources/`, `sql/`, `data/`, `docx/`).
