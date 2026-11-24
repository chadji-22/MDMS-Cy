# Agent log — Ioannis's Phase B tasks (B3, B11, C1, C2, C3, D2, D11, E1, E3 prep)

## 2026-11-22 17:47 — §0 orientation (read-only)

### Repository
- Clone `phaseB/MDMS-Cy-io`, branch `io`, clean, up to date with `origin/io` after `git fetch --all`.
- **Nothing new on `io` or `main` since 18/11** (the io clone's refs for `eliana` and `Kostis` were stale, see below). Last commits: `c236648` (merge of B1), `4b59de0` (B1 framework),
  `8deddca` (status/checklist), `b8d46cb` (merge of Kostis's `fn_Floor15` fix), `a871ff2` (Eliana's telemetry tests, ported).
  `origin/eliana` = `a871ff2`, `origin/Kostis` = `a1ebdfe`, `origin/main` = `bf86c83` (stale refs of the io clone; on GitHub 23/11: `eliana` = `188505e`, `Kostis` = `c236648`, now `5ca548a`).
- **Mismatch with the brief:** the brief says B5, B6, C4, C5, C6 are done. None of them is on `io` (checked in the io clone; B5, B6 and C4 are on GitHub branch `eliana`, see correction below)
  (no technician/staff pages under `sources/public/`, `data/` holds only `.gitkeep`, no concurrency screenshots, no C6 log).
  `docx/` holds only `.gitkeep`, so **D1 (manual skeleton) does not exist yet** → D2 will be written as standalone files
  `docx/src/manual_consumer.md` and `docx/src/manual_supplier.md`, as the brief allows.
  Correction 23/11: Eliana's B5, B6 and C4 are on GitHub branch `eliana` (188505e, 18/11), not merged into io; C5/C6 evidence is on no branch.
- The checklist in the repo (`PROJECT_STATUS_AND_CHECKLIST.md`) has no task ticked, including B1.

### Specification (project.pdf, re-read)
- §1.1 p.5 premises; §1.2 p.5–6 readings, prosumer import/export, voltage events, thresholds + email/SMS preference,
  current month free / older paid / limited by retention, daily-monthly-yearly aggregates; §1.3 p.6 requests with state
  and history, charges and payments; §1.4 p.6–7 right to be forgotten.
- §IV p.12: large set "of the order of thousands of rows"; three most important indexes (which, why, how);
  contention points; **< 2 s for ≥ 95 % of the usual OLTP queries over 10,000 requests**; at least one index/query
  before-after case. p.13 security and concurrency. §V p.13–14 zip layout `sources/ sql/ data/ docx/`.

### B1 framework (merged, `sources/`)
- `src/Db.php`: `Db::call / callAsActor / rows / row`, `{CALL dbo.sp_x(?, ...)}` only, procedure name must match
  `^sp_[A-Za-z0-9_]+$`, `EXECUTE AS USER = 'mdms_php'` after connect (fails closed). `Db::nv()` for NVARCHAR.
- `src/Errors.php` + `DbError.php`: 50001–50008 and [51001]–[51012] mapped to categories and HTTP codes.
- `src/Auth.php`: session from `sp_Login`, `Auth::requireRole(...)`; `src/Csrf.php` (`Csrf::field()/verify()`);
  `src/View.php` (`View::h`, header/footer/flash/error, CSP without inline script/style).
- `areas/<area>/menu.php` per area; `public/consumer/index.php` is a placeholder. **CSRF already exists (B1)**,
  so no extra token include is needed.
- Consequence: a function such as `fn_CanViewReadings` cannot be called from PHP (only `sp_` names), and the PHP user
  cannot read tables. Every value a page needs must come out of a procedure.

### Procedures the consumer pages need (signatures read from `procedures_*.sql`)
| Page | Procedure(s) | Gap |
|---|---|---|
| Premises | `sp_ListMyPremises`, `sp_AddPremise(actor, address, lat, lon, usage, district, municipality, parish, postal_code, scheme='NONE', supplier=NULL)` | no CONSUMER procedure lists the suppliers → supplier cannot be chosen (optional parameter) |
| Readings | `sp_GetPremiseReadings(actor, premise, from, to, obis_list)`; max 31 days; THROWs **50008** when the past is not bought | none |
| Aggregates | `sp_GetPremiseAggregates(actor, premise, 'DAY'/'MONTH'/'YEAR', from, to)`; same 50008 | none |
| History access | `sp_GetHistoricalAccessQuote(actor, meter, from, to)`, `sp_BuyHistoricalAccess(actor, meter, from, to, method, ref)` | none (`meter_id` comes from `sp_ListMyPremises`) |
| Events/thresholds | `sp_GetPremiseEvents(actor, premise, from, to)`, `sp_SetPremiseThreshold(actor, premise, kwh)`, `sp_GetMyProfile`, `sp_UpdateMyProfile(actor, name, phone, iban, notify_email, notify_sms)` | none |
| Service request | `sp_SubmitServiceRequest(actor, premise, meter, 'TECHNICAL_CHECK'/'FAULT_REPAIR', text)`, `sp_ListMyWorkOrders(actor, status, page, size)` (consumer branch), `sp_GetWorkOrderHistory(actor, wo)` | none |
| Bills/payments | `sp_GetMyBillsAndPayments(actor, from, to)`, `sp_PayBill(actor, bill, amount, method, ref)`, `sp_PayServiceFee(actor, service_type_id, amount, method, ref)` | **no CONSUMER procedure returns `service_type_id`** (`select.sql` UC-06 reads `SERVICE_TYPE` directly, which PHP cannot) |
| GDPR | `sp_SubmitGdprRequest(actor, 'RIGHT_TO_BE_FORGOTTEN'/'RETENTION_REDUCTION', meter)`, `sp_ListGdprRequests(actor, status, page, size)` (consumer sees own, with history) | none |

### B11 (notifications)
- `tr_AGGREGATE_threshold_alert` (TR21) inserts an `EVENT` of type `THRESHOLD_EXCEEDED`; its comment says
  "PHP sends the email / SMS". Preferences are `USER_ACCOUNT.notify_email / notify_sms`.
- **There is no table that can record a notification** (status SIMULATED, channel, recipient, time, event id).
  Recording one in the database is a schema change → asked Ioannis (see open questions).

### Large data set (C1) — arithmetic
- `sp_GenerateSyntheticData(@actor, @consumers, @days, @seed, @chunk_meters)` writes one meter per consumer and about
  4.55 readings per slot (1.8.0, 1.8.1, 1.8.2, 32.7.0 always; 2.8.0 for 25 % prosumers; 3 currents for 10 % three-phase)
  → **≈ 437 METER_READING rows per meter per day** (its own header: 100 meters × 1 day ≈ 45,000 rows).
- So the brief's "a few hundred meters × 2–4 weeks" gives **≈ 2–4 million rows**, not "tens of thousands".
  The two halves of the brief contradict each other → asked Ioannis.
- Data ends yesterday (UTC). For the history-access page to show "older month, buy access" on the large set, the data
  must reach into October: `@days ≥ 22` today, `≥ 24` on 24/11.
- Transformer tree: 1 level-1 transformer per 40 meters; with ≤ 40 consumers the tree has one leaf.

### perf.sql (C2) — observations
- PART 1 mixes 6 procedures (readings, aggregates, my work orders, ingest, transformer state, day-ahead). The brief also
  wants login, list bills, pay bill, submit service request → PART 1 must be extended (test script only, no DB object).
  Write calls (pay, submit, login writes `LOGIN_OK`) must run in a rolled-back transaction like the ingest call.
- The CATCH records the timing of a failed call too: a fast failure lowers p95. The result is only valid with
  `failed_calls = 0` per procedure; the report will state that.
- PART 3 runs IX1 with / without / with again; SSMS 22 is installed, so actual plans can be saved as `.sqlplan`.

### Local environment
| Item | State |
|---|---|
| SQL Server 2022 local | **MISSING** — no Windows service, no `mssql` container or image |
| Podman | installed, machine `podman-machine-default` running (WSL, ~15.8 GB RAM visible, 6 CPUs) |
| PHP + sqlsrv | available through the existing image `localhost/mdms-php-dev` (B1 `Containerfile`); no PHP on Windows |
| Container `mdms-web` | exists, stopped; its environment points at the course DB `ichara09`. **Do not start it as is** (every login writes audit rows to the shared DB); recreate it pointed at the local DB |
| sqlcmd | go-sqlcmd v1.10.0 (`C:\Users\ioann\tools\sqlcmd`) |
| SSMS | SQL Server Management Studio 22 installed |
| pandoc | **MISSING** (needed for D2 `.docx`) |
| bcp | missing (C4 is Eliana's) |
| Course server `mssql.cs.ucy.ac.cy` | not resolvable from this PC right now (UCY VPN off?) — so its collation could not be read |

Per §0.5 of the brief: local SQL Server is missing → **stopped and asked** (see open questions). Nothing was changed
in the repository except this log and `notes/open_questions.md` (both uncommitted).

```
Done:      §0 orientation only (no commits)
Evidence:  this file
Tests:     not run (no local SQL Server)
Blocked:   C1, C2, C3 and page testing need a local SQL Server; B11 needs a storage decision; B3 page 7 (pay service fee)
           needs a read procedure for service types; C1 size needs a decision. See notes/open_questions.md.
Next:      on answers: start the local server, build twice, run tests, start C1; build B3 pages 1–4 meanwhile.
```

## 2026-11-22 18:35 — session 1: B3, B11, C1, C2, C3, D2, D11

Decisions by Ioannis (22/11, answers to notes/open_questions.md):
use the course DB `ichara09` with small data (no local server) · B11 = new NOTIFICATION table ·
add sp_ListServiceTypes + sp_ListSuppliers · C1 size: "test it" (sized by measurement for the 27 MB cap).

```
Done:      B3  consumer pages, 8 pages + request detail            05272bd, 31fc6cc   (branch ioannis/B3-consumer-pages)
           B11 NOTIFICATION + TR23 + sp_ListMyNotifications, SIMULATED status, shown on events page,
               GDPR erases recipients                               b1b5bd8           (ioannis/B11-notifications, on top of B3)
           C1  8 consumers x 2 days on ichara09, pipeline OK, METER_READING 16,127
           C2  10,000 calls, 0 failed, p95 22.71 ms (all 10 procedures met; perf.sql PART 1 extended)
           C3  IX1 with/without, actual plans: Scan->Seek, reads 391->7, cost 0.427->0.078
                                                                    9143daa           (ioannis/C-perf)
           D2  docx/src/manual_consumer.md, manual_supplier.md (B4 placeholders); D11 docx/src/indexes_D11.md;
               built to .docx with pandoc 3.5 (container)           85b0397           (ioannis/D2-D11-docs)
Evidence:  evidence/B3 (11 screenshots, consumer_pages_run.txt 61/61), evidence/B11, evidence/C1, evidence/C2, evidence/C3
Tests:     build_all x2 NOT RUN (rebuilding the shared DB was blocked by the permission system; needs Ioannis)
           tests.sql 82/82 (73 old + L1-L3 + M1-M6), on ichara09 after ADDITIVE deploys (CREATE OR ALTER / IF NOT EXISTS)
           telemetry 26/26 · select.sql UC-01..UC-20 no error · B1 smoke.sh all passed · errors_test.php all passed (APP_DEBUG=0)
           sources/tests/consumer_pages.sh 53/53 read-only, 61/61 with WRITE=1 (before the B11 checks were added)
Blocked:   1. build_all.sql x2 on a fresh DB (brief §1) before merging B3/B11 into io: needs either the go-ahead to
              rebuild ichara09 (wipes it back to import.sql; C1 set must then be regenerated, ~6 s) or a local server.
           2. Pushed to GitHub on 23/11 (four ioannis/* branches); merging into io is not done: waiting for 1 and for Ioannis.
           3. E1 not started: after merges, and after Eliana's C5/C6 evidence is pushed (B5/B6/C4 are on GitHub branch `eliana`, not yet merged into io).
Next:      after the go-ahead: rebuild ×2 + all tests on the B11 head, merge B3 -> B11 -> C-perf -> docs into io, push;
           then E1 on its own branch (tell the team first); E3 checklist after E2.
```

### State left on the course DB `ichara09` (shared)
- Added (additively, no rebuild): procedures `sp_ListServiceTypes`, `sp_ListSuppliers`, `sp_ListMyNotifications`;
  table `NOTIFICATION` + FKs + `IX_NOTIFICATION_user`; trigger `tr_EVENT_notify`; `sp_ExecuteGdprRequest` step 4.
  These exist in the DB but are not on `io` yet. If a teammate runs `build_all.sql` from `io` before the merge, `io`'s
  `create.sql` does not know `NOTIFICATION`: its FKs are dropped, but the table (with its rows) and `IX_NOTIFICATION_user`
  stay as orphans, `tr_EVENT_notify` disappears with `EVENT`, and the 3 new procedures stay. Their build summary will
  then show **113 procedures and 15 indexes instead of the expected 110 and 14**. That is this, not a fault in their work.
- Data added: synthetic batches SYN1 (2 consumers × 2 days, trial) and SYN2 (8 × 2, C1); page-test writes as
  consumer9 / consumer7 (threshold set and removed, a cancelled request, a METER_CHECK fee, a retention request for
  meter 11, last month bought for premise 9); consumer8 threshold 5 kWh + one THRESHOLD_EXCEEDED event with 2 SIMULATED
  notifications (B11 demo). Data file 24.3 MB of 27 MB.
- `IX_METER_READING_obis_slot` was dropped and recreated during C3; checked present afterwards.

### Notes for teammates (to pass on)
- Kostis (B10): CSRF already exists in B1 (`Csrf::field()/verify()`); the consumer pages use it. B4 owner: the supplier
  manual section has `TODO-screenshot` / `TODO (B4)` markers to fill.
- Eliana (D6 data dictionary, C4 .dat list): there is now a 25th table, `NOTIFICATION`, and a 24th trigger (TR23).
- The B1 `errors_test.php` "hides the SQL text" case fails when the container runs with `APP_DEBUG=1` (by design); run it with `-e APP_DEBUG=0`.

### What Ioannis must do himself
- Decide on the rebuild (Blocked 1) and on merging/pushing.
- C3: open the four `evidence/C3/*.sqlplan` in SSMS 22 and save screenshots of the graphical plans (2 min).
- Later: upload `10.zip` to Moodle before Fri 4/12/2026 12:00, print `docx/`, rehearse the oral exam.

## 2026-11-22 19:00 — follow-ups after review
```
Done:      B3  pages re-checked on the large set: read-only run 59/59 incl. 8 checks as syn2_000004 (current month
               free with real rows, no purchase); 2 screenshots                      4b60b45 (B3 branch)
           B11 rebased onto B3; M6 replaced by the real GDPR flow (submit, review, pre-approve, approve by a 2nd officer,
               execute) in a rolled-back transaction; mutation check: FAILS with io's sp_ExecuteGdprRequest, PASSES with B11's
                                                                                      0f7bc58 (B11 branch)
           C1  tests.sql H3 failed after C1: it compared every root with ALL meters; each generator batch builds its own
               tree. Fixed per root (fn_TransformerSubtree)                           5b89d64 on C-perf, same change as cb93163 on B11
           C2  report states that readings/totals were timed as the DSO (consumer purchase check not in the timings)
Tests:     tests.sql 82/82 on the B11 head, with the C1 data present; io's tests.sql + H3 fix: 73/73
Blocked:   unchanged (Q5: fresh build_all x2; no merge, no push)
```
