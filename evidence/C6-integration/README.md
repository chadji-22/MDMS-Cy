# C6 — integrated code proven on a fresh SQL Server 2022 (24/11/2026)

Code under test: `origin/Kostis` `5ca548a` + `origin/ioannis/notes` (notes only) = branch `ioannis/integration`.
Environment: SQL Server 2022 (RTM-CU28) in a Podman container (`mcr.microsoft.com/mssql/server:2022-latest`), empty
database `mdms`, collation SQL_Latin1_General_CP1_CI_AS; web app in `mdms-php-dev` (PHP 8.3 + sqlsrv) on the same
Podman network, connecting as a login that may only `IMPERSONATE` the login-less user `mdms_php` (security.sql).
The course database `ichara09` was not touched.

| Step | Result | File |
|---|---|---|
| `build_all.sql` run 1 on an empty DB | exit 0, 25 tables, 8 views, 8+2 functions, 24 triggers, 118 procedures, 15 indexes | build1_output.txt |
| `build_all.sql` run 2 (idempotent) | exit 0, same counts | build2_output.txt |
| `tests.sql` | 82/82 passed | tests_output.txt |
| telemetry tests (ingest 4, storage 8, VEE range 5, VEE delta 9) | 26/26 passed | sql_test_*.txt |
| `test_vee_edit.sql`, `test_vee_spike_preview.sql` | PASS | sql_test_vee_*.txt |
| `select.sql` UC-01 .. UC-20 | all 20 ran, no SQL error | select_output.txt |
| `tests/smoke.sh` (B1) | 23/23 | web_smoke.txt |
| `tests/consumer_pages.sh` (B3, WRITE=1) | 63/63 | web_consumer_pages.txt |
| `tests/accounts.sh` (registration, profile, uploads) | 47/47 | web_accounts.txt |
| `tests/market_dso_tso.sh` read-only / WRITE=1 (market, DSO/TSO pages, login throttling) | 152/152 and 160/160 | web_market_dso_tso*.txt |
| `tests/errors_test.php`, `tests/db_integration.php` | all passed | php_*.txt |
| `tests/audit_pages.php` | 116 procedure calls checked, 0 errors, 15 "to review" (escaping hints) | php_audit_pages.txt |
| `crawl_pages.py`: 59 pages x 8 roles + anonymous | 531 requests, 0 failed (right role: no 401/403/5xx, no PHP error text; wrong role: 403; anonymous: redirect). Caught database errors show as `alert:` in the note column; the only one is consumer/request.php without an id ("Work order not found") | pages.md |
| `crawl_detail.py`: pages that need `?id=`, real ids from the DB | 11 requests, 0 failed (200, no alert box, no PHP error text) | detail_pages.md |
| application error log (`[MDMS <ref>]` lines) of the web container over all web tests and crawls | 0 entries | - |

How to repeat: start the two containers, `sqlcmd -d mdms -i build_all.sql` from the repo root, run the scripts above
(`BASE_URL=http://127.0.0.1:8081`; mount `sources/` writable because uploads and the throttle write under `sources/var/`;
run `errors_test.php` with `APP_DEBUG=0`; `audit_pages.php` needs the whole repo mounted next to `sources/`).
Not covered here:
- the POST flows of the technician (B5) and staff (B6) pages: no script exists for them, so they were only requested with GET and checked for the role rule and for caught database errors; they need a manual check or a new test;
- `bulk_import.sql` / `data/*.dat` (E1);
- the Leaflet map in a real browser (HTTP status and HTML only);
- `consumer/request.php?id=` with a real id (consumer1 has no work order; the write flows are in `consumer_pages.sh`).
