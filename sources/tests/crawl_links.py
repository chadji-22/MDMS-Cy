"""Link crawl: logs in as every demo role, opens every page reachable by links and checks every URL.

usage: [DB_FORM_PASS=...] python tests/crawl_links.py <BASE_URL>      e.g. http://localhost:8080 or .../~login/mdms
Checks, per role: login redirect, every page reachable by links (GET only, logout skipped), every href/action/src,
every Location header. A URL path must start with <base>/ and never contain the base twice; pages must not answer
404/500 or show "Service problem". Uses only correct passwords (no throttle counts).
"""
import html
import http.cookiejar
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import deque, defaultdict

BASE_URL = sys.argv[1].rstrip('/')
U = urllib.parse.urlparse(BASE_URL)
ORIGIN = f'{U.scheme}://{U.netloc}'
P = U.path.rstrip('/')
PW = 'Passw0rd!23'
ACCOUNTS = ['consumer1@example.cy', 'tech1@mdms.cy', 'officer1@mdms.cy', 'admin@mdms.cy', 'dso@mdms.cy',
            'tso@mdms.cy', 'billing@eacsupply.cy', 'desk@flexpool.cy']
ATTR = re.compile(r'\b(href|action|src)="([^"]*)"')
MAX_PAGES = 160


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def opener():
    jar = http.cookiejar.CookieJar()
    op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar), NoRedirect())
    form_pass = __import__('os').environ.get('DB_FORM_PASS', '')
    if form_pass:                                  # Connect page (no DB_PASS on the server): log the session in first
        _, _, page = fetch(op, P + '/connect.php')
        tok = re.search(r'name="_csrf" value="([^"]+)"', page).group(1)
        name = re.search(r'name="dbName" value="([^"]*)"', page).group(1)
        user = re.search(r'name="userName" value="([^"]*)"', page).group(1)
        st, hd, _ = fetch(op, P + '/connect.php', {'_csrf': tok, 'dbName': html.unescape(name),
                                                   'userName': html.unescape(user), 'pswd': form_pass})
        if st != 303:
            sys.exit(f'Connect page refused the database login (HTTP {st})')
    return op


def fetch(op, path, data=None):
    req = urllib.request.Request(ORIGIN + path, data=urllib.parse.urlencode(data).encode() if data else None)
    try:
        r = op.open(req, timeout=60)
        return r.status, r.headers, r.read().decode('utf-8', 'replace')
    except urllib.error.HTTPError as e:
        return e.code, e.headers, e.read().decode('utf-8', 'replace')


def path_ok(p):
    """A same-site URL path must be inside the application folder, with the base exactly once."""
    if P and P + P in p:
        return False
    return p.startswith(P + '/')


problems = []
notes = []          # to read, not failures: query-only links, pages that answer 404 with the application's own message
total_pages = 0
total_urls = 0
for email in ACCOUNTS:
    op = opener()
    st, _, body = fetch(op, P + '/login.php')
    m = re.search(r'name="_csrf" value="([^"]+)"', body)
    if st != 200 or not m:
        problems.append(f'{email}: login page {st}')
        continue
    st, hd, _ = fetch(op, P + '/login.php', {'_csrf': m.group(1), 'email': email, 'password': PW})
    loc = hd.get('Location', '')
    if st != 303 or not path_ok(urllib.parse.urlparse(loc).path):
        problems.append(f'{email}: login answered {st} Location={loc!r}')
        continue
    seen, per_path = set(), defaultdict(int)
    queue = deque([P + '/home.php'])
    pages = 0
    while queue and pages < MAX_PAGES:
        url = queue.popleft()
        if url in seen:
            continue
        seen.add(url)
        path_only = urllib.parse.urlparse(url).path
        per_path[path_only] += 1
        if per_path[path_only] > 4:            # pagers / filters: a few variants per page are enough
            continue
        st, hd, body = fetch(op, url)
        pages += 1
        if st in (301, 302, 303, 307, 308):
            loc = hd.get('Location', '')
            lp = urllib.parse.urlparse(urllib.parse.urljoin(ORIGIN + url, loc))
            if lp.netloc != U.netloc or not path_ok(lp.path):
                problems.append(f'{email}: {url} -> redirect outside the app: {loc!r}')
            elif lp.path.endswith('.php') or lp.path.endswith('/'):
                queue.append(lp.path + ('?' + lp.query if lp.query else ''))
            continue
        if st == 404 and 'MDMS-Cy' in body and 'Service problem' not in body:
            notes.append(f'{email}: {url} -> 404 with the application message (by design, e.g. a file not on this server)')
            continue
        if st >= 500 or st == 404 or 'Service problem' in body:
            problems.append(f'{email}: {url} -> HTTP {st}' + (' (Service problem)' if 'Service problem' in body else ''))
            continue
        if st == 403:
            problems.append(f'{email}: {url} -> 403 (a link the role cannot open)')
            continue
        if 'html' not in (hd.get('Content-Type') or ''):
            continue
        for kind, raw in ATTR.findall(body):
            value = html.unescape(raw)
            total_urls += 1
            if value == '' or value.startswith(('#', 'mailto:', 'data:', 'javascript:')):
                continue
            pu = urllib.parse.urlparse(value)
            if pu.scheme in ('http', 'https') and pu.netloc != U.netloc:
                continue                           # external (OpenStreetMap etc.)
            if not value.startswith('/') and not pu.scheme:
                notes.append(f'{email}: {url}: relative {kind}="{value}" (fine in any folder when it starts with ?)')
                continue
            if not path_ok(pu.path):
                problems.append(f'{email}: {url}: {kind}="{value}" is outside {P or "/"}')
                continue
            if kind == 'href' and not pu.path.endswith('/logout.php'):
                queue.append(pu.path + ('?' + pu.query if pu.query else ''))
            elif kind == 'src' and pu.path not in seen:
                seen.add(pu.path)
                s2, _, _ = fetch(op, pu.path)
                if s2 != 200:
                    problems.append(f'{email}: {url}: src {pu.path} -> HTTP {s2}')
    total_pages += pages
    print(f'{email:24s} pages fetched: {pages}')

# the map script's data URL (built in JavaScript from data-base)
op = opener()
_, _, body = fetch(op, P + '/login.php')
tok = re.search(r'name="_csrf" value="([^"]+)"', body).group(1)
fetch(op, P + '/login.php', {'_csrf': tok, 'email': 'tso@mdms.cy', 'password': PW})
_, _, mp = fetch(op, P + '/tso/map.php')
dm = re.search(r'data-base="([^"]*)"', mp)
base_js = html.unescape(dm.group(1)) if dm else None
st, hd, _ = fetch(op, (base_js or '') + '/tso/map-data.php')
print(f'map.php data-base={base_js!r}  ->  map-data.php HTTP {st} {hd.get("Content-Type")}')
if base_js != P or st != 200:
    problems.append(f'map: data-base={base_js!r}, map-data.php HTTP {st}')

print(f'\n{total_pages} pages, {total_urls} URLs checked, base path {P or "(root)"!r}')
print('\n'.join(problems) if problems else 'no problems')
if notes:
    print(f'notes ({len(notes)}, not failures):')
    print('\n'.join(sorted(set(n.split(': ', 1)[1] for n in notes))))
sys.exit(1 if problems else 0)
