#!/usr/bin/env python3
"""C6: request every page of sources/public as every role and as an anonymous visitor.

Usage:  BASE_URL=http://127.0.0.1:8081 python crawl_pages.py accounts.json > pages.md
accounts.json = {"CONSUMER": "email", ...}  (one approved account per role, password from import.sql)

Expected result (project.pdf: role-based access, section 1):
  role listed in the page's Auth::requireRole(...)  -> not 401/403/5xx, no PHP error text in the body
  every other role                                   -> 403
  anonymous visitor on a guarded page                -> 3xx redirect to the login page (or 401/403)
GET only: forms are POSTed by the other test scripts. logout.php is skipped (it would end the session).
"""
import http.cookiejar, json, os, re, sys, urllib.error, urllib.parse, urllib.request

BASE = os.environ.get("BASE_URL", "http://127.0.0.1:8081").rstrip("/")
PW = os.environ.get("DEMO_PASSWORD", "Passw0rd!23")
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "sources", "public")
SKIP = {"logout.php", "health.php"}
ALERT = re.compile(r'role="alert"[^>]*>(.*?)</', re.S)
ERR = re.compile(r"(Fatal error|Parse error|Warning:|Notice:|Stack trace|Uncaught|SQLSTATE|Call to undefined)", re.I)
ALL_ROLES = ["CONSUMER", "TECHNICIAN", "SYSTEM_OFFICER", "SYSTEM_ADMIN", "DSO", "TSO", "SUPPLIER", "AGGREGATOR"]


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


def opener():
    jar = http.cookiejar.CookieJar()
    return urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar), NoRedirect)


def fetch(op, path, data=None):
    req = urllib.request.Request(BASE + path, data=data)
    try:
        r = op.open(req, timeout=60)
        return r.status, r.read().decode("utf-8", "replace"), r.headers
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace"), e.headers


def login(email):
    op = opener()
    _, body, _ = fetch(op, "/login.php")
    tok = re.search(r'name="_csrf" value="([^"]+)"', body).group(1)
    code, _, hdr = fetch(op, "/login.php", urllib.parse.urlencode({"_csrf": tok, "email": email, "password": PW}).encode())
    if code not in (302, 303):
        raise SystemExit(f"login failed for {email}: HTTP {code}")
    return op


def guard(path):
    src = open(os.path.join(ROOT, path), encoding="utf-8").read()
    m = re.search(r"Auth::requireRole\(([^)]*)\)", src)
    if m:
        return set(re.findall(r"'([A-Z_]+)'", m.group(1))), "roles"
    if "Auth::requireLogin()" in src:
        return set(ALL_ROLES), "any login"
    return None, "public"


def main():
    accounts = json.load(open(sys.argv[1]))
    pages = sorted(os.path.relpath(os.path.join(d, f), ROOT).replace("\\", "/")
                   for d, _, fs in os.walk(ROOT) for f in fs if f.endswith(".php") and f not in SKIP)
    sessions = {role: login(email) for role, email in accounts.items()}
    anon = opener()
    rows, bad = [], 0
    for page in pages:
        allowed, kind = guard(page)
        url = "/" + page
        for who in ["(anonymous)"] + ALL_ROLES:
            if who not in sessions and who != "(anonymous)":
                continue
            op = anon if who == "(anonymous)" else sessions[who]
            code, body, hdr = fetch(op, url)
            err = bool(ERR.search(body)) or code >= 500
            loc = hdr.get("Location", "") if hdr else ""
            if kind == "public":
                ok = code < 500 and not err
                expect = "any (public page)"
            elif who == "(anonymous)":
                ok = code in (301, 302, 303, 401, 403) and not err
                expect = "redirect to login / refused"
            elif who in allowed:
                ok = code not in (401, 403) and not err
                expect = "allowed"
            else:
                ok = code == 403 and not err
                expect = "403"
            bad += 0 if ok else 1
            note = loc if 300 <= code < 400 else ("PHP error text" if err else "")
            if not note and code == 200 and kind != "public" and who in (allowed or ()):
                al = [re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", a)).strip() for a in ALERT.findall(body)]
                al = [a for a in al if a]
                if al:
                    note = "alert: " + " / ".join(al)[:160].replace("|", "/")
            rows.append((page, who, code, expect, "OK" if ok else "FAIL", note))
    print("# C6 page matrix (real SQL Server 2022, fresh build)\n")
    print(f"{len(pages)} pages x {len(ALL_ROLES)} roles + anonymous = {len(rows)} requests, {bad} failed.\n")
    print("| page | role | HTTP | expected | result | note |\n|---|---|---|---|---|---|")
    for r in rows:
        print("| " + " | ".join(str(x) for x in r) + " |")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
