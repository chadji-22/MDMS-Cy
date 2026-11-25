#!/usr/bin/env python3
"""C6: open the detail pages (they need ?id=) with real ids from the fresh database, as the right role.
crawl_pages.py cannot reach them: without an id they answer 400 by design.
Usage: BASE_URL=... python crawl_detail.py accounts.json > detail_pages.md
A page passes when it answers 200, shows no PHP error text and no role="alert" box (a caught database error)."""
import json, re, sys
import crawl_pages as c

CASES = [  # (page, role, id, what the id is)
    ("technician/job.php", "TECHNICIAN", 13, "accepted installation job 13"),
    ("technician/job.php", "TECHNICIAN", 1, "completed job 1"),
    ("technician/install-meter.php", "TECHNICIAN", 13, "accepted installation job 13"),
    ("technician/meter-certificates.php", "TECHNICIAN", 13, "pending meter 13"),
    ("staff/work-order.php", "SYSTEM_OFFICER", 1, "work order 1"),
    ("staff/work-order.php", "SYSTEM_ADMIN", 1, "work order 1"),
    ("staff/meter-review.php", "SYSTEM_OFFICER", 13, "pending meter 13"),
    ("staff/technician-review.php", "SYSTEM_OFFICER", 23, "pending technician 23"),
    ("staff/technician-review.php", "SYSTEM_OFFICER", 9, "approved technician 9 of import.sql"),
    ("staff/gdpr.php", "SYSTEM_OFFICER", 1, "GDPR request 1"),
    ("staff/remote-commands.php", "SYSTEM_OFFICER", 1, "remote command 1"),
]
accounts = json.load(open(sys.argv[1]))
sessions = {r: c.login(accounts[r]) for r in {x[1] for x in CASES}}
bad = 0
print("# C6 detail pages with real ids\n\n| page | role | id | HTTP | result | alert / note |\n|---|---|---|---|---|---|")
for page, role, i, what in CASES:
    code, body, _ = c.fetch(sessions[role], f"/{page}?id={i}")
    alerts = [re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", a)).strip() for a in c.ALERT.findall(body)]
    err = bool(c.ERR.search(body))
    ok = code == 200 and not err and not any(alerts)
    bad += 0 if ok else 1
    print(f"| {page} | {role} | {i} ({what}) | {code} | {'OK' if ok else 'FAIL'} | {' / '.join(a for a in alerts if a)[:140].replace('|', '/') or ('PHP error text' if err else '')} |")
print(f"\n{len(CASES)} requests, {bad} failed.")
sys.exit(1 if bad else 0)
