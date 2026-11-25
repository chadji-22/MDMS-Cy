#!/usr/bin/env bash
# C6 on the course server SQL2025: build_all.sql x2, all SQL tests, a final clean build, lab tables checked unchanged.
# Run from the repo root, on the UCY VPN. The password is read from the user environment variable SQLCMDPASSWORD.
# Stops at the first failure. build_all.sql is re-runnable, so a failed run is repaired by running it again.
set -u -o pipefail
E=evidence/C6-sql2025
fail0() { echo "STOPPED: $1"; exit 1; }
# the code that runs must be the tested, committed code with the scoped drop (lab FKs stay)
[ -f build_all.sql ] || fail0 "not in the repo root (the :r paths are relative)"
git diff --quiet HEAD -- '*.sql' || fail0 "uncommitted SQL changes"
grep -q 'DECLARE @mdms TABLE' create.sql && grep -q 'DECLARE @mdms TABLE' drop.sql || fail0 "scoped drop missing in create.sql / drop.sql"
echo "code under test: $(git rev-parse --short HEAD) on $(git branch --show-current)" | tee $E/commit.txt
# note: the 8 SSMS diagram helpers (sp_creatediagram, ..., fn_diagramobjects) belong to the lab DB and are left alone,
# so the build summary may count 125 procedures instead of 118
export SQLCMDPASSWORD="$(powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable('SQLCMDPASSWORD','User')" | tr -d '\r\n')"
Q() { /c/Users/ioann/tools/sqlcmd/sqlcmd.exe -S 'mssql.cs.ucy.ac.cy\SQL2025' -U ichara09 -d ichara09 -C -I -b -W -l 30 "$@"; }
SPACE="SET NOCOUNT ON; SELECT CAST(FILEPROPERTY('ichara09_Data','SpaceUsed')*8/1024.0 AS decimal(9,2))"
step() { echo "$(date +%H:%M:%S) $1"; }
fail() { step "STOPPED: $1"; exit 1; }

# 0. right server and database, nobody else's object touched yet
Q -h -1 -Q "IF @@SERVERNAME <> N'ntheva\SQL2025' OR DB_NAME() <> N'ichara09' THROW 50000, 'Wrong server or database', 1; SELECT 'target ok: '+@@SERVERNAME+' / '+DB_NAME()" || fail "guard"
Q -h -1 -i $E/lab_inventory.sql | grep -E '^(TABLE|FK)\|' > $E/lab_inventory_start.txt
diff -q --strip-trailing-cr $E/lab_inventory_before_25-11.txt $E/lab_inventory_start.txt >/dev/null || fail "lab tables changed since 25/11 inventory (see lab_inventory_start.txt)"
step "lab inventory unchanged; data used $(Q -h -1 -Q "$SPACE" | head -1) MB"
Q -Q "CHECKPOINT" > /dev/null || fail "CHECKPOINT"

# 1-2. build twice
for n in 1 2; do
  Q -i build_all.sql > $E/build$n.txt 2>&1 || fail "build $n (see $E/build$n.txt)"
  step "build $n OK: $(tail -9 $E/build$n.txt | tr '\n' ' ' | grep -oE 'tables [0-9]+|triggers [0-9]+|procedures [0-9]+' | tr '\n' ' ')data $(Q -h -1 -Q "$SPACE" | head -1) MB"
done

# 3. tests
Q -i tests.sql > $E/tests.txt 2>&1 || fail "tests.sql"
step "$(tail -1 $E/tests.txt)"
total=0
for f in seed_grid seed_telemetry_demo test_telemetry_parsing test_telemetry_ingest test_telemetry_storage test_vee_range test_vee_delta test_vee_edit test_vee_spike_preview; do
  Q -i sql/$f.sql > $E/sql_$f.txt 2>&1 || fail "sql/$f.sql"
  total=$((total + $(grep -oE '[0-9]+ tests, 0 not passed' $E/sql_$f.txt | grep -oE '^[0-9]+' || echo 0)))
done
step "telemetry/VEE: $total tests passed (expect 26)"
Q -i select.sql > $E/select.txt 2>&1 || fail "select.sql"
step "select.sql OK, use cases: $(grep -oE 'UC-[0-9]+' $E/select.txt | sort -u | wc -l); data $(Q -h -1 -Q "$SPACE" | head -1) MB"

# 4. final clean build: the database is left with the import.sql demo data only
Q -i build_all.sql > $E/build_final.txt 2>&1 || fail "final build"
step "final build OK; data $(Q -h -1 -Q "$SPACE" | head -1) MB"

# 5. lab tables unchanged, Query Store still off
Q -h -1 -i $E/lab_inventory.sql | grep -E '^(TABLE|FK)\|' > $E/lab_inventory_after.txt
diff -q --strip-trailing-cr $E/lab_inventory_before_25-11.txt $E/lab_inventory_after.txt >/dev/null && step "lab inventory identical after the run (25 tables, 21 FKs)" || fail "lab inventory differs (see lab_inventory_after.txt)"
step "query store: $(Q -h -1 -Q 'SET NOCOUNT ON; SELECT actual_state_desc FROM sys.database_query_store_options' | head -1)"
step "ALL DONE"
