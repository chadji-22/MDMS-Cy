# Ioannis's tests, 27/11/2026 (TESTING_PLAN.md 3, 3.1, 3.2, 4.1)

Commit tested: **`5415192`** (`testing` = `io`). Evidence branch: `ioannis/testing-evidence`. Times are UTC, 27/11/2026
00:25 to 01:05. Every file starts with the command that produced it. Passwords are never in these files (`grep` checked).

## Environments

| Code | What | Versions |
|---|---|---|
| L | `mdms-web-local` (`http://127.0.0.1:8081`, site root, `DB_PASS` in the environment) + `mdms-sql` (database `mdms2`, built 25/11 from the current SQL files: 25 tables, 118 procedures) | PHP 8.3.36, sqlsrv 5.13.3; SQL Server 16.0.4325.4 Developer; Podman 6.1.4 (WSL) |
| R | `mdms-ucy-replica` from `sources/dev/ucy-replica.sh` (`http://127.0.0.1:8090/~student/mdms`, user `student` uid 10027 / `cs24`, PHP as `www-data`, Connect page, installed by `deploy/install.sh`), database `mdms2` on `mdms-sql` | PHP 8.0.30, sqlsrv 5.11.1, Apache 2.4.56 |
| S | `https://students.cs.ucy.ac.cy/~ichara09/mdms` + `mssql.cs.ucy.ac.cy\SQL2025`, database `ichara09` (127 procedures, `mdms_php` present) | PHP 8.0.30, Apache 2.4.6 (CentOS) |

R ran the zip rebuilt from the working tree (`python deploy/build_zip.py`, sha256 `5ddcb528...`) for the gate. For I-15, it was then updated with the **committed** `deploy/mdms-app.zip` (sha256 `345fd7e9...`), which is the zip deployed on S.

## Results

| Suite | Env | Result | File |
|---|---|---|---|
| `audit_pages.php`, `errors_test.php`, `php -l` (91 files) | PHP 8.0.30 + 8.3.36, no DB | PASS: 116 calls, 0 errors, 15 review lines (baseline); errors_test all passed; 0 lint errors | `static-php80.txt`, `static-php83.txt` |
| `tests.sql` | L | PASS: 82 tests, 0 not passed | `db-tests_sql-L.txt` |
| `db_integration.php` | L | PASS: all passed | `db-db_integration-L.txt` |
| gate `run_all.sh` (WRITE=1) | L | PASS: smoke all passed; consumer 63/63; market/dso/tso 160/160; accounts all passed; crawl 168 pages, no problems; 0 PHP warnings | `gate-L-run_all.txt`, `L-php-log-check.txt` |
| gate `run_all.sh` (WRITE=1, Connect page) | R | PASS: smoke; **connect 23/23**; consumer 63/63; market/dso/tso 160/160; accounts; crawl 168 pages, no problems; 0 PHP warnings | `gate-R-run_all.txt`, `R-php-log-check.txt` |
| I-15 second `install.sh` + `connect.sh` + `accounts.sh` | R | PASS: `Done`, exit 0; 9 upload files kept (same content hash), `var` + 4 subfolders stay `drwx-wx-wt`, `config.local.php` unchanged; connect 23/23; accounts all passed (13 files in `var`) | `I-15-reinstall-R.txt` |
| I-08…I-14 (curl + SQL checks) | L | PASS 19/19 (run 2; run 1 had one FAIL caused by a wrong assumption in the script, see below) | `manual-I08-I14-L.txt`, `manual-I08-I14-L-run1.txt` |
| I-03, I-07, I-08, I-09 (read-only) | R | PASS 15/15 | `manual-I03-I07-I08-I09-R.txt` |
| I-05 idle 1900 s | R | see the file (result line `RESULT I-05`) | `I-05-idle-R.txt` |
| deployed code vs. zip | S | S serves the committed zip: 6/6 static files byte-identical; Connect page HTML identical apart from the server name | `S-deployed-vs-zip.txt` |
| `connect.sh` | S | PASS 23/23 | `S-connect.txt` |
| `smoke.sh` (once) | S | PASS all passed | `S-smoke.txt` |
| `crawl_links.py` | S | PASS: 151 pages, 2,436 URLs, no problems (notes: `account/photo.php` 404, query-only pager: known, not bugs) | `S-crawl_links.txt` |
| I-03, I-07, I-08, I-09 (read-only) | S | PASS 14/14 | `manual-I03-I07-I08-I09-S.txt` |

Run 1 of `manual_L.sh`: the I-10 check expected a **new** `THRESHOLD_EXCEEDED` event in the current month. Premise 1
has 0 kWh this month, so the officers' check rightly raised nothing. The plan expects an event and a SIMULATED
notification, and both exist: event 22 for October, 60.42 kWh > 10 kWh, raised by TR21 at import, with EMAIL and SMS
both SIMULATED. The check was corrected to that expectation; run 2 passed.

## Scripts (`scripts/`)

* `manual_L.sh`: I-08 to I-14 on L. It writes to the local copy only: it buys October for premise 1, makes a partial
  payment of 1.00 on bill 2, submits a check request and cancels it, and submits a right-to-be-forgotten request for
  consumer9, which officer1 then rejects so that consumer9 stays usable.
* `manual_ro.sh`: I-03, I-07, I-08, I-09, read-only. It makes one Connect and three logins, with no wrong password,
  so it is safe on S.
* `i05_idle.sh`: I-05. It connects, logs in, sleeps 1900 s, then opens a page.

## Changes left in the local database `mdms2` (L/R)

These are on top of the usual `WRITE=1` rows:
* consumer1 bought October 2026 for premise 1 (payment 2018);
* bill 2 is now PARTIALLY_PAID, with 2.00 paid in two payments;
* check requests 2033 and 2034 are CANCELLED;
* GDPR requests 1007 and 1008 (consumer9) are REJECTED;
* officer1 ran `sp_CheckConsumptionThresholds` twice: no new event.
