"""Time every page of the MDMS-Cy web app as every demo role (read-only: GET requests and logins only).

usage: DB_FORM_PASS=... python time_pages.py <BASE_URL> <out.csv> [repeats=3]
Per role: Connect (Connect page) + log in, crawl every page reachable by links (GET only, logout skipped, same rules as
tests/crawl_links.py), plus EXTRA parameterised read URLs (bigger windows, reports, map points, JSON). Every distinct
URL is fetched <repeats> times; the CSV has one row per URL with min / median / max seconds (wall clock from this PC,
so it includes the VPN, TLS, PHP, the SQL connection + EXECUTE AS and the procedures). Passwords are never printed.
"""
import csv
import html
import http.cookiejar
import os
import re
import statistics
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import deque, defaultdict
from datetime import date, timedelta

BASE_URL = sys.argv[1].rstrip('/')
OUT = sys.argv[2]
REPEATS = int(sys.argv[3]) if len(sys.argv) > 3 else 3
U = urllib.parse.urlparse(BASE_URL)
ORIGIN = f'{U.scheme}://{U.netloc}'
P = U.path.rstrip('/')
PW = 'Passw0rd!23'
ACCOUNTS = ['consumer1@example.cy', 'consumer2@example.cy', 'tech1@mdms.cy', 'officer1@mdms.cy', 'admin@mdms.cy',
            'dso@mdms.cy', 'tso@mdms.cy', 'billing@eacsupply.cy', 'desk@flexpool.cy']
ATTR = re.compile(r'\b(href|action|src)="([^"]*)"')
MAX_PAGES = 160

first = date.today().replace(day=1)
lm_end = first - timedelta(days=1)
lm_from = lm_end.replace(day=1)
d1 = lm_end - timedelta(days=1)
LM = lm_from.strftime('%Y-%m')
EXTRA = {
    'consumer1@example.cy': [
        f'/consumer/readings.php?premise_id=1&from={d1}&to={lm_end}',
        f'/consumer/aggregates.php?premise_id=1&period=DAY&from={lm_from}&to={lm_end}',
        f'/consumer/history.php?premise_id=1&from={LM}&to={LM}',
        '/consumer/events.php?premise_id=1',
    ],
    'consumer2@example.cy': [
        f'/consumer/readings.php?premise_id=3&from={d1}&to={lm_end}',
        f'/consumer/readings.php?premise_id=3&from={lm_from}&to={lm_end}',
        f'/consumer/aggregates.php?premise_id=3&period=DAY&from={lm_from}&to={lm_end}',
        f'/consumer/aggregates.php?premise_id=3&period=MONTH&from={lm_from}&to={lm_end}',
        '/consumer/events.php?premise_id=3',
        f'/consumer/history.php?premise_id=4&from={LM}&to={LM}',
    ],
    'dso@mdms.cy': [f'/dso/reports.php?report={r}&transformer={t}' for r in ('voltage', 'unbalance', 'losses') for t in (1, 2)]
                   + [f'/dso/events.php?from={lm_from}&to={date.today()}'],
    'tso@mdms.cy': ['/tso/map-data.php', '/tso/map-data.php?lat=35.1856&lon=33.3823', '/tso/state.php?root=1&level=3'],
    'billing@eacsupply.cy': [f'/market/day-ahead.php?level={l}' for l in (1, 2, 3)] + ['/market/intraday.php?level=3',
                            '/market/api/portfolio.php', '/market/api/day-ahead.php?level=3', '/market/api/intraday.php?level=3'],
    'desk@flexpool.cy': ['/market/api/portfolio.php', '/market/day-ahead.php?level=3'],
    'officer1@mdms.cy': ['/staff/audit.php', '/staff/audit.php?page=2', '/staff/statistics.php'],
}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def fetch(op, path, data=None):
    req = urllib.request.Request(ORIGIN + path, data=urllib.parse.urlencode(data).encode() if data else None)
    t0 = time.perf_counter()
    try:
        r = op.open(req, timeout=120)
        body = r.read().decode('utf-8', 'replace')
        return r.status, r.headers, body, time.perf_counter() - t0
    except urllib.error.HTTPError as e:
        body = e.read().decode('utf-8', 'replace')
        return e.code, e.headers, body, time.perf_counter() - t0


def opener():
    jar = http.cookiejar.CookieJar()
    op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar), NoRedirect())
    form_pass = os.environ.get('DB_FORM_PASS', '')
    if form_pass:
        _, _, page, _ = fetch(op, P + '/connect.php')
        tok = re.search(r'name="_csrf" value="([^"]+)"', page).group(1)
        name = re.search(r'name="dbName" value="([^"]*)"', page).group(1)
        user = re.search(r'name="userName" value="([^"]*)"', page).group(1)
        st, _, _, t = fetch(op, P + '/connect.php', {'_csrf': tok, 'dbName': html.unescape(name),
                                                     'userName': html.unescape(user), 'pswd': form_pass})
        timings['(connect) POST /connect.php'].append((st, t, '-'))
        if st != 303:
            sys.exit(f'Connect page refused the database login (HTTP {st})')
    return op


def label(body):
    m = re.search(r'<h1[^>]*>([^<]*)</h1>', body)
    return html.unescape(m.group(1)).strip() if m else ''


timings = defaultdict(list)       # key "role url" -> [(status, seconds, title)]
for email in ACCOUNTS:
    op = opener()
    st, _, body, t = fetch(op, P + '/login.php')
    timings['(any) GET /login.php'].append((st, t, 'login page'))
    tok = re.search(r'name="_csrf" value="([^"]+)"', body).group(1)
    st, hd, _, t = fetch(op, P + '/login.php', {'_csrf': tok, 'email': email, 'password': PW})
    timings[f'{email} POST /login.php'].append((st, t, 'log in (sp_Login)'))
    if st != 303:
        print(f'{email}: login answered {st}', file=sys.stderr)
        continue
    seen, per_path, urls = set(), defaultdict(int), []
    queue = deque([P + '/home.php'] + [P + x for x in EXTRA.get(email, [])])
    while queue and len(urls) < MAX_PAGES:
        url = queue.popleft()
        if url in seen:
            continue
        seen.add(url)
        pth = urllib.parse.urlparse(url).path
        per_path[pth] += 1
        if per_path[pth] > 4 and url[len(P):] not in EXTRA.get(email, []):
            continue
        st, hd, body, t = fetch(op, url)
        if st in (301, 302, 303, 307, 308):
            continue
        urls.append(url)
        timings[f'{email} GET {url[len(P):]}'].append((st, t, label(body) if 'html' in (hd.get('Content-Type') or '') else hd.get('Content-Type', '')))
        if 'html' not in (hd.get('Content-Type') or ''):
            continue
        for kind, raw in ATTR.findall(body):
            value = html.unescape(raw)
            pu = urllib.parse.urlparse(value)
            if kind == 'href' and value.startswith(P + '/') and not pu.path.endswith('/logout.php') \
                    and not pu.path.startswith(P + '/assets/'):
                queue.append(pu.path + ('?' + pu.query if pu.query else ''))
    for _ in range(REPEATS - 1):                     # repeat every URL of this role
        for url in urls:
            st, hd, body, t = fetch(op, url)
            timings[f'{email} GET {url[len(P):]}'].append((st, t, ''))
    print(f'{email:24s} {len(urls)} URLs x {REPEATS}', flush=True)

rows = []
for key, vals in timings.items():
    ts = [v[1] for v in vals]
    rows.append({'request': key, 'title': next((v[2] for v in vals if v[2]), ''), 'status': '/'.join(sorted({str(v[0]) for v in vals})),
                 'n': len(ts), 'min_s': f'{min(ts):.3f}', 'median_s': f'{statistics.median(ts):.3f}', 'max_s': f'{max(ts):.3f}'})
rows.sort(key=lambda r: -float(r['max_s']))
with open(OUT, 'w', newline='', encoding='utf-8') as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0]))
    w.writeheader()
    w.writerows(rows)
allmax = [float(r['max_s']) for r in rows]
print(f'{len(rows)} distinct requests, {sum(r["n"] for r in rows)} timed; max {max(allmax):.3f} s; '
      f'over 2 s: {sum(x > 2 for x in allmax)}; over 1 s: {sum(x > 1 for x in allmax)}')
for r in rows[:15]:
    print(f'{r["max_s"]:>7} max {r["median_s"]:>7} med  {r["status"]:>7}  {r["request"]}  [{r["title"]}]')
