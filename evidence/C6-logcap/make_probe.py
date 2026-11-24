"""Builds a scratch copy of import.sql (and build_all.sql pointing at it) with a log probe around every
top-level EXEC [dbo].[sp_...] line. The repo files are not changed."""
import re, sys
repo, out = sys.argv[1], sys.argv[2]
src = open(repo + '/import.sql', encoding='utf-8').read().split('\n')


def probe(tag):
    return ("SELECT CONCAT('PROBE|" + tag + "|file=',(SELECT size*8/1024 FROM sys.database_files WHERE type=1),"
            "'|used=',(SELECT CAST(used_log_space_in_bytes/1048576.0 AS decimal(9,2)) FROM sys.dm_db_log_space_usage)) AS p;")


lines = []
for i, line in enumerate(src, 1):
    if re.match(r'^EXEC \[dbo\]\.\[sp_', line) and line.rstrip().endswith(';'):
        name = re.search(r'\[(sp_\w+)\]', line).group(1)
        lines += ["CHECKPOINT;", probe(f"before L{i} {name}"), line, probe(f"after L{i} {name}")]
    else:
        lines.append(line)
open(out + '/import_probe.sql', 'w', encoding='utf-8').write('\n'.join(lines))
b = open(repo + '/build_all.sql', encoding='utf-8').read()
b = b.replace(':r create.sql', "SELECT CONCAT('PROBE|before create.sql|file=',(SELECT size*8/1024 FROM sys.database_files WHERE type=1),'|used=',(SELECT CAST(used_log_space_in_bytes/1048576.0 AS decimal(9,2)) FROM sys.dm_db_log_space_usage)) AS p;\nGO\n:r create.sql\nSELECT CONCAT('PROBE|after create.sql|file=',(SELECT size*8/1024 FROM sys.database_files WHERE type=1),'|used=',(SELECT CAST(used_log_space_in_bytes/1048576.0 AS decimal(9,2)) FROM sys.dm_db_log_space_usage)) AS p;\nGO")
b = b.replace(':r import.sql', ':r ' + out + '/import_probe.sql')
open(out + '/build_probe.sql', 'w', encoding='utf-8').write(b)
print(sum(1 for l in lines if 'PROBE|' in l), 'probes written')
