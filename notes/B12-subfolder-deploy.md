# B12 · Run the web app from `public_html` (students.cs.ucy.ac.cy/~user/mdms/)

Branch: `ioannis/B12-subfolder-deploy` (from `io` at c1ce774). Goal: the full `sources/` app runs on the department
web server under a sub-folder URL and talks to our database on `mssql.cs.ucy.ac.cy\SQL2025`.

> **For everyone: the steps to install or update are in [`deploy/DEPLOY.md`](../deploy/DEPLOY.md) (`bash ~/install.sh`), the tests in
> [`TESTING_PLAN.md`](../TESTING_PLAN.md).** This file is the history: why each change was made and how it was tested.

## Why the app does not work there as it is

| # | Problem | Effect on `https://students.cs.ucy.ac.cy/~ichara09/mdms/` |
|---|---|---|
| P1 | 211 root-absolute URLs in 65 files (`href="/consumer/bills.php"`, `header('Location: /home.php')`, menu entries, `map.js`) | every link, form and redirect goes to `students.cs.ucy.ac.cy/consumer/...` → 404 |
| P2 | Session cookie path `/` | the cookie is sent to every student's site on the host |
| P3 | `Auth::safeNext()` accepts any path of the host | after login, `?next=` could send the user into another student's site |
| P4 | The app expects only `public/` to be served (`src/` holds the password file, `var/` holds uploads) | `public_html` cannot be pointed at `public/`; a layout is needed |
| P5 | `Db.php` does not ask for encryption (`Encrypt`) | with ODBC Driver 17 the password would travel unencrypted (Lab 7 uses `Encrypt => true`) |
| P6 | README / config sample say `DB_HOST = mssql.cs.ucy.ac.cy (not SQL2025)` | our current build is on the SQL2025 instance |

## Code changes (all in `sources/`)

| # | File | Change |
|---|---|---|
| C1 | `src/Config.php`, `src/config.sample.php` | new setting `BASE_PATH` (default `''` = served at the site root, as before). Sample shows `/~ichara09/mdms` and `mssql.cs.ucy.ac.cy\SQL2025` |
| C2 | `src/View.php` | `View::base()` (validated: `''` or `/seg/seg`, only `A-Z a-z 0-9 _ . ~ -`), `View::url($appPath)` (raw, for `Location:`), `View::href($appPath)` (= `h(url())`, for HTML). Layout links, stylesheet, logout form and error page use them |
| C3 | `src/Menu.php` | menu entries stay app paths (`/consumer/`); `forRole()` adds the base. The `areas/*/menu.php` files do not change |
| C4 | `src/Ui.php` | `Ui::redirect()` and `Ui::pager()` take app paths and add the base themselves |
| C5 | `src/Auth.php` | cookie path = base + `/`; login redirect uses `url('/login.php')`; `safeNext()` accepts only paths under the base, default `url('/home.php')` |
| C6 | `src/Db.php` | `'Encrypt' => true` on the connection (same as the Lab 7 skeleton) |
| C7 | every page in `public/` and `areas/consumer/lib.php` | each `href` / `action` / `src` literal → `<?= View::href('/...') ?>`; each `header('Location: /...')` → `View::url('/...')`. Variables such as `$path`, `$route`, `$detailUrl` stay app paths and get the base where they are printed or sent |
| C8 | `public/tso/map.php`, `public/assets/map.js` | the page gives the base to the script in `data-base`; `map.js` builds `map-data.php` URLs from it |
| C9 | `tests/audit_pages.php` | `View::href` counts as escaped; new rule **url**: a root-absolute literal in `href`/`action`/`src`/`Location` that does not go through `View::url/href` is an error (catches new pages) |
| C10 | `tests/smoke.sh` | the expected `next=` and redirect URLs include the base path of `BASE_URL` |
| C11 | `sources/README.md` | rule 10 "links go through `View::href()` / `View::url()`", deploy section for students.cs.ucy.ac.cy |

New pages written by anyone must follow C7, otherwise `audit_pages.php` fails (C9).

## Server layout (department web server)

```
~/                       701  (as Lab 7 says)
~/mdms/                  711  the whole sources/ folder (src, areas, public, var) - NOT under public_html
~/mdms/areas/            755  (Menu lists it with glob(); PHP runs as "other")
~/mdms/src/config.local.php   644, the settings WITHOUT the password (see "Secrets": the Connect page)
~/mdms/var/ + 4 subfolders   1733  uploads (PHP writes, others cannot list or delete)
~/public_html/           755
~/public_html/mdms  ->  ~/mdms/public      symbolic link: the only part the web sees
```

`src/config.local.php` on the server (put in the zip by the build, no secret in it):

```php
<?php
return [
    'DB_HOST'   => 'mssql.cs.ucy.ac.cy\SQL2025',
    'DB_NAME'   => 'ichara09',        // pre-filled on the Connect page
    'DB_USER'   => 'ichara09',        // pre-filled on the Connect page
    'DB_PASS'   => '',                // empty: typed on the Connect page, kept only in the PHP session
    'DB_RUN_AS' => 'mdms_php',
    'BASE_PATH' => '/~ichara09/mdms',
    'APP_DEBUG' => '0',
];
```

## What the server check found (`server-check/mdms-check.php`, 25/11)

| Check | Result | Consequence |
|---|---|---|
| PHP version | **8.0.30** (apache2handler) | C12 below: the app now runs on 8.0 |
| `sqlsrv`, `fileinfo`, `mbstring` | yes | - |
| `open_basedir` | none | `~/mdms` outside `public_html` can be read |
| symlink `public_html/probe -> ~/probe` | followed (the page ran) | the `~/public_html/mdms -> ~/mdms/public` layout works |
| PHP user | **`apache` (uid 48)**, not `ichara09` | PHP is "other" to our files: see Secrets, `areas/` and `var/` |
| chmod-600 file readable by PHP | no | the password file needs an ACL for `apache` (Secrets) |
| home writable by PHP | no | `var/` and its four subfolders get an ACL for `apache` |
| HTTPS | yes | session cookie gets `Secure` |

* **C12 (PHP 8.0)**: the only 8.1 feature was the `never` return type (`View::fail`, `Ui::redirect`, `Ui::json`); now `void`
  (they still always `exit`). Docs say PHP ≥ 8.0. `dev/Containerfile.php80` builds a PHP 8.0.30 + sqlsrv 5.11 test image
  (Debian 11 packages from archive.debian.org).
* **`areas/` must be 755**: `Menu::forRole()` lists it with `glob()`, and `apache` is "other". With 711 every role sees an
  empty menu (measured: consumer menu 1 link instead of 10). It is the only directory listing in the app.

## Secrets: the Connect page (C13, chosen 25/11)

POSIX ACLs are not supported on the home folder (`setfacl: Operation not supported`) and a separate low-privilege SQL login
is impossible (no ALTER ANY LOGIN, contained database authentication off). Any file PHP (`apache`) can read is therefore
readable by every account. So **no password is stored on the server**:

* `DB_PASS` empty in `config.local.php` -> the app shows `public/connect.php` (Lab 7 field names `dbName`, `userName`,
  `pswd`). The login is tested (`Db::test`, incl. `EXECUTE AS mdms_php`) and kept only in the PHP session on the web server
  (`/var/lib/php/session`, not on the shared home). Other students' shell accounts cannot read it; PHP scripts running as
  `apache` could in principle (same as Lab 7).
* It survives the application login/logout (switch demo roles without retyping); **Disconnect** or 30 min idle forgets it.
* 5 refused connection attempts per 15 min (per address and per browser session) so the SQL login is not locked.
* `config.local.php` (in the zip, made by the build) holds no secret: host, database, login name (pre-filled), BASE_PATH.
* With `DB_PASS` set (containers, XAMPP) nothing changes: no Connect page.
* `Throttle` (login lock, B10) falls back to the web server's temporary folder when `var/throttle` is not writable
  (`/tmp/mdms-throttle-<hash>`, mode 700, owner `apache`).
* Uploads: `var/` and its 4 subfolders `chmod 1733` (PHP can write; other accounts cannot list, and the sticky bit stops
  them deleting files; the owner can). With `700` instead, uploads are refused and everything else works.
* The SQL login is db_owner of the grading database: **change the SQL password after grading**.

## Database (SQL2025)

Nothing to change. The build on SQL2025 (25/11, commit 30ebc4f) has the same SQL files as `io`. To confirm (read-only,
needs the VPN): user `mdms_php` exists and none of the 92 procedures the pages name is missing.

## Verification

1. `php tests/audit_pages.php`: 0 errors, no new "review" lines, the new url rule passes.
2. Local container at the root (`BASE_PATH=''`): `tests/smoke.sh` passes (no regression).
3. Local container under `/~ichara09/mdms` (Apache Alias, `BASE_PATH=/~ichara09/mdms`): `smoke.sh` passes; a crawl that logs in
   as every role, opens every menu page and checks that every `href`/`action`/`src`/`Location` starts with the base (or is
   `https://` external) and that the base never appears twice.

## Results (25/11, local containers, local SQL Server copy of the same build)

* `php -l`: 87 files, no errors. `audit_pages.php`: 116 calls, 0 errors, the same 15 review lines as before the change.
  The new **url** rule on the unchanged `io` code: 118 errors (so it does catch bare links).
* `smoke.sh` at the root (`BASE_PATH=''`, port 8081): 23/23 passed. Under `/~ichara09/mdms` (Apache Alias, empty site
  root so a forgotten base gives 404, port 8082): 23/24 passed, including the new check that a `next` into another
  student's folder is ignored; the one failure was the login throttle ("Too many failed logins") after three runs in a
  few minutes (5 failures / 15 min per email, by design). Clean re-run at 16:20 after the window: **all passed** under
  `/~ichara09/mdms` (incl. the new `next` check) and **all passed** at the root.
* Link crawl (8 roles, 162 pages, 2,724 URLs): no URL outside `/~ichara09/mdms/`, base never doubled, every redirect inside
  the folder, `map.js` reads `data-base` and `map-data.php` answers 200. Two notes, identical at the root, so not caused
  by this change: `staff/audit.php` uses a query-only relative pager link (fine in any folder); `account/photo.php` answers
  404 for tech1 by design (the demo photo file is not on the server).
* Session cookie: `MDMSSESSID; path=/~ichara09/mdms/; HttpOnly; SameSite=Lax`.
* Upload package: `deploy/mdms-app.zip` (outside the repo): `mdms/src, areas, public` + empty `mdms/var/`; no
  `config.local.php`, no tests.

* POST flows (writes, local database only): `consumer_pages.sh` 63/63, `market_dso_tso.sh` 160 passed (incl. throttling),
  `accounts.sh` 47 passed - under `/~ichara09/mdms` and again at the root. `errors_test.php`: all passed.
* **PHP 8.0.30** (`mdms-php80`, sqlsrv 5.11): all 87 files parse; POST flows, crawl as above; no PHP warning in the log.
* **Server replica** (PHP 8.0.30, mod_userdir, user `ichara09` uid 10027 / group `cs24`, Apache as another user, app unzipped
  from `mdms-app.zip` and installed with the exact Step 2 commands, served through `~/public_html/mdms`): crawl 162 pages
  clean, `accounts.sh` (uploads into `var/`), `consumer_pages.sh`, `market_dso_tso.sh` all passed; another `cs24` account
  is denied the password file, the PHP user can read it; the owner can still delete files PHP wrote in `var/`.

## Deploy steps (department server, in a terminal on a department Linux machine)

**Step 0 - database** (SSMS, `mssql.cs.ucy.ac.cy\SQL2025`, db `ichara09`): done 25/11 (`mdms_php` exists, 127 procedures).

**Step 1 - upload** `deploy/mdms-app.zip` to the home folder `~` (`U:\`), NOT into `public_html`.

**Step 2 - install (the same block also updates)**:

```bash
cd ~ && unzip -o -q mdms-app.zip && rm mdms-app.zip
find ~/mdms -type d ! -path "$HOME/mdms/var*" -exec chmod 711 {} +
find ~/mdms/public -type d -exec chmod 755 {} +
chmod 755 ~/mdms/areas
find ~/mdms -type f ! -path "$HOME/mdms/var/*" -exec chmod 644 {} +
mkdir -p ~/mdms/var/throttle ~/mdms/var/technician-documents ~/mdms/var/technician-photos ~/mdms/var/meter-certificates
chmod 1733 ~/mdms/var ~/mdms/var/*
ln -sfn ~/mdms/public ~/public_html/mdms
```
No editing: `src/config.local.php` comes from the zip and holds no password. The zip has no `var/` entry and the block
skips `var/` contents, so running it again for an update keeps the uploads and the 1733 mode (tested on the replica: fresh
install and update over an install with uploads, block exit 0, all tests passed).

**Step 3 - test**: `https://students.cs.ucy.ac.cy/~ichara09/mdms/` -> Connect page (database `ichara09`, login `ichara09`,
SQL password) -> login page -> demo accounts (`Passw0rd!23`). Uploads: as `tech1@mdms.cy`, My documents, upload a small
PDF; if the real server refuses it (NFS / SELinux), `chmod 700 ~/mdms/var ~/mdms/var/*` (uploads off, the rest works).

**Step 4 - clean up the check files**:

```bash
rm ~/public_html/mdms-check.php ~/public_html/probe ~/mdms_probe.txt ~/mdms_probe600.txt
rm -r ~/probe
```

## Results of C13 (Connect page)

* Server replica, fresh install of the final zip with the exact Step 2 commands (PHP 8.0.30, mod_userdir, user ichara09
  uid 10027/cs24, PHP as another user, no ACLs, no password on disk, `var` 1733): `connect.sh` 23/23, crawl 162 pages clean,
  `consumer_pages.sh` 63/63, `market_dso_tso.sh` 160/160 (login lock via the temp folder), `accounts.sh` all passed
  (uploads), `smoke.sh` all passed, 0 PHP warnings/notices in the log. Another account: cannot list `var/`, cannot delete
  PHP's files (sticky bit); the owner can.
* With the password in the settings (root 8081, sub-folder 8082, PHP 8.0 8083): smoke, consumer, market/dso/tso, accounts
  all passed; `connect.php` redirects to the login page and no Disconnect button is shown.
* PHP 8.0 and 8.3 lint (89 `.php` files), `audit_pages.php` 0 errors (same 15 review lines), `errors_test.php` passed.

## Status

* [x] code changes C1–C13 (branch `ioannis/B12-subfolder-deploy`, merged into `io` 25/11)
* [x] verification (root, sub-folder, PHP 8.0, server replica with real permissions, Connect mode)
* [x] server check (PHP 8.0.30, PHP user `apache`, no ACLs)
* [x] SQL2025 (25/11): user `mdms_php` exists and `EXECUTE AS` works, 127 procedures, none of the 92 the pages name is missing, the 8 demo accounts are APPROVED and active
* [x] deployed 25/11 on https://students.cs.ucy.ac.cy/~ichara09/mdms/ (Connect page, user confirmed it works)
