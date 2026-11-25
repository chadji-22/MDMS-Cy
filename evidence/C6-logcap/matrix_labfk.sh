#!/usr/bin/env bash
# Test matrix for the log-cap change. Run from the repo root. Local SQL Server only.
S=/c/Users/ioann/AppData/Local/Temp/claude/01188d643f296ad0/173627e6-c0e9-4796-a80b-9b4c09e01900/scratchpad
OUT=$S/matrix2; mkdir -p $OUT
export SQLCMDPASSWORD="$(cat $S/sa.pw)"
L="/c/Users/ioann/tools/sqlcmd/sqlcmd.exe -S 127.0.0.1,11433 -U sa -C -I -W"
SNAP="SET NOCOUNT ON; SELECT STRING_AGG(CAST(t.name+'='+CAST(p.rows AS varchar(12)) AS varchar(60)), ' ') WITHIN GROUP (ORDER BY t.name) FROM sys.tables t JOIN sys.partitions p ON p.object_id=t.object_id AND p.index_id IN (0,1) WHERE t.name NOT IN ('EMPLOYEE','DEPARTMENT','L8_ORDERS'); SELECT 'status:'+STRING_AGG(CAST(status+'='+CAST(c AS varchar(10)) AS varchar(40)),' ') WITHIN GROUP (ORDER BY status) FROM (SELECT status, COUNT(*) c FROM METER_READING GROUP BY status) x; SELECT 'audit:'+STRING_AGG(CAST(action+'='+CAST(c AS varchar(10)) AS varchar(60)),' ') WITHIN GROUP (ORDER BY action) FROM (SELECT action, COUNT(*) c FROM AUDIT_LOG GROUP BY action) y"
USE="SET NOCOUNT ON; SELECT 'data '+CAST(CAST(FILEPROPERTY('d','SpaceUsed')*8/1024.0 AS decimal(9,2)) AS varchar)+' MB'"

mkdb() { # name logMB (0 = uncapped)
  if [ "$2" = 0 ]; then $L -b -Q "IF DB_ID('$1') IS NOT NULL DROP DATABASE $1; CREATE DATABASE $1 ON (NAME=d, FILENAME='/var/opt/mssql/data/$1.mdf') LOG ON (NAME=l, FILENAME='/var/opt/mssql/data/$1.ldf') COLLATE SQL_Latin1_General_CP1_CI_AS"
  else $L -b -Q "IF DB_ID('$1') IS NOT NULL DROP DATABASE $1; CREATE DATABASE $1 ON (NAME=d, FILENAME='/var/opt/mssql/data/$1.mdf', SIZE=27MB, MAXSIZE=27MB, FILEGROWTH=0) LOG ON (NAME=l, FILENAME='/var/opt/mssql/data/$1.ldf', SIZE=$2MB, MAXSIZE=$2MB, FILEGROWTH=0) COLLATE SQL_Latin1_General_CP1_CI_AS"; fi
  $L -b -Q "ALTER DATABASE $1 SET RECOVERY SIMPLE; ALTER DATABASE $1 SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE"
  $L -b -d $1 -Q "CREATE TABLE dbo.DEPARTMENT (dno INT PRIMARY KEY, mgr INT NULL); CREATE TABLE dbo.EMPLOYEE (ssn INT PRIMARY KEY, dno INT NOT NULL CONSTRAINT FK_EMP_DEPT REFERENCES dbo.DEPARTMENT(dno)); ALTER TABLE dbo.DEPARTMENT ADD CONSTRAINT FK_DEPT_MGR FOREIGN KEY (mgr) REFERENCES dbo.EMPLOYEE(ssn); CREATE TABLE dbo.L8_ORDERS (id INT PRIMARY KEY, emp INT CONSTRAINT FK_L8_EMP REFERENCES dbo.EMPLOYEE(ssn)); INSERT dbo.DEPARTMENT VALUES (1,NULL); INSERT dbo.EMPLOYEE VALUES (10,1); INSERT dbo.L8_ORDERS VALUES (1,10)"
}
build() { # db tag
  timeout 400 $L -b -d $1 -i build_all.sql > $OUT/$1_$2.txt 2>&1 </dev/null; local rc=$?
  $L -h -1 -d $1 -Q "$SNAP" > $OUT/snap_$1_$2.txt
  local cmpres; cmp -s $OUT/snap_base.txt $OUT/snap_$1_$2.txt && cmpres=SAME || cmpres=DIFF
  echo "$1 $2: exit=$rc Msg=$(grep -cE '^Msg' $OUT/$1_$2.txt) logfull=$(grep -c 'transaction log' $OUT/$1_$2.txt) ingest_err=$(grep -cE '^[0-9]+ [0-9]+ [0-9]+ [0-9]+ [0-9]+ [1-9][0-9]* [0-9]+$' $OUT/$1_$2.txt) vs-baseline=$cmpres $($L -h -1 -d $1 -Q "$USE" | head -1) $(tail -3 $OUT/$1_$2.txt | grep -o 'procedures [0-9]*')"
}
tests() { # db
  timeout 400 $L -b -d $1 -i tests.sql > $OUT/$1_tests.txt 2>&1 </dev/null; echo "$1 tests.sql: $(tail -1 $OUT/$1_tests.txt)"
  local t=0 bad=0
  for f in seed_grid seed_telemetry_demo test_telemetry_parsing test_telemetry_ingest test_telemetry_storage test_vee_range test_vee_delta test_vee_edit test_vee_spike_preview; do
    timeout 200 $L -b -d $1 -i sql/$f.sql > $OUT/$1_$f.txt 2>&1 </dev/null || bad=$((bad+1))
    t=$((t + $(grep -oE '[0-9]+ tests, 0 not passed' $OUT/$1_$f.txt | grep -oE '^[0-9]+' || echo 0))); done
  echo "$1 telemetry/VEE: files failed=$bad, tests passed=$t (expect 26)"
  timeout 300 $L -b -d $1 -i select.sql > $OUT/$1_select.txt 2>&1 </dev/null; echo "$1 select.sql exit=$? UC=$(grep -oE 'UC-[0-9]+' $OUT/$1_select.txt | sort -u | wc -l)"
}
populate() { # db: C1 large set on top, like the real course DB today
  timeout 400 $L -b -d $1 -i evidence/C1/c1_large_set.sql > $OUT/$1_c1.txt 2>&1 </dev/null; echo "$1 C1 large set exit=$? readings=$($L -h -1 -d $1 -Q 'SET NOCOUNT ON; SELECT COUNT(*) FROM METER_READING' | head -1) $($L -h -1 -d $1 -Q "$USE" | head -1)"
}

# baseline: this branch's code, uncapped, fresh
mkdb base 0; timeout 400 $L -b -d base -i build_all.sql > $OUT/base.txt 2>&1 </dev/null; echo "baseline exit=$?"; $L -h -1 -d base -Q "$SNAP" > $OUT/snap_base.txt
for cfg in "c20 20" "cun 0"; do set -- $cfg; echo "=== $1 (log ${2} MB, 0=uncapped)"
  mkdb $1 $2
  build $1 b1; populate $1; build $1 b2_after_populated; build $1 b3
  tests $1; build $1 b4_final
  echo "$1 lab: $($L -h -1 -d $1 -i "$S/labcheck.sql" 2>&1 | head -1)  (expect: 3 lab FKs, 3 rows)"
done
