"""Ranks the statements of a probe run by the log they needed (file growth and used-space delta)."""
import sys
rows = [l.strip().split('|') for l in open(sys.argv[1], encoding='utf-8', errors='replace') if l.startswith('PROBE|')]
prev, res = None, []
for r in rows:
    tag, f, u = r[1], int(r[2].split('=')[1]), float(r[3].split('=')[1])
    if tag.startswith('after') and prev:
        res.append((f - prev[0], u - prev[1], tag[6:]))
    if tag.startswith('before'):
        prev = (f, u)
print('final log file size:', rows[-1][2] if rows else '?', '| probes read:', len(rows))
print('file growth MB | used delta MB | statement')
for g, d, t in sorted(res, key=lambda x: (x[0], x[1]), reverse=True)[:12]:
    print(f'{g:6d} {d:8.2f}   {t}')
