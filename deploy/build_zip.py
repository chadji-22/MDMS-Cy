"""Build deploy/mdms-app.zip from sources/ (run from anywhere:  python deploy/build_zip.py).

The zip holds mdms/src, mdms/areas and mdms/public with Unix file modes. It never holds:
  - src/config.local.php  (settings stay on each server; install.sh creates them from config.ucy.sample.php)
  - var/                   (uploads stay on the server; an "unzip -o" must not reset that folder)
  - tests/, dev/           (not needed on the server)
"""
import hashlib
import os
import stat
import sys
import zipfile

repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = os.path.join(repo, 'sources')
out = os.path.join(repo, 'deploy', 'mdms-app.zip')

entries = []
for top in ('src', 'areas', 'public'):
    for root, dirs, files in os.walk(os.path.join(src, top)):
        dirs.sort()
        for f in sorted(files):
            rel = os.path.relpath(os.path.join(root, f), src).replace(os.sep, '/')
            if rel == 'src/config.local.php' or f.endswith(('.pyc', '.swp', '.log')):
                continue
            entries.append(rel)

with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for rel in entries:
        zi = zipfile.ZipInfo('mdms/' + rel, date_time=(2026, 1, 1, 0, 0, 0))   # fixed date: same code -> same zip
        zi.external_attr = (stat.S_IFREG | 0o644) << 16
        zi.compress_type = zipfile.ZIP_DEFLATED
        zi.create_system = 3                     # Unix, so unzip on Linux applies the modes
        with open(os.path.join(src, rel), 'rb') as fh:
            z.writestr(zi, fh.read())

names = zipfile.ZipFile(out).namelist()
bad = [n for n in names if n.endswith('config.local.php') or n.startswith(('mdms/var', 'mdms/tests', 'mdms/dev'))]
if bad:
    sys.exit(f'refusing: the zip contains {bad}')
digest = hashlib.sha256(open(out, 'rb').read()).hexdigest()
print(f'{len(names)} files -> {os.path.relpath(out, repo)}  ({os.path.getsize(out)} bytes, sha256 {digest[:16]}...)')
