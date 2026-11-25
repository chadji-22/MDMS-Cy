# (b) Security

*Second document, part (b). Spec: project.pdf §IV p. 13 (unauthorised access, SQL injection), Κοινές αρχές p. 5, §1.4 p. 6, §5.1 p. 10.*

Protection is built in layers, so that a mistake in one is caught by the next: **web page → database permissions → checks inside each procedure → triggers**.

## 1. Unauthorised access

**Login.** A user gets a session only after `sp_Login` accepts the password. A wrong password, an unknown email, an inactive and an anonymised user all get the same answer, "Login failed.", so the page does not reveal which accounts exist. Every attempt that reaches the database is written to `AUDIT_LOG`.

**Session.** The session id changes at login and after a password change. The cookie is `HttpOnly` and `SameSite=Lax`, and `Secure` on HTTPS. An idle session ends after 30 minutes.

**Roles, checked twice.** Each protected page starts with `Auth::requireRole(...)` or `Auth::requireLogin()`. The procedure behind it checks the role again with `sp__AssertRole`, and then **ownership**: a consumer sees only their own premises and bills, a technician only their own jobs, a supplier only its own customers.

**The actor cannot be forged.** The user id passed to a procedure always comes from the session (`Db::callAsActor`), never from a form, address or cookie.

**Checked.** 59 pages (all except logout and the developer check) were requested as each of the 8 roles and without login: 531 requests, 0 failures (`evidence/C6-integration/pages.md`).

## 2. Least privilege in the database

The site connects with the one login the course server gives us, and at once switches to the user `mdms_php` (`EXECUTE AS USER`). If the switch fails, the page stops. `mdms_php` has no login of its own and belongs to the role `mdms_app`, which may only **execute procedures**. Verified on our database (`evidence/D9`):

| Attempt as `mdms_php` | Result |
|---|---|
| `SELECT` from `USER_ACCOUNT` | denied (229) |
| `SELECT` from `view_CONSUMER` | denied (229) |
| `DELETE` from `AUDIT_LOG` | denied (229) |
| `EXEC sp__SetActor` (internal helper) | denied (229) |
| `CREATE TABLE` | denied (262) |

## 3. SQL injection

1. PHP sends only `{CALL dbo.sp_name(?, ?)}` with **bound parameters**. A value is never joined into SQL text.
2. The procedure name is fixed in the code and must match `^sp_[A-Za-z0-9_]+$`.
3. The only file that talks to the driver is `src/Db.php`.
4. The procedures, functions, views and triggers contain **no dynamic SQL** (no `EXEC(@text)`, no `sp_executesql`).

`tests/audit_pages.php` reads every page and looks for SQL outside `Db`; it checked 116 procedure calls with 0 errors.

## 4. Passwords

- Stored as SHA2-512 over the password and a random 16-byte salt per user (`fn_HashPassword`, `CRYPT_GEN_RANDOM`).
- No procedure or view returns the hash or the salt, and the views over user data are encrypted.
- 8 to 128 characters, sent as `NVARCHAR` so that Greek passwords work.
- **Guessing is slowed down:** 5 failures for one email and address, or 50 from one address, in 15 minutes give "Too many attempts" (429). Registration is limited to 30 attempts per hour from one address.

## 5. Attacks through the browser

| Threat | Measure |
|------|--------------|
| Script in stored data (XSS) | every value goes through `View::h()`; the map uses `textContent`; the Content-Security-Policy allows only our own scripts |
| Forged form (CSRF) | a token per session on every POST, compared with `hash_equals`; logout included |
| Change by a link | every form that changes data is a POST; shedding needs a second, confirmed step |
| Hostile upload | type read from the content, at most 2 MB, random name, stored outside the web root, served only through a page that checks access |
| Wrong input | one check per kind of value (`src/Validate.php`); the database checks again |
| Clickjacking, sniffing, open redirect | `X-Frame-Options: DENY`, `nosniff`, redirects only inside the site |
| Error details | the user sees a reference number; the text goes to the server log |
| Downgrade to HTTP | `Strict-Transport-Security` when the request is HTTPS |

## 6. Personal data (GDPR)

- Suppliers and aggregators get only sums; groups of fewer than 3 meters are hidden.
- The right to be forgotten passes submission, review, pre-approval and approval, each logged. The final approval must come from a **different officer**.
- Raw readings are deleted after their retention time; aggregates stay.

## 7. Traceability

`AUDIT_LOG` records who, when, through which procedure, and the old and new state. Triggers write the changes of the critical tables, so a direct change there is recorded too. It is **append-only**: a trigger refuses updates and deletes. Final readings and aggregates are protected from change in the same way, and bills and payments are never deleted.

## 8. How it was tested

| Test | Result |
|---|---|
| `tests.sql` | 82 of 82 |
| `smoke.sh` (login, roles, CSRF, cookies) | 23 of 23 |
| `accounts.sh` (registration, passwords, uploads) | 47 of 47 |
| `market_dso_tso.sh` (roles, bad values, throttling) | 160 of 160 |
| `consumer_pages.sh` | 53 of 53 (read-only); 63 of 63 with writes (`evidence/C6-integration`) |

On SQL Server 2025 and Windows, random errors appeared because Windows reuses connections that had switched user. Connection pooling is therefore off (`Db.php`). The results above are from SQL Server 2025 with that change (`evidence/D9`); the runs on SQL Server 2022 are in `evidence/C6-integration`.

## 9. Known limits

1. **The switch of user can be undone.** `REVERT` in the same connection returns to the owner (`evidence/D9`). It needs SQL injection first, which section 3 prevents, but the restriction alone does not stop an injected `REVERT`. Adding `WITH NO REVERT` to `EXECUTE AS` closes it; we tested that SQL Server then refuses `REVERT` (15196). A separate login for the site would be stronger still.
2. **SHA2-512 is fast.** The salt stops ready-made tables, but a slow hash (bcrypt, Argon2) would resist guessing better if the table were stolen.
3. **Differencing.** Two allowed market sums can be subtracted: an area of 4 meters minus its part of 3 leaves one household.
4. The certificate of the course server is not verified (`DB_TRUST_CERT`), although ODBC Driver 18 encrypts the connection.
5. The device procedures have no user by design: the page guard is the only role check for a single pasted packet.
6. Other open sessions stay open after a password change, and uploads are not scanned for viruses.
7. The throttle counts per server and address, so an attacker with many addresses is slowed down less.
