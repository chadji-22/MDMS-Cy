# Security notes of the web layer (B10, input for D9)

What B1 already gives is in `README.md`, section *Security*. This file lists what B10 added, how it is checked, and what is left.

## Added by B10

| Threat | Measure | Where |
|---|---|---|
| Wrong or hostile input | Every value has one check (text, code, email, phone, IBAN, date, date-time, decimal, id). Decimals travel as text, so no digit is lost. A crafted array (`name[]=x`) counts as empty. The database still checks everything. | `src/Validate.php` |
| Stored and reflected XSS | All output through `View::h()` or a helper that calls it. The map builds its popups with `textContent`. JSON is sent with `nosniff` and with `<`, `>`, `&` escaped. | pages, `src/Ui.php`, `assets/map.js` |
| Third-party script | Leaflet 1.9.4 is served from this site, after its SHA-256 was compared with the published one. Only map tiles (images) come from outside, and only on the map page. | `assets/leaflet/`, `tso/map.php` |
| Hostile upload | Type read from the content, at most 2 MB, random name, stored outside the web root, deleted again if the database refuses. Served only to its owner. | `src/Upload.php`, `account/photo.php` |
| Password guessing | 5 failures per email and address, or 50 per address, in 15 minutes: answer 429. Same for known and unknown emails. | `src/Throttle.php`, `login.php` |
| Mass registration | At most 30 attempts per hour from one address. | `register*.php` |
| Session after a password change | New session id and new CSRF token. | `account/password.php` |
| Unreadable password | One limit (128 NVARCHAR characters) for registration, change and login. Before, a login longer than 128 *bytes* was refused, so a long Greek password could be stored and never used. | `Auth::login`, `Validate` |
| Change by a link | Every change is a POST with a token. The report pages write events only on POST. Shedding needs a second step with a confirmation. | `dso/reports.php`, `tso/shedding.php` |
| Acting as a device | `sp_RecordTransformerReading` and `sp_RaiseTamperEvent` accept "no user" for devices. The pages always pass the logged-in user, so the role check of the procedure applies. | `tso/frequency.php`, `dso/events.php` |
| Downgrade to HTTP | `Strict-Transport-Security` when the request is HTTPS. | `src/View.php` |

## How it is checked

- `php tests/audit_pages.php` reads every page of the team: guard, CSRF, SQL outside `Db`, inline script, actor from the request, and the
  number of parameters of every procedure call against the SQL files. "review" lines are for a person to read.
- `tests/accounts.sh` and `tests/market_dso_tso.sh` try wrong roles, missing tokens, bad values and uploads.

## Known limits

1. **Differencing in the market data.** A group with fewer than 3 meters is hidden, but two allowed answers can be subtracted: if an
   area of 4 meters and its part of 3 meters are both shown, the difference is one household. `@root_transformer_id` and the group
   level make this easy. The same holds for export when only one meter of a group exports. A fix belongs in `procedures_10_market.sql`.
2. A single packet goes through `sp_IngestTelemetryPacket`, which has no actor by design. The page guard is the only role check on the
   web side, and every application procedure can be executed by `mdms_app`.
3. Other open sessions of a user are not closed when the password changes. A deactivated user keeps a session, but every procedure refuses it.
4. The registration form says when an email is already registered. This cannot be avoided without sending email.
5. The throttle counts per server and per address. An attacker with many addresses is slowed down less.
6. Uploaded files are not scanned for viruses.
