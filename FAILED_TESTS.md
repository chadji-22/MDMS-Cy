# Failed tests: run on the department servers, 27/11/2026

Where: `https://students.cs.ucy.ac.cy/~chadji22/mdms/` with the database `chadji22` on `mssql.cs.ucy.ac.cy\SQL2025`.
Full results of the run: `evidence/S-chadji22/README.md`.

## `accounts.sh` after the redeploy: 28/11, 11:49 UTC: **0 failed** (31 / 31, consumer half)

**Status: resolved.** After the current `deploy/mdms-app.zip` was installed and the PHP files were touched (see below), the
consumer half passed 31 / 31, including the three IBAN checks. With the technician half of 11:25 (all passed), every check
of `accounts.sh` has passed on the live site.

Two deployment problems were found and fixed on the way:

1. **Login impossible after the update:** `~/mdms` had been replaced as a whole, so `src/config.local.php` and `var/` were
   gone. Without the settings every redirect went to `students.cs.ucy.ac.cy/login.php` (no `BASE_PATH`) and the Connect page
   had empty fields. Fixed by writing `config.local.php` again and recreating `var/` (1733). Update by `unzip -o` over the
   old folder, never by deleting it.
2. **Old page served after the update:** `deploy/build_zip.py` gives every file the fixed date 2026-01-01, and the web
   server's PHP OPcache recompiles a file only when its date changes. A changed `profile.php` with the same date kept running
   the cached old version (new IBAN rule from `Validate.php`, old message from `profile.php`). Fixed with
   `find ~/mdms -name '*.php' -exec touch {} +` after unzipping.

## `accounts.sh`: 28/11, 11:25–11:35 UTC: **3 failed** (the live site still ran the code without the IBAN fix)

The test skipped on 27/11 (registration limit), run live on 28/11 in three steps:

| Step | Result |
|---|---|
| 1. `accounts.sh` as it is | technician half **all passed** (registration, photo, the three documents, every refusal); consumer half 21 failed: the registration got **403 from Apache**, not from PHP, so no consumer existed for the later checks |
| 2. why | the department server blocks a request whose name contains an HTML tag: `Δοκιμή <script>` and `Δοκιμή <b>` get Apache's 403, plain `Δοκιμή` reaches the application (422 for a wrong repeated password). The test's name `Δοκιμή <script>` can therefore never be registered on this server |
| 3. consumer half again with the name `Δοκιμή Λάιβ` (copy of the script, nothing else changed) | **28 passed, 3 failed** |

| # | Failed check | Expected | Got | Cause |
|---|---|---|---|---|
| 1 | profile: an IBAN with wrong check digits is refused | 422 | 303, saved | the live site has the **old** `Validate::iban` (form only); the fix (`b3cd2c6`) is in `testing` and in `deploy/mdms-app.zip`, not yet installed in `~/mdms` |
| 2 | ...and the saved IBAN is unchanged | `CY60…7699` | the wrong IBAN | follows from 1 |
| 3 | profile: a Cyprus IBAN of 27 characters is refused | 422 | 303 | same as 1 |

The same three checks pass on a local instance with the current code (27/11). **To clear them:** install the current
`deploy/mdms-app.zip` in `~/mdms` (`deploy/DEPLOY.md`, section 4) and run `accounts.sh` again. The name-escaping check of
`accounts.sh` cannot run on this server (its `<script>` name is blocked before PHP); it passes locally, and K-14 shows on the
live site that a stored `<script>` name is displayed escaped.

## Run: 27/11, 13:43–13:47 UTC: **0 failed**

All tests again, live, in an order where the K-04 login lock cannot reach another suite (SQL, then web suites, then K-01..K-15).

| Test | Result |
|---|---|
| `tests.sql` | 82 / 82 |
| `select.sql` | 0 errors, 20 / 20 use cases |
| telemetry (`sql/test_telemetry_ingest`, `_storage`, `test_vee_range`, `_delta`) | 4 + 8 + 5 + 9 = 26 / 26 |
| `sql/test_vee_edit.sql`, `sql/test_vee_spike_preview.sql` | PASS, PASS |
| `smoke.sh` | 24 / 24 |
| `connect.sh` | 23 / 23 |
| `consumer_pages.sh` (WRITE=1) | 63 / 63 |
| `market_dso_tso.sh` (WRITE=1) | 160 / 160 |
| `crawl_links.py` | 169 pages, 2,931 URLs, no problems |
| K-01..K-15 (48 checks) | 48 / 48 |

No new accounts were registered in this run (the site allows 3 registrations per hour per address): K-01 and K-14 log in with
accounts registered earlier through the site, K-02 checks the pending technician registered earlier. Registration itself is
tested by `accounts.sh` (run on 28/11, see above).

## Earlier run: 27/11, 13:26 UTC: 28 failed (cause: login lock, not a defect)

**Status: resolved.** `consumer_pages.sh` was run again at 13:34 UTC, after consumer2's lock had expired: **63 passed,
0 failed**. No defect was found; the failures below were caused by the login lock only.

**28 checks failed in that run, all in `tests/consumer_pages.sh`. Every other test passed** (`tests.sql` 82/82, `select.sql`, telemetry
26/26, `smoke.sh`, `connect.sh` 23/23, `market_dso_tso.sh` 160/160, crawl 169 pages, manual tests K-01 to K-15).

**Cause of all 28:** the first check, consumer2's login, was refused with **HTTP 429 "Too many failed logins"**, because
manual test K-04 had locked consumer2 on this site 15 minutes earlier (5 wrong passwords, on purpose). Checks 2 to 28 all run
as consumer2, so they failed with it. The same suite passed 63/63 earlier the same day against the same database.

| # | Failed check | Expected |
|---|---|---|
| 1 | consumer2 logs in | 303 to home; **got 429** |
| 2 | consumer menu lists the 8 pages | 8 consumer menu entries |
| 3 | consumer2 opens `/consumer/` | 200 |
| 4 | consumer2 opens `/consumer/readings.php` | 200 |
| 5 | consumer2 opens `/consumer/aggregates.php` | 200 |
| 6 | consumer2 opens `/consumer/history.php` | 200 |
| 7 | consumer2 opens `/consumer/events.php` | 200 |
| 8 | consumer2 opens `/consumer/requests.php` | 200 |
| 9 | consumer2 opens `/consumer/bills.php` | 200 |
| 10 | consumer2 opens `/consumer/gdpr.php` | 200 |
| 11 | prosumer premise 3, bought days | import and export side by side |
| 12 | premise 4, past month not bought | 50008 message and the reason, not an empty table |
| 13 | totals of premise 4, past month not bought | 50008 message |
| 14 | totals of premise 3 (bought) | daily table with import and export |
| 15 | another consumer's premise | "Permission denied: not your premise." |
| 16 | window longer than 31 days | 50004 message |
| 17 | history quote for premise 4, last month | price and buy button |
| 18 | history quote for the current month | cannot be bought |
| 19 | unknown request id | "Work order not found." |
| 20 | events of premise 3 | the 198.5 V undervoltage event |
| 21 | events page, notifications section | says delivery is simulated (B11) |
| 22 | notifications of another consumer's premise | refused (50002) |
| 23 | bills page | bills and payment history of consumer2 |
| 24 | POST without CSRF token | refused (403) |
| 25 | add premise with a bad postal code | 50004 from the database |
| 26 | buy the current month | refused with 50008 ("current month is free") |
| 27 | pay someone else's bill #1 | refused |
| 28 | right to be forgotten without the confirmation box | refused, nothing submitted |

**Rerun:** `consumer_pages.sh` at 13:34 UTC: **63 / 63 passed**.

**Why:** `public/login.php` refuses an email with 429 for 15 minutes after 5 wrong passwords from the same address. K-04 did
exactly that to consumer2 at about 13:17 UTC; the consumer suite started at about 13:26, inside the 15 minutes. To avoid it,
run K-04 last, or wait 15 minutes after it.

`accounts.sh` was run on 28/11: see the first section.
