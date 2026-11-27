# Ioannis test report (27/11/2026)

Scope: Ioannis's part of [`TESTING_PLAN.md`](../TESTING_PLAN.md): B1 framework, Connect page and deploy, B3 consumer
pages, B11 notifications. Tests 3 (automatic + gate), 3.1 (replica R), 3.2 (read-only on S) and 4.1 (I-01 to I-15).
Commit tested: `5415192` (`testing` = `io`). Evidence with every output and command:
[`evidence/testing-ioannis/2026-11-27/`](../evidence/testing-ioannis/2026-11-27/README.md) (abbreviated `ev/` below).

How each test was done:
* **AUTO-L**, **AUTO-R**, **AUTO-S**: scripted with curl (and SQL checks on L), with the expected result checked by
  the script.
* **USER**: needs a person in a browser or an SSH session on the department machine. It is not marked as passed
  here.

## Summary

| Area | Result | Evidence |
|---|---|---|
| Static: `audit_pages.php`, `errors_test.php`, `php -l` on PHP 8.0.30 and 8.3.36 | PASS: 0 errors, 15 review lines (baseline), 91 files lint clean | `ev/static-php80.txt`, `ev/static-php83.txt` |
| DB: `tests.sql` (L) | PASS: 82/82 | `ev/db-tests_sql-L.txt` |
| DB: `db_integration.php` (L) | PASS | `ev/db-db_integration-L.txt` |
| Gate on L (`run_all.sh`, WRITE=1) | PASS: smoke, consumer 63/63, market/dso/tso 160/160, accounts, crawl 168 pages | `ev/gate-L-run_all.txt` |
| Replica R (3.1, `run_all.sh`, WRITE=1, Connect page) | PASS: smoke, connect 23/23, consumer 63/63, market/dso/tso 160/160, accounts, crawl 168 pages; 0 PHP warnings | `ev/gate-R-run_all.txt`, `ev/R-php-log-check.txt` |
| S (3.2, read-only, once) | PASS: connect 23/23, smoke all passed, crawl 151 pages no problems; the deployed code equals the committed `deploy/mdms-app.zip` | `ev/S-*.txt` |

## I-01 to I-15

| ID | How | Result | Evidence |
|---|---|---|---|
| I-01 wrong SQL password | AUTO-R, AUTO-S (`connect.sh`: "wrong password: 401 and a clear message", checks the text "Login failed: check the login name and the password." and still not connected) | PASS | `ev/gate-R-run_all.txt`, `ev/I-15-reinstall-R.txt`, `ev/S-connect.txt` |
| I-02 wrong database name | AUTO-R, AUTO-S (`connect.sh`: "right password, wrong database: 401 'cannot open the database'") | PASS | same |
| I-03 Connect, consumer1, Log out, tso | AUTO-R, AUTO-S (`manual_ro.sh`: after log out the login form opens with no Connect; tso sees only the `tso` menu; also `connect.sh`) | PASS | `ev/manual-I03-I07-I08-I09-{R,S}.txt` |
| I-04 Log out, then Disconnect | AUTO-R, AUTO-S (`connect.sh`: "Disconnect: 303 to the Connect page", then the login page asks for the database again) | PASS | `ev/S-connect.txt` |
| I-05 idle more than 30 min | AUTO-R (`i05_idle.sh`, 1900 s idle, then a menu page) | see `ev/I-05-idle-R.txt` (filled in below) | `ev/I-05-idle-R.txt` |
| I-05 on S | USER | open | checklist below |
| I-06 every menu entry stays under the folder | AUTO-R, AUTO-S (`crawl_links.py`: 8 roles, every link, form, script and redirect, no 404/500, no "Service problem") | PASS (S: 151 pages, 2,436 URLs) | `ev/S-crawl_links.txt` |
| I-07 consumer1 opens `/tso/` | AUTO-R, AUTO-S (`manual_ro.sh`: 403 and "Access denied"; also `smoke.sh`) | PASS | `ev/manual-I03-I07-I08-I09-S.txt` |
| I-08 premises, readings | AUTO-L, AUTO-R, AUTO-S. Greek addresses are intact. Premise 1 shows 96 fifteen-minute rows per day on L/R, after I-11. On S consumer1 has **not bought** October, so the page shows the 50008 reason and how to buy (by design, §1.2). Import + export rows were checked on prosumer premise 3 (consumer2) | PASS (see note N2) | `ev/manual-I08-I14-L.txt`, `ev/manual-I03-I07-I08-I09-{R,S}.txt` |
| I-09 daily and monthly totals | AUTO-L, AUTO-R, AUTO-S: premise 1 October 30/31 = 29.950 / 30.470 kWh, month 60.420 (L/R); S: premise 1 not bought (message), premise 3 the same daily / monthly totals | PASS (note N2) | same |
| I-10 threshold 10 kWh, THRESHOLD_EXCEEDED, SIMULATED (B11) | AUTO-L. The threshold was saved on the page. Event 22 (October, 60.42 > 10 kWh) exists, and its NOTIFICATION rows are EMAIL=SIMULATED and SMS=SIMULATED (read-only query). The events page shows the event, the SIMULATED rows and "delivery is simulated". `tests.sql` M1-M6 cover the trigger path (TR21 → TR23) | PASS (note N3) | `ev/manual-I08-I14-L.txt`, `ev/db-tests_sql-L.txt` |
| I-11 buy an older month | AUTO-L: premise 1, October: "not bought" → quote 2.00 € → bought → readings visible | PASS | `ev/manual-I08-I14-L.txt` |
| I-12 check request, History | AUTO-L: TECHNICAL_CHECK #2033 SUBMITTED, History listed, in My requests; cancelled afterwards | PASS | same |
| I-13 pay part of an open bill | AUTO-L: bill #2, 1.00 €: paid 0.00→1.00, left 19.33→18.33, ISSUED→PARTIALLY_PAID (page and SQL) | PASS | same |
| I-14 right to be forgotten (consumer9) | AUTO-L: request #1007 listed as SUBMITTED; officer1 then rejected it on L so consumer9 stays usable | PASS | same |
| I-15 `install.sh` twice | AUTO-R: second install as `student` with the committed zip: `Done`, exit 0. Uploads kept (9 files, same hash), mode `drwx-wx-wt`, settings file unchanged, code replaced. Then connect 23/23 and accounts all passed | PASS on R | `ev/I-15-reinstall-R.txt` |
| I-15 on S | USER (needs SSH on the department machine) | open | checklist below |

## Findings

No test showed a bug in the application. **No code was changed.**

* **N1. The zip is not reproducible across checkouts (line endings).** `python deploy/build_zip.py` gives a different
  zip from the committed one (`5ddcb528…` vs `345fd7e9…`).
  * Both zips hold exactly HEAD's 93 files once CR bytes are ignored. The committed zip has CRLF in 70 of 93 files; the
    rebuilt one has CRLF in 92 of 93.
  * Cause: `core.autocrlf=true` on Windows. `sources/.gitattributes` fixes the line endings only for `*.sh`, so PHP,
    JS and CSS files are checked out as CRLF and packed as they are.
  * It does no harm: PHP 8.0 runs the CRLF files, and the R gate passed on the rebuilt zip. But "same code -> same
    zip" (`build_zip.py`) does not hold, so comparing zips needs CR stripped.
  * Fix, not applied because it changes the build: add `*.php text eol=lf`, `*.js text eol=lf`, `*.css text eol=lf`
    to `sources/.gitattributes` and check out again, or let `build_zip.py` turn CRLF into LF.
  * The rebuilt zip was not committed; the committed zip (= S) is unchanged.
* **N2. The I-08 / I-09 wording does not match the demo data.**
  * Premise 1 (consumer1) is not a prosumer, so its readings have no export column.
  * October is past data, which consumer1 has not bought on S. Readings and totals of premise 1 therefore show the
    "not bought" message until I-11 is done.
  * Proposed wording: "consumer2, premise 3" for import + export and totals, or run I-11 first (L only).
* **N3. In I-10, saving a threshold does not raise an event at once.**
  * TR21 raises it when final daily totals arrive. `sp_CheckConsumptionThresholds` also raises it, but only officers
    can run that procedure, from SQL; no page calls it.
  * With `import.sql`, the event for premise 1 already exists (October). The expected result is met, but a new event
    appears only when new consumption passes the threshold.
* N4. Documentation nits:
  * The gate in `TESTING_PLAN.md` uses `http://localhost:8080`; the L container of this setup is on `:8081`.
  * Section 2 allows `smoke.sh` 3 times per 15 minutes on S. Each run makes 2 wrong passwords for consumer1, so 3 runs
    make 6 failures and trip the lock (5). Once per 15 minutes is the safe limit.
* N5. The crawl now finds 168 pages on L/R (162 on 25/11). The extra pages are rows created by the repeated `WRITE=1`
  runs, not new pages.

## USER checklist (a person must do these; expected results in **bold**)

1. **I-05 on S, idle.**
   1. Open `https://students.cs.ucy.ac.cy/~ichara09/mdms/` with the VPN on.
   2. Connect with database `ichara09`, login `ichara09` and the SQL password.
   3. Log in as `consumer1@example.cy` / `Passw0rd!23`. Open *My premises*.
   4. Touch nothing for 35 minutes, then click *Readings*.
   5. **Expected: you land on the Connect page or the login page.** A login page that then asks to Connect is
      also correct.
2. **I-15 on S, install twice.** Use an SSH session on a department Linux machine.
   1. Record the state: `ls -ld ~/mdms/var ~/mdms/var/*; find ~/mdms/var -type f | wc -l`.
   2. Copy `deploy/mdms-app.zip` and `deploy/install.sh` to `~`. The committed zip is the one already deployed, so
      nothing changes.
   3. Run `bash ~/install.sh`.
   4. Copy the zip again and run `bash ~/install.sh` again.
   5. **Expected: `Done. Open https://students.cs.ucy.ac.cy/~ichara09/mdms/` both times.** The same `find … | wc -l`
      count as before. `ls -ld ~/mdms/var` shows **`drwx-wx-wt`**. The site still opens: Connect, then log in.
3. **Visual check on S** (browser, consumer1): *My premises* shows **"Λεωφ. Στροβόλου 101", "Οδός Γρίβα Διγενή 12"**
   in Greek letters, not `?` or boxes. Click every menu entry once: **no "Service problem"**, and the address always
   starts with `/~ichara09/mdms/`.
4. **I-01 / I-02 in a browser** (optional; each costs one refused attempt, at most 5 per 15 minutes):
   * A wrong password shows **"Login failed: check the login name and the password."**
   * A wrong database name shows **"… cannot open the database …"**.
   * In both cases you stay on the Connect page.

## Re-run everything (from the repository root, Git Bash)

```bash
podman machine start; podman start mdms-sql mdms-web-local
E=evidence/testing-ioannis/<date>; R="$(pwd -W)"
# static, PHP 8.0 and 8.3 (no PHP on the host)
for img in mdms-php80 mdms-php-dev; do MSYS_NO_PATHCONV=1 podman run --rm -v "$R:/repo" -w /repo/sources -e APP_DEBUG=0 \
  --entrypoint sh localhost/$img -c 'php tests/audit_pages.php; php tests/errors_test.php; for x in $(find /repo/sources /repo/deploy -name "*.php"); do php -l "$x" >/dev/null || echo "LINT $x"; done'; done
# DB, L (sa password from the container, never printed)
SQLCMDPASSWORD="$(MSYS_NO_PATHCONV=1 podman exec mdms-sql printenv MSSQL_SA_PASSWORD)" /c/Users/ioann/tools/sqlcmd/sqlcmd.exe \
  -S 127.0.0.1,11433 -U sa -d mdms2 -C -I -b -W -i tests.sql
MSYS_NO_PATHCONV=1 podman exec -w /var/www/html mdms-web-local php tests/db_integration.php
# gate, L
BASE_URL=http://127.0.0.1:8081 WRITE=1 bash sources/tests/run_all.sh
# replica R
python deploy/build_zip.py      # then: git restore deploy/mdms-app.zip, unless the code changed (see N1)
MSYS_NO_PATHCONV=1 DB_HOST=mdms-sql DB_NAME=mdms2 DB_USER=mdms_web bash sources/dev/ucy-replica.sh 8090
export DB_FORM_PASS="$(MSYS_NO_PATHCONV=1 podman exec mdms-web-local printenv DB_PASS)"
BASE_URL=http://127.0.0.1:8090/~student/mdms WRITE=1 bash sources/tests/run_all.sh
bash $E/scripts/i05_idle.sh http://127.0.0.1:8090/~student/mdms "$(pwd)/$E/I-05-idle-R.txt" 1900 &   # I-05, 32 min
BASE_URL=http://127.0.0.1:8090/~student/mdms bash $E/scripts/manual_ro.sh
#   I-15: podman cp <zip> mdms-ucy-replica:/home/student/mdms-app.zip; podman exec mdms-ucy-replica sh -c
#         'chown student:cs24 /home/student/mdms-app.zip && su student -c "bash ~/install.sh"'; then connect.sh + accounts.sh
# manual writes, L
SQLCMDPASSWORD="$(MSYS_NO_PATHCONV=1 podman exec mdms-sql printenv MSSQL_SA_PASSWORD)" BASE_URL=http://127.0.0.1:8081 \
  SQLCMD=/c/Users/ioann/tools/sqlcmd/sqlcmd.exe bash $E/scripts/manual_L.sh
podman rm -f mdms-ucy-replica
# S, read-only, once (VPN; password from the Windows user variable, never printed)
export DB_FORM_PASS="$(powershell.exe -NoProfile -Command "[Console]::Out.Write([Environment]::GetEnvironmentVariable('SQLCMDPASSWORD','User'))" | tr -d '\r\n')"
S=https://students.cs.ucy.ac.cy/~ichara09/mdms
BASE_URL=$S bash sources/tests/connect.sh; BASE_URL=$S bash sources/tests/smoke.sh; python sources/tests/crawl_links.py $S
BASE_URL=$S bash $E/scripts/manual_ro.sh
```
