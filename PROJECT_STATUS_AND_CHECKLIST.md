# MDMS-Cy — status, 1:1 map on `project.pdf`, and the team checklist

**Group 10 · EPL342 · written 18/11/2026 · Phase B deadline: Friday 4/12/2026, 12:00 (16 days)**
Sources: `project.pdf` (re-read in full on 18/11), `REPORT.md` (11/11), the `io` branch after merging `Kostis` and Eliana's tests.

---

## 1. Where we stand (checked today, not copied from the old report)

Everything below was run on **`mssql.cs.ucy.ac.cy` (SQL Server 2022)**, database `ichara09`, from a clean `build_all.sql`.

| Check | Result |
|---|---|
| `build_all.sql` (24 tables, 8 views, 10 functions, 23 triggers, 110 procedures, 14 indexes, `import.sql`) | OK, 0 errors |
| `tests.sql` (includes Kostis's `fn_Floor15` tests K1, K2) | **73 / 73 PASS** |
| `select.sql` (UC-01 … UC-20 demos) | runs with 0 errors; all 20 use cases appear (UC-07/08 share one heading) |
| Eliana's telemetry tests, ported (`sql/test_*.sql`) | **26 / 26 PASS**, each cleans its own data |
| The code runs on SQL Server **2022**, which `project.pdf` p.2 allows ("2025 or 2022") | yes |

**The database side of Phase B is complete. What is missing is everything the course grades *around* it:** the PHP/HTML interface, the large data set and the performance evidence, the `.dat` files, the two written documents, and the final zip.

### Two corrections to `REPORT.md`
1. **The large data set is "of the order of thousands of rows" (p.12), not millions.** `REPORT.md` planned ~29 million readings (2,000 consumers × 30 days) and concluded that only a local server can hold them. A set of **tens of thousands** of rows is enough for the requirement and for a visible index before/after. It may even fit the course database, but the cap is real (see 4).
2. **Server and numbers moved on:** the project now runs on SQL Server 2022 (not `...\SQL2025`), tests are 73 (not 71) plus 26 telemetry checks, and the telemetry tests live in `sql/`.

---

## 2. One-to-one map: `project.pdf` → what we implemented

Status: **Done** = implemented and exercised by `tests.sql`, `select.sql` or `import.sql`. **Partial** / **Open** are explained. Page numbers are the PDF's own.
(The same map in full detail, row by row, is in `REPORT.md` §6; this table is the checked, condensed version.)

### I. Goal and conditions (p.1–2)
| PDF | Requirement | Implementation | Status |
|---|---|---|---|
| p.2 | One relational DB (OLTP) + reports (OLAP-style) | `create.sql` (24 tables); `sp_ReportSystemStatistics`, DSO reports, aggregates | Done |
| p.2 | SQL Server 2025 or 2022; logic in stored queries/scripts | 110 procedures; role `mdms_app` has EXECUTE only | Done |
| p.2 | **Web application** (HTML/PHP) for the operational scenarios | `sources/` is empty | **Open** |
| p.2 | +10 % for sophisticated interaction / Leaflet maps | coordinates + rectangles are returned by `view_METER_LOCATION`, `sp_ListMeters`, `sp_GetTransformerTree`; no page | **Open** (bonus) |
| p.2 | Phase A (30 %): ER + relational schema + assumptions (deadline was 19/10) | `phaseA/` holds the ER diagram, relational schema and `create.sql` | Done (files present; the final v6 ER still goes into `docx/`) |

### II. Scenario — five stakeholders (p.3–4)
| Stakeholder | Implemented by | Status |
|---|---|---|
| A. Consumers/premises | `procedures_01/02/08/09`; UC-01…UC-08 | Done (DB) |
| B. Field technicians | `procedures_01/03/04/05`; UC-09…UC-14 | Done (DB) |
| C. DSO (VEE, analytics) | `procedures_06/07`; UC-15, 16, 19 | Done (DB) |
| D. TSO (frequency, geofences, shedding) | `procedures_05/07`; UC-13, UC-17 | Done (DB) |
| E. Suppliers / aggregators | `procedures_10`; UC-18 | Done (DB) |

### III. Functional requirements (p.5–11)
| PDF § | Requirement | Where | Evidence | Status |
|---|---|---|---|---|
| Common | Unique account, login before every protected function | `sp_Login`, `sp__AssertRole` in every procedure | E1–E5 | Done |
| Common | Passwords irreversible, not readable even with table access | `fn_HashPassword` (salted SHA2-512), never returned | E1–E5 | Done |
| Common | Admin = root, created by hand; officers created by admin | `sp_BootstrapAdmin`, `sp_CreateStaffUser` | import | Done |
| Common | Officers define meter types, service types, tariffs | `sp_UpsertMeterType/ServiceType/Tariff` | UC-20 | Done |
| Common | Every critical change traceable (who, when, old/new, result) | `AUDIT_LOG`, 7 audit triggers, `sp__Log`, append-only trigger | C-series | Done |
| Common | Multi-step function = one atomic action | transaction + `XACT_ABORT` + rollback in every write procedure | C04b | Done |
| 1.1 | Self-registration; premises (ID, address, WGS84, usage, district…) | `sp_RegisterConsumer`, `sp_AddPremise` | import | Done |
| 1.2 | Own 15-min series; prosumers see import and export | `sp_GetPremiseReadings` | D1 | Done |
| 1.2 | Voltage events, thresholds, email/SMS preference | `VOLTAGE_*` events, `sp_SetPremiseThreshold`, `tr_AGGREGATE_threshold_alert` | G2, UC-04 | **Partial**: preference stored and event raised; actually *sending* email/SMS is for the web layer |
| 1.2 | Current month free; older months paid; limited by retention | `fn_CanViewReadings`, `sp_BuyHistoricalAccess` | D7, D8 | Done |
| 1.2 | Daily/monthly/yearly aggregates, same access rules | `sp_GetPremiseAggregates` | UC-03 | Done |
| 1.3 | Check/fault request with state + history, assigned to a technician | `sp_SubmitServiceRequest` + work-order flow | UC-05 | Done |
| 1.3 | Charges/payments history; payment links consumer, supplier, fee | `BILL`, `PAYMENT`, `sp_PayBill`, `sp_PayServiceFee` | B6, UC-06 | Done |
| 1.4 | Right to be forgotten: submit → review → pre-approve → approve, logged | `sp_SubmitGdprRequest`, `sp_AdvanceGdprRequest`, `sp_ExecuteGdprRequest` | B7a–e, I1 | Done |
| 1.4 | Raw 15-min kept 3 years (1 month after approved request); aggregates stay; transformer data permanent | `retention_months`, `sp_PurgeExpiredReadings` | I2 | Done |
| 2.1 | Technician self-registers, no jobs before approval; ≥1 specialty; availability; documents | `sp_RegisterTechnician`, `tr_WORK_ORDER_technician_guard`, `sp_SetAvailability` | D3, C05 | Done (one specialty per technician, a stated limit) |
| 2.2 | Jobs: installation, replacement, check, anti-tamper; accept; see location; history | `procedures_03` | B1, UC-05 | Done (one evidence file per job, a stated limit) |
| 2.3 | Install meter (serial, type, firmware, phases, amps, photos, 3 certificates); inactive until officer confirms; replacement keeps history | `sp_InstallMeter`, `sp_AddMeterDocument`, `sp_ConfirmMeter`, `sp_ReplaceMeter` | C04a, UC-10/11 | Done |
| 2.4 | Remote commands with logged attempts until ACK; tamper → event → new job | `procedures_05`, `sp_RaiseTamperEvent`, `tr_EVENT_work_order` | B5a–d, H1 | Done |
| 3.1 | Ingest JSON packet, match to an active meter, store at 15-min slot; unmatched/faulty are logged, never lost; Appendix OBIS codes; not every code present | `sp_IngestTelemetryPacket`, `fn_Floor15`, `OBIS_CODE` | G1–G3, **T1–T3, S1–S6** (Eliana), K1–K2 (Kostis) | Done |
| 3.2 | Validation (range, gaps, inconsistencies), the 1.8/2.0/1.9/**25.4** example, the **10:30 → 2.1** estimate, editing keeps original/corrected/origin | `sp_RunVEE`, `sp__EstimateGaps`, `sp_EditReading` | F1–F4, **R0–R4, D0–D7** | Done |
| 3.2 | After VEE readings are final/immutable; aggregates only from final data and immutable | `sp_FinalizeReadings`, triggers TR01/TR02 | C01, C02, B8 | Done |
| 4.1 | Meter has WGS84 + one LV transformer; geofence = rectangle; hierarchy L1…Ln; find geofence from coordinates | `TRANSFORMER` tree, `fn_FindGeofence` | C08, C09, H4 | Done (rectangle, not polygon) |
| 4.2 | Current state per geofence (SUM of 1.8.0 / 2.8.0), manual trigger, missing readings ignored, ancestors updated | `sp_RefreshTransformerState`, `sp_RefreshTransformerAncestors` | H2 | Done |
| 4.2 | Immutable historical aggregates per transformer | `sp_BuildTransformerAggregates` | H3 | Done |
| 5.1 | Suppliers/aggregators: aggregated data only, only their customers | `procedures_10`, groups < 3 meters suppressed | D2, J1, J2 | Done |
| 5.2 | Day-Ahead (final aggregates) and Intraday (latest, before VEE completes) | `sp_GetDayAheadAggregates`, `sp_GetIntradayProvisional` | UC-18 | Done (forecasting not required) |
| App. | OBIS codes 1.8.0/1.8.1/1.8.2/2.8.0/3.8.0/4.8.0, voltages, currents; JSON structure | `OBIS_CODE`, parsed field by field | G1–G3, T1–T3 | Done |

### IV. Implementation topics (p.12–13)
| PDF | Requirement | Where | Status |
|---|---|---|---|
| p.12 | Interface: PHP + SQLSRV driver + HTML (JS/AJAX/Leaflet optional); login by code/password | — | **Open** |
| p.12 | Small data set (to check the implementation) | `import.sql` (2,305 packets, 8,063 readings, 12 meters…) | Done |
| p.12 | **Large data set "of the order of thousands of rows"**, part of the grade; use ChatGPT/tools to generate | `sp_GenerateSyntheticData` exists, verified only on a tiny run | **Partial** (not run at scale) |
| p.12 | State the **3 most important indexes**: which, why, how | `indexes.sql` (IX1–IX3 documented in comments) | Done in code, **text for `docx/` open** |
| p.12 | Avoid and document **contention points** | `OPTIMIZE_FOR_SEQUENTIAL_KEY`, current-state table via temp tables + one short write under app lock | Done in code, **text open** |
| p.12 | **< 2 s for ≥ 95 % of OLTP queries over 10,000 requests**; one case where an index or a better query lowers the cost | `perf.sql` (PART 1 and PART 3) | **Open: never run at scale** |
| p.13 | Security: unauthorised access, SQL injection | role `mdms_app` (EXECUTE only), role checks, parameterised procedures | Done in DB; **PHP side open + text open** |
| p.13 | Concurrency: intermediate tables, transactions, isolation levels | guarded updates, `UPDLOCK/HOLDLOCK` on payment, app locks, temp tables, read-committed snapshot | Done; two-window demo is manual (`tests.sql` footer) |
| p.13 | Future extension without changing structure | row-based reference tables (`REPORT.md` §6.6) | Done in code, **text open** |

### V. Deliverables (p.13–14)
| Deliverable | State |
|---|---|
| `sources/` application source | **Open** |
| `sql/` — `create.sql`, `drop.sql`, `import.sql`, `select.sql`, `indexes.sql`, … | Done, but files still sit in `phaseB/` root: **move into `sql/`** |
| `data/` — `.dat` files importable into the DB | **Open** (`bulk_import.sql` written, never run; login may lack `BULK INSERT`) |
| `docx/` user manual (usage, design choices, extra functions, difficulties, final ER, data dictionary, limits, improvements) | **Open** |
| `docx/` separate document: (a) contention points, (b) security, (c) future extension | **Open** |
| Printed `docx/` for the lab | **Open** |
| Moodle: `10.zip` (sources, sql, data, docx) | **Open** |
| Oral exam: every member presents design *and* implementation | Preparation open |

---

## 3. What is left — by size of the grade at stake

*Checked on 25/11/2026 at `io` `c1ce774` plus the documents of D4, D8 and D9. (Section 1 and the status columns of section 2 are still those of 18/11.)*

| # | Area | State | Done | Still open |
|---|---|---|---|---|
| 1 | **Web application** | Pages done | B1–B11 have code; 531 page × role requests, 0 failed (`evidence/C6-integration-2`). B2, B4, B7–B10 and the consumer pages also pass on SQL Server 2025 / Windows (`evidence/D9`) | POST flows of the technician and staff pages (B5, B6) have no test; final choice of server for the demo |
| 2 | **Large data set + performance** | Done | C1 (16,127 readings), C2 (10,000 calls, p95 22.71 ms, 0 failed), C3 (plans with / without index) | — |
| 3 | **Documentation** | Partly done | D2 consumer, D2 supplier (draft), **D4** DSO + TSO + map, **D8** contention, **D9** security, D11 indexes | D1 skeleton, D3, D5, D6 (final ER + data dictionary: 25 tables, 24 triggers, 118 procedures), D7, D10 (E); supplier section: screenshots and endpoint URLs, the pages are merged now (I); join the parts into two documents; D12 print |
| 4 | **Data files and packaging** | Partly done | 24 `.dat` files and `bulk_import.sql` (C4); all 24 load into today's schema with the right row counts (`evidence/C4-recheck`) | optional: empty `NOTIFICATION.dat` and its line, so that all 25 tables are covered (E); move `.sql` into `sql/` (E1, I); `10.zip` on a clean machine (E2, E); upload (E3, I) |
| 5 | **Quality and rehearsal** | Partly done | fresh-database run of the merged code (`evidence/C6-integration-2`), build and SQL tests on SQL2025 with the lab tables unchanged (`evidence/C6-sql2025`), build drops only MDMS-Cy objects, page audit (B10), four two-session concurrency checks with output (`evidence/D8`) | the 2022 server's 12 MB log still fails at the month-end finalize (fix ready, `evidence/C6-logcap`); C5 screenshots in SSMS, and its VEE case (E); decide on `EXECUTE AS … WITH NO REVERT` (security document, limit 1); oral-exam rehearsal (E4, all) |
| 6 | **Bonus: Leaflet map** | Done | B9; the page was rendered in a real browser with tiles, rectangles and meters (`docx/src/img/tso_07_map.png`) | click through the popups once before the demo |

---

## 4. Risks and decisions to take **this week**

| # | Risk / decision | Why it matters | Suggestion |
|---|---|---|---|
| D1 | **Course DB caps: data 27 MB, log 12 MB** (`sys.database_files`). 25 MB are used now. Back-to-back rebuilds fill the 12 MB log ("transaction log is full", seen today). | Large data set and perf run will not fit; rebuilds fail randomly. | Do the large-set/perf work on a **local SQL Server** (Developer/Express, or the SQL Server 2022 container with Podman). Keep the course DB for the final demo. Run `CHECKPOINT;` and wait between rebuilds. |
| D2 | Three people share **one** database `ichara09`. `build_all.sql` drops everything. | One rebuild wipes the others' test data. | Agree a rule, or each uses a local copy; only one person rebuilds the shared one. |
| D3 | **Where does the PHP app run?** (UCY web server vs XAMPP at home, SQLSRV driver for PHP). | Needed before any page can be tested. | Decide on day 1; XAMPP + Microsoft Drivers for PHP is the safest for development. |
| D4 | **`bulk_import.sql` / `.dat` files**: login may not be allowed to `BULK INSERT`; `bcp` not installed on every PC. | `data/` deliverable. | Export with `bcp` from the local server and test the reload there. |
| D5 | Who presents what at the oral exam (every member must show *design and implementation*). | Absent/unprepared member zeroes the project. | Each member owns one area end to end (see split below). |

---

## 5. The checklist (to split)

Effort: **S** ≈ ≤ 2 h · **M** ≈ ≤ 6 h · **L** ≈ ≤ 12 h (rough estimates). Fill **Owner** with `I` (Ioannis), `K` (Kostis), `E` (Eliana).
The *Suggested* column is a proposal built to balance load and to keep each person inside one area from database to page to manual (that also covers the oral exam). Change freely.

### A. Decisions and setup (everyone, this week)
| ☐ | ID | Task | Effort | Suggested | Owner |
|---|----|------|--------|-----------|-------|
| ☐ | A1 | Decide D1–D5 above (hosting of PHP, DB per person, local SQL Server) | S | all | |
| ☐ | A2 | Install a local SQL Server 2022 (or Podman container) and load `build_all.sql` | S | each | |
| ☐ | A3 | Install PHP + Microsoft SQLSRV driver (XAMPP or UCY server); "hello world" query through `sqlsrv_connect` | M | each | |
| ☐ | A4 | Agree branch/merge rule (`io` is the integration branch; short feature branches; no direct force-push) | S | all | |

### B. Web application (`sources/`) — every page only calls `{call dbo.sp_…(?, …)}` with parameters
| ☐ | ID | Task | Effort | Suggested | Owner |
|---|----|------|--------|-----------|-------|
| ☐ | B1 | **Framework**: DB connection helper (one SQL login), session after `sp_Login`, role-based menu, error mapping for the catalog 50001–50008 / 51001–51012, shared layout | L | I | |
| ☐ | B2 | Login, logout, change password, register consumer / technician, profile (`sp_Login`, `sp_RegisterConsumer`, `sp_RegisterTechnician`, `sp_UpdateMyProfile`, `sp_ChangePassword`) | M | K | |
| ☐ | B3 | **Consumer pages**: premises, 15-min readings, aggregates, events/thresholds, buy history, service request, bills + pay, GDPR request | L | I | |
| ☐ | B4 | **Supplier / aggregator pages** and **JSON endpoints** for aggregates ("APIs", p.4/p.10): portfolio, Day-Ahead, Intraday | M | K | |
| ☐ | B5 | **Technician pages**: availability, my jobs (with coordinates), accept/decline/start/complete, install meter + upload certificates | L | E | |
| ☐ | B6 | **Officer / admin pages**: approve technicians and documents, confirm meters, assign/list work orders, remote commands (approve/dispatch/ack), GDPR review (pre-approve vs approve by two people), meter/service types, OBIS codes, tariffs, create staff/organisations, audit log, statistics | L | E | |
| ☐ | B7 | **DSO pages**: ingest a packet (paste JSON) / batch, run VEE, suspect list → accept/edit, finalize, voltage / unbalance / loss reports, events | L | K | |
| ☐ | B8 | **TSO pages**: transformer tree, current state, grid overview, frequency record, remote shedding | M | K | |
| ☐ | B9 | **Leaflet map** (bonus +10 %): meters and transformer rectangles from `view_METER_LOCATION` / `sp_GetTransformerTree`, click for state | M | K | |
| ☐ | B10 | Input validation + escape all output (XSS), no SQL built from strings, session fixation / CSRF basics — keep notes for the security document | M | K | |
| ☐ | B11 | Notifications: email/SMS preference → actually send (or log "sent") when `THRESHOLD_EXCEEDED` is raised | S | I | |

### C. Data and performance (graded)
| ☐ | ID | Task | Effort | Suggested | Owner |
|---|----|------|--------|-----------|-------|
| ☐ | C1 | Run `sp_GenerateSyntheticData` locally for the **large set (tens of thousands of rows)**; check VEE/finalize/aggregates on it; keep the numbers | M | I | |
| ☐ | C2 | Run `perf.sql` PART 1: 10,000 calls, record p95 per procedure (target < 2,000 ms); fix any slow procedure | M | I | |
| ☐ | C3 | Run `perf.sql` PART 3: scan without `IX_METER_READING_obis_slot` vs seek with it; save both execution plans and the logical-read numbers | M | I | |
| ☐ | C4 | Export the **`.dat` files** with `bcp` (`-w -k -E`), test `bulk_import.sql` on a clean database | M | E | |
| ☐ | C5 | **Concurrency demo** (two SSMS windows: pay the same bill; VEE on the same meter; two officers on one request); screenshots | S | E | |
| ☐ | C6 | Re-run `build_all.sql` twice in a row + `tests.sql` + `select.sql` + telemetry tests on a **fresh** database; fix anything found | S | E | |

### D. Documentation (`docx/`) — two documents, one printed
| ☐ | ID | Task | Effort | Suggested | Owner |
|---|----|------|--------|-----------|-------|
| ☐ | D1 | **User manual** skeleton: how to run, accounts, one section per role | S | E | |
| ☐ | D2 | Manual: consumer + supplier/aggregator sections (screens, steps) | M | I | |
| ☐ | D3 | Manual: technician + officer/admin sections | M | E | |
| ☐ | D4 | Manual: DSO + TSO + map sections | M | K | |
| ☐ | D5 | Manual: design choices (state machines, audit, immutability, row-based extensibility), extra functions, difficulties we met (log cap, `fn_Floor15`, month-closing rule…) | M | E | |
| ☐ | D6 | **Final ER diagram v6** (`MDMS_Cy_ERD_v6.erdplus`) as an image + **data dictionary** (24 tables, columns, types, constraints) | M | E | |
| ☐ | D7 | Limits and improvements (use `REPORT.md` §7.4) | S | E | |
| ☐ | D8 | **Second document, (a) contention points**: the two documented ones + the concurrency demo C5 | M | K | |
| ☐ | D9 | **Second document, (b) security**: unauthorised access (roles, EXECUTE-only, actor checks), SQL injection (parameterised), passwords, audit; PHP measures from B10 | M | K | |
| ☐ | D10 | **Second document, (c) future extension**: the table in `REPORT.md` §6.6 with one worked example (UC-20) | S | E | |
| ☐ | D11 | **Three most important indexes**: which, why, how, with the before/after from C3 | M | I | |
| ☐ | D12 | Print `docx/` for the lab (only `docx/` is printed) | S | any | |

### E. Packaging and exam
| ☐ | ID | Task | Effort | Suggested | Owner |
|---|----|------|--------|-----------|-------|
| ☐ | E1 | Move all `.sql` into `sql/` (`build_all.sql` works from there), keep the telemetry tests, add the PHP code to `sources/`, `.dat` to `data/`, documents to `docx/` | S | I | |
| ☐ | E2 | Build `10.zip` and **unzip it on a clean machine**: build, tests, app all work | S | E | |
| ☐ | E3 | Upload to Moodle before **Fri 4/12/2026 12:00**; keep a copy of the receipt | S | I | |
| ☐ | E4 | Oral-exam rehearsal: each member explains the database *and* demonstrates their area; use `select.sql` as the script | M | all | |

### Suggested load (hours, rough)
| Member | Items | Estimated |
|---|---|---|
| Ioannis (I) | B1, B3, B11, C1, C2, C3, D2, D11, E1, E3 | ~60 h |
| Kostis (K) | B2, B4, B7, B8, B9, B10, D4, D8, D9 | ~60 h |
| Eliana (E) | B5, B6, C4, C5, C6, D1, D3, D5, D6, D7, D10, E2 | ~60 h |

(Totals add the S/M/L estimates above: S = 2 h, M = 6 h, L = 12 h.) B1 blocks every page, so Ioannis starts it first; Kostis's B2 (login pages) starts as soon as B1's session helper exists.

---

## 6. Suggested timeline

| By | Goal |
|---|---|
| Fri 20/11 | A1–A4 done; **B1 framework merged** (everyone can build pages on it); local SQL Server up |
| Fri 27/11 | All pages working against the real procedures (B2–B8); large data set generated (C1); documentation skeleton (D1) |
| Tue 1/12 | Performance numbers and plans (C2, C3, C4); documents drafted (D2–D11); map (B9) if time |
| Wed 2/12 | **Freeze.** Fresh-database run (C6), zip built and tested on a clean machine (E2) |
| Thu 3/12 | Print documents (D12); oral-exam rehearsal (E4) |
| Fri 4/12, before 12:00 | Upload `10.zip` (E3) |

*The oral-exam date is announced on Moodle; move E4 accordingly.*
