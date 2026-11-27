# Deploy MDMS-Cy on the department web server

Result: the full web application at **`https://students.cs.ucy.ac.cy/~<your login>/mdms/`**, using the team database
on **`mssql.cs.ucy.ac.cy\SQL2025`**. Everyone can install it in their own account; it takes about 5 minutes.

| File in `deploy/` | What it is |
|---|---|
| `mdms-app.zip` | the application (`src/`, `areas/`, `public/` of `sources/`), no settings, no password |
| `install.sh` | installs **and** updates it in your home folder (the commands below) |
| `mdms-check.php` | optional one-time check of the server (PHP version, PHP user, ...) |
| `build_zip.py` | rebuilds `mdms-app.zip` from `sources/` after a code change |

## How it works (why there is a Connect page)

* The web server runs PHP **8.0.30** as the user **`apache`**, not as you. Every file PHP can read is therefore readable by
  every other account on the department machines, and the home folders do not support ACLs.
* So **no password is stored on the server.** The first page asks for the database name, login and password (as in Lab 7)
  and keeps them only in your PHP session on the web server. Then the normal MDMS-Cy login page appears.
* Only `~/mdms/public` is visible on the web, through the link `~/public_html/mdms -> ~/mdms/public`.
  `src/`, `areas/` and `var/` (uploads) stay outside `public_html`.

## 0. Before you start

* University VPN if you are not on campus.
* The database must hold the MDMS build. Check in SSMS (`mssql.cs.ucy.ac.cy\SQL2025`, database `ichara09`):
  ```sql
  SELECT name FROM sys.database_principals WHERE name = 'mdms_php';   -- 1 row
  SELECT COUNT(*) FROM sys.procedures;                                 -- about 127
  SELECT COUNT(*) FROM dbo.USER_ACCOUNT;                               -- more than 0
  ```

## 1. Upload two files to your HOME folder (not `public_html`)

`deploy/mdms-app.zip` and `deploy/install.sh`:

* Lab PC: copy both into `U:\`.
* Own PC (PowerShell, VPN on; `<host>` = the department Linux machine you SSH into):
  ```powershell
  scp deploy\mdms-app.zip deploy\install.sh <login>@<host>:~/
  ```

## 2. Install (the same command updates later)

In a terminal on a department Linux machine:

```bash
bash ~/install.sh
```

It ends with `Done. Open https://students.cs.ucy.ac.cy/~<login>/mdms/`. What it does (you can also paste these lines):

```bash
cd ~ && unzip -o -q mdms-app.zip && rm mdms-app.zip
find ~/mdms -type d ! -path "$HOME/mdms/var*" -exec chmod 711 {} +
find ~/mdms/public -type d -exec chmod 755 {} +
chmod 755 ~/mdms/areas
find ~/mdms -type f ! -path "$HOME/mdms/var/*" -exec chmod 644 {} +
mkdir -p ~/mdms/var/throttle ~/mdms/var/technician-documents ~/mdms/var/technician-photos ~/mdms/var/meter-certificates
chmod 1733 ~/mdms/var ~/mdms/var/*
[ -f ~/mdms/src/config.local.php ] || sed "s/__USER__/$USER/" ~/mdms/src/config.ucy.sample.php > ~/mdms/src/config.local.php
chmod 644 ~/mdms/src/config.local.php
chmod 701 ~ && mkdir -p ~/public_html && chmod 755 ~/public_html
ln -sfn ~/mdms/public ~/public_html/mdms
```

| Permission | Why |
|---|---|
| `~` 701, `public_html` 755, files 644 | Lab 7 rules |
| `~/mdms/areas` **755** | the menus are found by listing this folder; with 711 every menu is empty |
| `~/mdms/var` + 4 subfolders **1733** | PHP can save uploads; other accounts cannot list or delete them |
| `config.local.php` 644 | it holds **no password** (server, database name, login name, URL folder) |

## 2b. Demo technician photos (once per server)

The demo technicians (`tech1`–`tech3`) have a photo. Its files are not in the zip (the zip never touches `var/`).

1. Upload the folder `deploy/demo-photos/` to your home: `scp -r deploy\demo-photos <login>@<host>:~/`
2. On the department machine:
   ```bash
   install -m 644 ~/demo-photos/*.jpg ~/mdms/var/technician-photos/ && rm -r ~/demo-photos
   ```
3. A database built before 27/11/2026 still has the old photo paths: run `sql/fix_demo_photo_paths.sql` once in SSMS.
   Running it again changes nothing. A database built later already has the right paths.

Check: log in as `tech1@mdms.cy` → *My profile* → *Show my photo*: the photo appears instead of "Photo unavailable".

## 3. Use it

1. Open `https://students.cs.ucy.ac.cy/~<login>/mdms/` (with **`/mdms/`**; without it you get your Lab 7 pages).
2. **Connect to the database**: database `ichara09`, login `ichara09` (pre-filled), the SQL password. 5 wrong passwords
   -> wait 15 minutes (protects the SQL login).
3. **Log in** with a demo account (password `Passw0rd!23`):
   `consumer1@example.cy`, `tech1@mdms.cy`, `officer1@mdms.cy`, `admin@mdms.cy`, `dso@mdms.cy`, `tso@mdms.cy`,
   `billing@eacsupply.cy`, `desk@flexpool.cy`. 5 wrong passwords for one account -> that account waits 15 minutes.
4. **Log out** keeps the database connection (log in as another role at once). **Disconnect** (login page) forgets it;
   so does about 20-30 minutes without activity.

## 4. Update after a code change

1. Rebuild the zip from the code: `python deploy/build_zip.py` (commit the new zip with the code change).
2. Upload `mdms-app.zip` (and `install.sh` if it changed) to your home folder.
3. `bash ~/install.sh` again. Your settings and the uploaded files are kept.

## Rules

* **Never** put the database password in a file on the server and never set `DB_PASS` in `config.local.php` there.
* The SQL2025 database is the team database (the demo): tests that write (`WRITE=1`) run on a local copy only (see
  `TESTING_PLAN.md`).
* Change the SQL password after grading: that login owns the database.

## Troubleshooting

| What you see | Fix |
|---|---|
| Lab 7 page ("Connected", Q1-Q3) | the address lacks `/mdms/` |
| 403 Forbidden | `bash ~/install.sh` again; `ls -ld ~` must be `drwx-----x` |
| 404 at `/~login/mdms/` | the link is missing: `ls -l ~/public_html` must show `mdms -> .../mdms/public` |
| Logged in, but the menu is empty | `chmod 755 ~/mdms/areas` |
| Links jump to `students.cs.ucy.ac.cy/consumer/...` | `grep BASE_PATH ~/mdms/src/config.local.php` must say `/~<login>/mdms` |
| "Login failed: check the login name and the password" on Connect | wrong SQL login or password |
| "cannot open the database" on Connect | wrong database name |
| "Service problem" after logging in | the database lacks the MDMS build or `mdms_php` (step 0) |
| An upload is refused | `ls -ld ~/mdms/var` must be `drwx-wx-wt`; if the server still refuses, `chmod 700 ~/mdms/var ~/mdms/var/*` (uploads off, the rest works) |
| "Too many ... attempts" | wait 15 minutes, or use another demo account |

## Optional: check a server account first

Upload `mdms-check.php` into `~/public_html`, `chmod 644 ~/public_html/mdms-check.php`, open
`https://students.cs.ucy.ac.cy/~<login>/mdms-check.php`. Needed: PHP >= 8.0, `sqlsrv: yes`, `open_basedir: (none)`.
It prints no passwords. Delete it afterwards: `rm ~/public_html/mdms-check.php`.

## Remove the application

```bash
rm ~/public_html/mdms     # the link only (no "/" at the end)
rm -r ~/mdms              # the application and its uploaded files
```
