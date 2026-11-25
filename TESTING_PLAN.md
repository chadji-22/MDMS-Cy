# MDMS-Cy · Test plan (automatic + manual, per member)

Everyone tests **their own area** after every change, runs the **gate** before merging into `io`, and records results in
the log at the end. Deployment steps: [`deploy/DEPLOY.md`](deploy/DEPLOY.md). Code rules: [`sources/README.md`](sources/README.md).

## 1. Who owns what

From the checklist split (`PROJECT_STATUS_AND_CHECKLIST.md`, section B); change it there if the team decides otherwise.

| Member | Areas (tasks) | Pages |
|---|---|---|
| **Ioannis (I)** | B1 framework, Connect page and deploy, B3 consumer, B11 notifications | `src/`, `public/connect.php`, `public/consumer/`, `deploy/` |
| **Kostis (K)** | B2 accounts, B4 market, B7 DSO, B8 TSO, B9 map, B10 security | `public/login.php`, `register*.php`, `account/`, `market/`, `dso/`, `tso/` |
| **Eliana (E)** | B5 technician, B6 officer / admin | `public/technician/`, `public/staff/`, `account/documents.php` |

## 2. Where tests run

| Code | Environment | Database | Allowed |
|---|---|---|---|
| **L** | your PC: container of `sources/README.md` option A (`DB_PASS` in the environment, no Connect page) | **a local copy** (local SQL Server with `build_all.sql` + `import.sql`) | everything, incl. `WRITE=1` |
| **R** | server replica: `sources/dev/ucy-replica.sh` (PHP 8.0.30, user folder, PHP as another user, Connect page) | the local copy | everything; **before every deploy** |
| **S** | the department server `https://students.cs.ucy.ac.cy/~<login>/mdms/` | **SQL2025 `ichara09`: the team / demo database** | read-only suites + manual tests; small, deliberate writes only |

Rules for **S**: no `WRITE=1`, no `accounts.sh` (it creates users), no load or perf tests (27 MB data / 20 MB log cap),
`smoke.sh` at most 3 times per 15 minutes (it fails logins on purpose and trips the login lock). Every login adds one
audit row. The SQL password is typed on the Connect page and never written in a file or a command.

## 3. Automatic tests

All commands from `sources/` in Git Bash (Windows: prefix `podman ...` commands with `MSYS_NO_PATHCONV=1`).

| Test | Checks | Command | Where | Writes |
|---|---|---|---|---|
| `tests/audit_pages.php` | every page: guard, CSRF, no SQL strings, every procedure call exists with the right number of parameters, escaping, no inline script, **no bare `/...` link** | `php tests/audit_pages.php` (or in the container) | any, no DB | no |
| `tests/errors_test.php` | error mapping of the catalog 50001-50008 / 51001-51012 | `php tests/errors_test.php` | any, no DB | no |
| `tests/db_integration.php` | real database errors, Greek text, `EXECUTE AS mdms_php`; needs `tests.sql` run once | `podman exec -w /var/www/html mdms-web php tests/db_integration.php` | L | 2 audit rows |
| `tests.sql` (repo root) | the database itself (Build Spec §14), PASS/FAIL table at the end | SSMS / sqlcmd on the local copy | L | yes (re-runnable) |
| `tests/smoke.sh` | login, menus per role, 403s, CSRF, cookies, logout, open redirect | `BASE_URL=... bash tests/smoke.sh` | L R S | audit rows |
| `tests/connect.sh` | Connect page: refused logins, connect, login/logout keeps it, Disconnect, JSON 401 | `BASE_URL=... DB_FORM_PASS=... bash tests/connect.sh` | R S | audit rows |
| `tests/consumer_pages.sh` | B3 consumer pages; `WRITE=1` also the write flows (as consumer9) | `BASE_URL=... [WRITE=1] bash tests/consumer_pages.sh` | L R (S read-only) | with `WRITE=1` |
| `tests/market_dso_tso.sh` | B4 market + JSON, B7 DSO chain, B8 TSO, B9 map data, B10 throttling | `BASE_URL=... [WRITE=1] bash tests/market_dso_tso.sh` | L R (S read-only) | with `WRITE=1` |
| `tests/accounts.sh` | B2 register consumer / technician, profile, password, technician documents (uploads) | `BASE_URL=... bash tests/accounts.sh` | L R only | **always** (new users) |
| `tests/crawl_links.py` | logs in as all 8 roles, opens every reachable page, every link / form / script / redirect stays under the base path, no 404/500 | `python tests/crawl_links.py <BASE_URL>` | L R S | audit rows |
| `tests/run_all.sh` | all HTTP tests above in one go, with a summary | `BASE_URL=... [WRITE=1] [DB_FORM_PASS=...] bash tests/run_all.sh` | L R (S without `WRITE`) | as above |

`DB_FORM_PASS` (only for an instance with the Connect page) is read from the environment and never printed. Pass it
without leaving it in the shell history, e.g. `read -rs DB_FORM_PASS && export DB_FORM_PASS`.

Results on 25/11 (branch `ioannis/B12-subfolder-deploy`, merged into `io` 25/11): audit 0 errors / 15 review lines; L and R: smoke all passed, connect 23/23,
consumer 63/63, market/dso/tso 160/160, accounts all passed, crawl 162 pages, no problems, 0 PHP warnings on PHP 8.0.30.

### The gate: before merging into `io` (everyone, for their branch)

1. `php tests/audit_pages.php` -> `0 errors` (new pages must use `View::base()` / `View::url()`, README rule 10).
2. On **L**: `BASE_URL=http://localhost:8080 WRITE=1 bash tests/run_all.sh` -> every line `PASS`.
3. If `src/`, a page's links or anything deploy-related changed: on **R** (see 3.1) -> every line `PASS`.
4. Your manual tests (section 4) for the pages you changed, on **L**.
5. Write the result in the log (section 6) with the commit id.

### 3.1 Server replica (R), before every deploy (owner: Ioannis, anyone can run it)

```bash
python deploy/build_zip.py
podman build -t mdms-php80 -f sources/dev/Containerfile.php80 sources/dev          # once
DB_HOST=mdms-sql DB_NAME=<local db> DB_USER=<local login> bash sources/dev/ucy-replica.sh 8090
read -rs DB_FORM_PASS && export DB_FORM_PASS                                        # that login's password
BASE_URL=http://127.0.0.1:8090/~student/mdms WRITE=1 bash sources/tests/run_all.sh
podman rm -f mdms-ucy-replica
```

### 3.2 After a deploy (S), read-only

```bash
read -rs DB_FORM_PASS && export DB_FORM_PASS                                        # the SQL2025 password
BASE_URL=https://students.cs.ucy.ac.cy/~<login>/mdms bash tests/connect.sh
BASE_URL=https://students.cs.ucy.ac.cy/~<login>/mdms bash tests/smoke.sh
python tests/crawl_links.py https://students.cs.ucy.ac.cy/~<login>/mdms
```

## 4. Manual tests per member

Columns: **Env** = where (L local copy, S department server). On S only the read steps and the writes marked "S ok".
Demo password `Passw0rd!23`. Expected values from `REPORT.md` refer to the `import.sql` data. Each owner refines the steps
of their pages and adds a row for every new page.

### 4.1 Ioannis: framework, Connect page, deploy, consumer, notifications

| ID | Env | Account | Steps | Expected | Ref |
|---|---|---|---|---|---|
| I-01 | S | - | Open `/~<login>/mdms/`, type a wrong SQL password | "Login failed: check the login name and the password."; still on Connect | C13 |
| I-02 | S | - | Wrong database name, right password | "... cannot open the database ..." | C13 |
| I-03 | S | consumer1 | Connect, log in, Log out, log in as tso | no second Connect; tso menu only | C13 |
| I-04 | S | - | Log out, then on the login page press Disconnect (or open `connect.php` and press it) | back to the Connect page | C13 |
| I-05 | S | consumer1 | Leave the browser idle 35 minutes, then click a menu link | asked to connect / log in again | B1 |
| I-06 | S | any | Click through every menu entry | the address always stays under `/~<login>/mdms/`; no "Service problem" | C1-C11 |
| I-07 | S | consumer1 | Open `/~<login>/mdms/tso/` directly | 403 Access denied | B1 |
| I-08 | S | consumer1 | My premises, Readings for a premise | Greek addresses correct; 15-minute rows with import and export | UC-02 |
| I-09 | S | consumer1 | Totals: daily and monthly | daily totals of the imported days; monthly total of premise 1 | UC-03 |
| I-10 | L | consumer1 | Events and alerts: set the threshold of premise 1 to 10 kWh | a `THRESHOLD_EXCEEDED` event appears; the notification is recorded as SIMULATED (B11) | UC-04, B11 |
| I-11 | L | consumer1 | Past data: buy access to an older month | the older readings become visible | §1.2 |
| I-12 | L | consumer1 | Requests: submit a check request; open its History | state SUBMITTED, history listed | UC-05 |
| I-13 | L | consumer1 | Bills and payments: pay part of an open bill | `paid` / `remaining` updated | UC-06 |
| I-14 | L | consumer9 | Privacy (GDPR): submit a right-to-be-forgotten request | request listed as SUBMITTED | UC-07 |
| I-15 | S | - | `bash ~/install.sh` twice in a row | `Done` both times; uploads in `~/mdms/var` still there | deploy |

### 4.2 Kostis: accounts, market, DSO, TSO, map, security

| ID | Env | Account | Steps | Expected | Ref |
|---|---|---|---|---|---|
| K-01 | L | - | Create a consumer account (Greek name), log in with it | account works at once (no approval) | UC-01 |
| K-02 | L | - | Register as a technician | status PENDING; asked for documents; no jobs | UC-09 |
| K-03 | L | consumer1 | My profile: change the phone; Change my password, then log in with the new one | saved; old password refused | B2 |
| K-04 | L | consumer2 | Log in 5 times with a wrong password, then the right one | 6th try: "Too many failed logins" (HTTP 429); works again after 15 minutes. Not on S: it locks a demo account | B10 |
| K-05 | S | billing@eacsupply.cy | Portfolio, Day-Ahead, Intraday, "Same data as JSON" | tables; JSON opens; Intraday rows provisional | UC-18 |
| K-06 | S | billing@eacsupply.cy | Customer bills | no consumer ids shown | B4 |
| K-07 | S | desk@flexpool.cy | Market menu | no "Customer bills" (aggregator) | B4 |
| K-08 | L | dso@mdms.cy | Ingest packets: paste a valid JSON packet | MATCHED, readings inserted | UC-15 |
| K-09 | L | dso@mdms.cy | Run VEE -> Suspect readings: accept one, edit one -> Finalize a day | suspects listed; edit keeps original + corrected value | UC-16 |
| K-10 | S | dso@mdms.cy | Network reports: voltage, unbalance, losses for transformer 1 | report rows, no error | UC-19 |
| K-11 | S | tso@mdms.cy | Transformer tree; Current state; Frequency | tree indented by level; parents' import = sum of children | UC-17 |
| K-12 | L | tso@mdms.cy | Remote shedding: check, then confirm | commands created = active meters under the transformer | UC-13 |
| K-13 | S | tso@mdms.cy | Map: click a rectangle, a meter, an empty spot | coloured rectangles and points; popups with state | B9 |
| K-14 | L | - | Create a consumer account with the full name `Test <script>alert(1)</script>`, log in | the name is shown as text, no pop-up | B10 |
| K-15 | S | consumer1 | Open My profile; in another tab open `/~<login>/mdms/connect.php` and press Disconnect; then save the profile form | sent back to log in / connect; nothing saved | B10 |

### 4.3 Eliana: technician, officer / admin

| ID | Env | Account | Steps | Expected | Ref |
|---|---|---|---|---|---|
| E-01 | S | tech1@mdms.cy | Availability: view; (L: add a slot) | slots listed / saved | B5 |
| E-02 | S | tech1@mdms.cy | My jobs | jobs with location (latitude / longitude) | UC-05 |
| E-03 | L | tech1@mdms.cy | Accept a job, start it, complete it; decline another | states change; a declined request goes back to SUBMITTED | UC-05 |
| E-04 | L | tech1@mdms.cy | Register meter on an installation job; add the three certificates | meter PENDING until an officer confirms | UC-10 |
| E-05 | S ok | tech1@mdms.cy | My documents: upload a small PDF | accepted (if refused on S, see DEPLOY.md troubleshooting) | UC-09 |
| E-06 | L | officer1@mdms.cy | Technician approvals: open the PENDING technician, approve / reject a document | the document state changes; a rejected one can be resubmitted | UC-09 |
| E-07 | L | officer1@mdms.cy | Meter approvals: review a PENDING meter, download a certificate, confirm | meter ACTIVE | UC-10 |
| E-08 | S | officer1@mdms.cy | Work orders: open one, read its history | history of states | B6 |
| E-09 | L | officer1@mdms.cy | Remote commands: approve, dispatch, acknowledge a command | attempts counted, ACKNOWLEDGED, history | UC-12 |
| E-10 | L | officer1 + officer2 | GDPR review: pre-approve with officer1, approve with officer2 | the same officer cannot do both steps; request moves on | UC-07/08 |
| E-11 | L | officer1@mdms.cy | Catalogs: add a service type and an OBIS code | added without any schema change | UC-20 |
| E-12 | S | admin@mdms.cy | Accounts and organizations; Audit log; Statistics | lists open; the audit log shows the logins of the tests | B6 |
| E-13 | S | officer1@mdms.cy | Open `/~<login>/mdms/consumer/` directly | 403 Access denied | B6 |

## 5. Before the demo / oral exam

1. Gate (3) on `io`; replica run (3.1) on the zip of that commit; commit the zip.
2. Deploy (`deploy/DEPLOY.md`), then the read-only run (3.2) and I-01..I-07 on S.
3. Each member runs the S rows of their table on the deployed site.
4. Do not change demo data on S the day before; keep the SQL password at hand (typed on the Connect page).

## 6. Results log

| Date | Member | Commit | Env | Tests | Result / notes |
|---|---|---|---|---|---|
| 25/11 | I | B12 merge into `io` | L, R | `run_all.sh` (WRITE=1), audit, errors, db_integration | all passed; crawl 162 pages no problems |
| 25/11 | I | - | S | deployed, Connect + login confirmed in the browser | works |
| | K | | | | |
| 25–26/11 | E | c54b11c | L, S | E-01–E-13 | All 13 manual test scenarios exercised. E-08 fixed and verified locally. See detailed results below. |


### Eliana — Detailed manual testing results (25–26/11/2026)

| Test | Result | Notes |
|---|---|---|
| E-01 | PASS | Availability displayed on S; new slot saved on L. |
| E-02 | PASS (L) | Assigned jobs and meter coordinates displayed correctly locally. |
| E-03 | PASS with limitation | Fault repair completed successfully. Declined request returned to SUBMITTED; direct decline evidence is limited. |
| E-04 | PASS | Meter #13 registered with automatic transformer lookup and three certificates uploaded. Installation work order #15 completed. |
| E-05 | PASS | PDF uploaded successfully and document status set to PENDING. |
| E-06 | PASS with setup workarounds | Document approval, rejection, resubmission and final technician approval successful. |
| E-07 | PASS with limitation | All three certificates approved and meter activated. Premature activation did not proceed in the UI; TR04 was not independently verified. Certificate download was not explicitly verified. |
| E-08 | PASS AFTER FIX (L) | Officer work order history was missing. Added history and findings using the existing stored procedure. University deployment retest pending. |
| E-09 | PASS | Remote command progressed from PENDING_APPROVAL to APPROVED, SENT and ACKNOWLEDGED. Attempt count and timestamps recorded. |
| E-10 | PASS | Same-officer final approval denied. Second officer successfully approved the request. Review history confirmed both actors. |
| E-11 | PASS | New service type and OBIS code added without schema changes. |
| E-12 | PARTIAL | Admin pages, audit log and statistics verified. Full account and organization lists were not verified. |
| E-13 | PASS (UI) | Officer access to the consumer page denied. HTTP 403 status was not independently checked. |

### Fix implemented

- Commit: `c54b11c`
- Branch: `eliana/setup-testing`
- File: `sources/public/staff/work-order.php`
- Added officer work order history and findings using `sp_GetWorkOrderHistory`.
- PHP syntax validation passed.
- Manual verification on the local environment passed.
- No database schema changes were required.

### Testing environment and observations

- University SQL Server build and deployment completed successfully.
- Separate local SQL Server and PHP containers configured for write tests.
- Local upload directory permissions required configuration.
- The E-06 test account required a manual password reset after a password mismatch. No application login defect was confirmed.
- Installation and remote command test data were prepared using existing stored procedures.
- Local automatic pre-merge tests completed successfully.
- Post-deployment verification remains pending.

### Automatic testing results (26/11/2026)

| Test | Result |
|---|---|
| audit_pages.php | PASS: 117 procedure calls, 0 errors, 15 review notes |
| errors_test.php | PASS: all passed with APP_DEBUG=0 |
| smoke.sh | PASS |
| consumer_pages.sh | PASS: 63 passed, 0 failed |
| market_dso_tso.sh | PASS: 160 passed, 0 failed |
| accounts.sh | PASS |
| crawl_links.py | PASS: 163 pages, 2627 URLs, no problems |

All five run_all.sh suites passed on the local environment with WRITE=1.

The initial errors_test.php failure was caused by APP_DEBUG=1.
The test passed after disabling debug mode for the test execution.
No source code changes were required.

The Connect-page suite was not applicable to this local setup.
Server replica and post-deployment verification remain pending.

## 7. Known, not bugs

* `account/photo.php` answers 404 for the demo technicians: their photo files are not on the server (the crawl lists it
  as a note).
* Some pagers use query-only links (`href="?page=2"`): correct in any folder (crawl note).
* After about 20-30 minutes idle the server forgets the session: Connect again.
* The login lock also blocks the right password for 15 minutes after 5 wrong ones (by design).
