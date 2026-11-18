# MDMS-Cy web application (`sources/`)

Plain PHP ≥ 8.1 with the SQLSRV driver. No Composer, no framework. Every page only calls stored procedures.
Task **B1** (framework) is this folder; pages are tasks B2–B9.

## Layout

```
public/            web root (the only folder the web server serves)
  login.php logout.php home.php index.php
  assets/style.css
  consumer/ technician/ staff/ dso/ tso/ market/    one folder per area; each has an index.php placeholder
areas/<area>/menu.php     the menu entries of that area (outside the web root)
src/               the framework: Config, Db, DbError, Errors, Auth, Csrf, Menu, View, bootstrap.php
dev/Containerfile  development image (PHP + Apache + ODBC Driver 18 + sqlsrv)
tests/             errors_test.php, db_integration.php, smoke.sh
```

Area owners (see the checklist): consumer = B3 · market = B4 · technician = B5 · staff = B6 · dso = B7 · tso = B8.
Each person edits only their own `public/<area>/` and `areas/<area>/menu.php`, so nobody collides.

## Run it

Settings are read from environment variables (or from `src/config.local.php`, which is git-ignored; copy
`src/config.sample.php`). **Never commit the password.**

| Variable | Meaning |
|---|---|
| `DB_HOST` | `mssql.cs.ucy.ac.cy` (SQL Server 2022; not `...\SQL2025`) |
| `DB_NAME`, `DB_USER`, `DB_PASS` | your database, login, password |
| `DB_RUN_AS` | `mdms_php` (default): the connection switches to this restricted user, see *Security* |
| `APP_DEBUG` | `1` on your own machine only: enables `/health.php` and shows technical detail |

**A. Podman or Docker (what the framework was developed with)**
```bash
podman build -t mdms-php-dev -f sources/dev/Containerfile sources/dev
DB_PASS="$SQLCMDPASSWORD" podman run -d --name mdms-web -p 8080:80 \
  -v "$(pwd)/sources:/var/www/html:Z" \
  -e DB_HOST=mssql.cs.ucy.ac.cy -e DB_NAME=<db> -e DB_USER=<login> -e DB_PASS -e APP_DEBUG=1 mdms-php-dev
# open http://localhost:8080   (demo accounts of import.sql, password Passw0rd!23: consumer1@example.cy, officer1@mdms.cy, tso@mdms.cy ...)
```
On Windows Git Bash prefix the command with `MSYS_NO_PATHCONV=1` and use `$(pwd -W)` for the folder.

**B. XAMPP / UCY web server**: PHP ≥ 8.1 with the `sqlsrv` extension (Microsoft Drivers for PHP) and ODBC Driver 17/18.
Point the document root at `sources/public`, and put the settings in `src/config.local.php`.

**C. Without Apache**: `cd sources && php -S 127.0.0.1:8080 -t public` (needs `sqlsrv` in your PHP).

The database must be built first (`build_all.sql`, which runs `security.sql` and creates the user `mdms_php`).

## Tests

```bash
php tests/errors_test.php                       # no database needed
podman exec -w /var/www/html mdms-web php tests/db_integration.php     # real database errors, nothing committed
BASE_URL=http://localhost:8080 bash tests/smoke.sh                     # login, menus, 403s, CSRF, cookies
```
`db_integration.php` expects `tests.sql` to have been run (it uses the meter `SN-TEST-0001`).
Each login appends an audit row (`LOGIN_OK`): do not run the smoke test in a loop on the shared database.

## How to add a page (recipe)

1. Create `public/<area>/premises.php`:
```php
<?php
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';
use Mdms\{Auth, Csrf, Db, DbError, View};

Auth::requireRole('CONSUMER');                       // 1. the page guard
$error = null;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {         // 2. every POST: CSRF first
    Csrf::verify();
    try {
        Db::callAsActor('sp_SetPremiseThreshold', [(int) $_POST['premise_id'], (float) $_POST['kwh']]);
        View::flash('ok', 'Saved.');
        header('Location: /consumer/premises.php', true, 303); exit;
    } catch (DbError $e) { $error = $e; }            // 3. show the database's own message
}
$rows = Db::rows('sp_ListMyPremises');               // 4. read through a procedure
View::header('My premises');
if ($error) { View::error($error); }
foreach ($rows as $r) { echo '<p>' . View::h($r['address']) . '</p>'; }   // 5. escape EVERY value
View::footer();
```
2. Add one line to `areas/<area>/menu.php`: `['label' => 'My premises', 'href' => '/consumer/premises.php', 'roles' => ['CONSUMER']]`.

## Rules every page follows

1. **Procedures only.** `Db::call / callAsActor / rows / row`. No SQL strings anywhere. Values are bound parameters.
2. **The actor comes from the session.** `Db::callAsActor()` puts the logged-in user id first; never read an
   `actor_user_id` from a form, URL or cookie.
3. **Guard the page**: `Auth::requireRole(...)` (or `requireLogin()`); the procedures check the role again.
4. **Escape output**: `View::h($value)` for everything that comes from the database, the request or the session.
5. **Every `<form method="post">` has `Csrf::field()` and its handler starts with `Csrf::verify()`.**
6. **Text with Greek or passwords** is passed as `Db::nv($text, $maxLength)` (NVARCHAR), not a plain string.
7. **Errors**: catch `DbError`; `getUserMessage()` is safe to show. Unknown/technical errors are already reduced to a
   reference id (the detail is in the server log). `category()` is one of `not_found, permission, state, input,
   duplicate, login, busy, history, guard, server`.
8. Inline scripts/styles are blocked by the Content-Security-Policy: use files under `public/assets/`. A page that needs an
   external source (e.g. Leaflet map tiles) adds it: `View::$cspExtra['img-src'][] = 'https://tile.openstreetmap.org';`
   before `View::header()`.

## Security (what B1 provides, for the security document D9)

| Threat | Measure |
|---|---|
| SQL injection | only `{CALL dbo.sp_x(?, ...)}` with bound parameters; the procedure name is checked against `^sp_[A-Za-z0-9_]+$` |
| Unauthorised access | session only from a successful `sp_Login`; page guards; procedures re-check the role and ownership |
| Acting as someone else | actor id taken from the session only |
| Direct table access | after connecting, `EXECUTE AS USER = 'mdms_php'` (role `mdms_app`): procedures run, `SELECT/INSERT/UPDATE/DELETE` on tables and the `sp__` helpers are denied (error 229). The connection fails closed if the switch fails |
| Session theft / fixation | `HttpOnly` + `SameSite=Lax` (+ `Secure` on HTTPS) cookie, strict mode, new id at login, idle timeout 30 min |
| CSRF | one token per session, `hash_equals`, required on every POST (logout included) |
| XSS | `View::h()`; Content-Security-Policy `default-src 'self'`, no inline script/style |
| Login enumeration | the same status and message for a wrong password, an unknown email, an inactive and an anonymised user |
| Open redirect | `?next=` is accepted only as a path of this site |
| Information leak | unknown SQL errors show a reference id; the text goes to the server log only |
| Clickjacking / sniffing | `X-Frame-Options: DENY`, `frame-ancestors 'none'`, `nosniff` |

Not done yet (for B10): login throttling, `Secure`-only cookies behind HTTPS in production, an audit of every page against rules 1-8.
