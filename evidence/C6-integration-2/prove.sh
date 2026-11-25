#!/usr/bin/env bash
# C6 proof of ioannis/integration-2 (Kostis 68a26f9 + ioannis/C6-log-cap) on the local SQL Server 2022 container.
# Run from the repo root. Needs the containers mdms-sql and mdms-web-local (see evidence/C6-integration/README.md).
# Passwords: the local sa and web-login passwords are read from files outside the repo (SA_FILE, WEB_FILE).
set -u
E=evidence/C6-integration-2
DB=mdms2
export SQLCMDPASSWORD="$(cat "$SA_FILE")"; WEBPW="$(cat "$WEB_FILE")"
L="/c/Users/ioann/tools/sqlcmd/sqlcmd.exe -S 127.0.0.1,11433 -U sa -C -I -W"
step() { echo "$(date +%H:%M:%S) $1"; }
echo "code under test: $(git rev-parse --short HEAD) on $(git branch --show-current)" | tee $E/commit.txt

# SQL: fresh database, build x2, all SQL tests
$L -b -Q "IF DB_ID('$DB') IS NOT NULL DROP DATABASE $DB; CREATE DATABASE $DB COLLATE SQL_Latin1_General_CP1_CI_AS; ALTER DATABASE $DB SET RECOVERY SIMPLE; ALTER DATABASE $DB SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE" >/dev/null
for n in 1 2; do timeout 400 $L -b -d $DB -i build_all.sql > $E/build$n.txt 2>&1 </dev/null; step "build $n exit=$? $(tail -9 $E/build$n.txt | tr '\n' ' ' | grep -oE 'tables [0-9]+|triggers [0-9]+|procedures [0-9]+|indexes[^0-9]*[0-9]+' | tr '\n' ' ')"; done
timeout 400 $L -b -d $DB -i tests.sql > $E/tests.txt 2>&1 </dev/null; step "$(tail -1 $E/tests.txt)"
t=0; bad=0
for f in seed_grid seed_telemetry_demo test_telemetry_parsing test_telemetry_ingest test_telemetry_storage test_vee_range test_vee_delta test_vee_edit test_vee_spike_preview; do
  timeout 200 $L -b -d $DB -i sql/$f.sql > $E/sql_$f.txt 2>&1 </dev/null || bad=$((bad+1))
  t=$((t + $(grep -oE '[0-9]+ tests, 0 not passed' $E/sql_$f.txt | grep -oE '^[0-9]+' || echo 0))); done
step "telemetry/VEE: $t passed (expect 26), files failed: $bad"
timeout 300 $L -b -d $DB -i select.sql > $E/select.txt 2>&1 </dev/null; step "select.sql exit=$? use cases $(grep -oE 'UC-[0-9]+' $E/select.txt | sort -u | wc -l)"

# web: point the web container at this database (login that may only impersonate mdms_php)
$L -Q "IF SUSER_ID('mdms_web') IS NULL CREATE LOGIN mdms_web WITH PASSWORD='$WEBPW', CHECK_POLICY=OFF" >/dev/null
$L -b -d $DB -Q "CREATE USER mdms_web FOR LOGIN mdms_web; GRANT IMPERSONATE ON USER::mdms_php TO mdms_web;" >/dev/null
podman rm -f mdms-web-local >/dev/null 2>&1
podman run -d --name mdms-web-local --network mdms-net -p 127.0.0.1:8081:80 -v "$(pwd -W)/sources:/var/www/html" \
  -e DB_HOST=mdms-sql -e DB_NAME=$DB -e DB_USER=mdms_web -e DB_PASS -e DB_RUN_AS=mdms_php -e APP_DEBUG=0 localhost/mdms-php-dev:latest >/dev/null
sleep 6
export BASE_URL=http://127.0.0.1:8081
c() { echo "PASS=$(grep -c '^PASS' $1) FAIL=$(grep -c '^FAIL' $1)"; }
bash sources/tests/smoke.sh > $E/web_smoke.txt 2>&1; step "smoke: $(c $E/web_smoke.txt)"
WRITE=1 bash sources/tests/consumer_pages.sh > $E/web_consumer_pages.txt 2>&1; step "consumer_pages WRITE=1: $(c $E/web_consumer_pages.txt)"
bash sources/tests/accounts.sh > $E/web_accounts.txt 2>&1; step "accounts: $(c $E/web_accounts.txt)"
bash sources/tests/market_dso_tso.sh > $E/web_market.txt 2>&1; step "market read-only: $(c $E/web_market.txt)"
WRITE=1 bash sources/tests/market_dso_tso.sh > $E/web_market_write.txt 2>&1; step "market WRITE=1: $(c $E/web_market_write.txt)"
for t in errors_test db_integration; do MSYS_NO_PATHCONV=1 podman exec mdms-web-local php /var/www/html/tests/$t.php > $E/php_$t.txt 2>&1; step "$t exit=$?"; done
MSYS_NO_PATHCONV=1 podman run --rm -v "$(pwd -W):/repo:ro" localhost/mdms-php-dev:latest php /repo/sources/tests/audit_pages.php > $E/php_audit_pages.txt 2>&1; step "audit_pages exit=$? $(grep -E 'procedure calls checked' $E/php_audit_pages.txt)"

# role crawl of every page + detail pages with real ids (accounts: one approved account per role)
$L -h -1 -s '|' -d $DB -Q "SET NOCOUNT ON; SELECT role_code, MIN(email) FROM USER_ACCOUNT WHERE approval_status='APPROVED' AND is_active=1 AND anonymized_at IS NULL AND email NOT LIKE 'nobody%' AND email NOT LIKE '%test%' GROUP BY role_code" \
  | python -c "import sys,json; json.dump({l.split('|')[0]:l.split('|')[1].strip() for l in sys.stdin if '|' in l}, open(sys.argv[1],'w'))" "$(cygpath -m "$ACC_FILE")"
python evidence/C6-integration/crawl_pages.py "$(cygpath -m "$ACC_FILE")" > $E/pages.md; step "page crawl: $(sed -n 3p $E/pages.md)"
( cd evidence/C6-integration && python crawl_detail.py "$(cygpath -m "$ACC_FILE")" ) > $E/detail_pages.md; step "detail pages: $(tail -1 $E/detail_pages.md)"
step "app error log [MDMS ref] lines: $(podman logs mdms-web-local 2>&1 | grep -c '\[MDMS ')"
step "DONE"
