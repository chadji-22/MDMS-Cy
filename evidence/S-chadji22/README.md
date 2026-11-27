# Full test run on the department servers (27/11/2026, Kostis)

Every test from `PROJECT_STATUS_AND_CHECKLIST.md` (section 1), `sql/HOW_TO_RUN_TESTS.md` and `TESTING_PLAN.md`, run against the
real servers, not localhost:

* SQL tests: **`mssql.cs.ucy.ac.cy\SQL2025`**, database `chadji22` (own copy of the MDMS build).
* Web tests: **`https://students.cs.ucy.ac.cy/~chadji22/mdms/`** (installed with `deploy/DEPLOY.md`, PHP 8.0.30, Connect page),
  on the same database. Writes (`WRITE=1`) were allowed because this is not the team database `ichara09`.
* Code: branch `testing`. The database was **not** rebuilt for this run (it already held the current build: all 118
  procedures match the repository); the `build_all.sql` check of section 1 is therefore not repeated here.

## 1. SQL tests

| Test | Result |
|---|---|
| `tests.sql` | **82 / 82 PASS** (`tests.sql: 82 tests, 0 not passed.`) |
| `select.sql` | 0 errors; all 20 use cases UC-01 … UC-20 run |
| `sql/seed_grid.sql`, `sql/seed_telemetry_demo.sql` | fixture already present ("nothing to do") |
| `sql/test_telemetry_parsing.sql` | runs, packet parsed (read-only demo) |
| `sql/test_telemetry_ingest.sql` | 4 / 4 PASS, cleaned up |
| `sql/test_telemetry_storage.sql` | 8 / 8 PASS, cleaned up |
| `sql/test_vee_range.sql` | 5 / 5 PASS, cleaned up |
| `sql/test_vee_delta.sql` | 9 / 9 PASS, cleaned up |
| **telemetry total** | **26 / 26 PASS** |
| `sql/test_vee_edit.sql`, `sql/test_vee_spike_preview.sql` (not in the guide) | both PASS, rolled back |

## 2. Web tests on the deployed site

| Suite | Result |
|---|---|
| `tests/smoke.sh` | all passed |
| `tests/connect.sh` | **23 / 23** passed |
| `tests/market_dso_tso.sh` (`WRITE=1`) | **160 / 160** passed |
| `tests/crawl_links.py` | **169 pages, 2,923 URLs**, every link under `/~chadji22/mdms`, no problems (5 notes, see `TESTING_PLAN.md` section 7) |
| `tests/consumer_pages.sh` (`WRITE=1`) | first run: 35 passed, 28 failed (cause below); **rerun at 13:34 UTC: 63 / 63 passed** |
| `tests/accounts.sh` | pending (see below) |
| Manual tests K-01 … K-15 (`TESTING_PLAN.md` 4.2), scripted over HTTP | **all 15 passed** (details in `TESTING_PLAN.md` section 6) |

## 3. Failed checks

All 28 failures are in the first `consumer_pages.sh` run and have **one cause**: check 1, consumer2's login, was refused with
**HTTP 429** ("Too many failed logins"). The manual test K-04 had locked consumer2 on this site about 15 minutes earlier on
purpose (5 wrong passwords). Every later check logs in as consumer2, so it failed with it. This is the login lock working as
designed, not a defect.

| # | Check | Why it failed |
|---|---|---|
| 1 | consumer2 logs in (got 429) | consumer2 locked by K-04 |
| 2 | consumer menu lists the 8 pages | not logged in (1) |
| 3 | consumer2 opens `/consumer/` (200) | not logged in (1) |
| 4 | consumer2 opens `/consumer/readings.php` (200) | not logged in (1) |
| 5 | consumer2 opens `/consumer/aggregates.php` (200) | not logged in (1) |
| 6 | consumer2 opens `/consumer/history.php` (200) | not logged in (1) |
| 7 | consumer2 opens `/consumer/events.php` (200) | not logged in (1) |
| 8 | consumer2 opens `/consumer/requests.php` (200) | not logged in (1) |
| 9 | consumer2 opens `/consumer/bills.php` (200) | not logged in (1) |
| 10 | consumer2 opens `/consumer/gdpr.php` (200) | not logged in (1) |
| 11 | prosumer premise 3, bought days: import and export side by side | not logged in (1) |
| 12 | premise 4, past month not bought: 50008 message and the reason | not logged in (1) |
| 13 | totals of premise 4, past month not bought: 50008 message | not logged in (1) |
| 14 | totals of premise 3 (bought): daily table with import and export | not logged in (1) |
| 15 | another consumer's premise: "Permission denied: not your premise." | not logged in (1) |
| 16 | window longer than 31 days: 50004 message | not logged in (1) |
| 17 | history quote for premise 4, last month: price and buy button | not logged in (1) |
| 18 | history quote for the current month: cannot be bought | not logged in (1) |
| 19 | unknown request id: "Work order not found." | not logged in (1) |
| 20 | events of premise 3: the 198.5 V undervoltage event | not logged in (1) |
| 21 | events page: notifications explained as simulated (B11) | not logged in (1) |
| 22 | notifications of another consumer's premise: refused (50002) | not logged in (1) |
| 23 | bills page: bills and payment history of consumer2 | not logged in (1) |
| 24 | POST without CSRF token is refused (403) | not logged in (1) |
| 25 | add premise with a bad postal code: 50004 from the database | not logged in (1) |
| 26 | buy the current month: refused with 50008 | not logged in (1) |
| 27 | pay someone else's bill #1: refused | not logged in (1) |
| 28 | right to be forgotten without the confirmation box: refused, nothing submitted | not logged in (1) |

The same suite passed 63 / 63 earlier the same day on a local PHP instance against the same database.

## 4. Pending

* ~~`consumer_pages.sh` again after consumer2's 15-minute lock has expired~~: done at 13:34 UTC, 63 / 63 passed.
* `accounts.sh` after 14:20 UTC: the site accepts **3 registrations per hour from one address** (B10 throttle), and the K-01,
  K-02 and K-14 runs had used them.

## 5. Notes for the team

* **`<script>` in a request is blocked by the department server itself**: a registration with the full name
  `Test <script>alert(1)</script>` gets Apache's own 403 page before PHP runs. So K-14 cannot register that account on S; an
  account with that name (registered on a local instance) logs in on S and its name is shown escaped.
* **K-10**: the losses report works for level-1 transformers only (transformer 1 is level 4 and answers "Level-1 transformer
  not found" by design); use e.g. transformer 9.
* **K-05**: Day-Ahead needs a window with final data (e.g. 2026-10-01 … 2026-11-30, level 3); Intraday shows rows only where
  a group has at least 3 meters (31/10, level 3 or 4), as `sp_GetIntradayProvisional` intends.
* Test data left in `chadji22`: consumers `k01-*`, `k14-*`, technician `k02-*`, 96 final readings of `DEMO-NET-001` on
  2026-11-20 and 2026-11-21, two APPROVED (not dispatched) DISCONNECT commands for it.
