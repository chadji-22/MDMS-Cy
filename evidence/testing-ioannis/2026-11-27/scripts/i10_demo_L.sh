#!/usr/bin/env bash
# I-10 end to end on L, on a premise WITHOUT a threshold and without any THRESHOLD_EXCEEDED event (premise 2 of consumer1):
# set the threshold on the page -> the officers' threshold check (the scheduled job; SQL only, L only) for last month ->
# a new THRESHOLD_EXCEEDED event + NOTIFICATION rows SIMULATED (B11) -> the consumer sees both. Then the threshold is
# removed again on the page (the event and notifications stay, as they would in production).
# Usage (repository root): SQLCMDPASSWORD=<sa> BASE_URL=http://127.0.0.1:8081 SQLCMD=<sqlcmd> bash <this file> [premise] [meter]
BASE="${BASE_URL:?}"; PW='Passw0rd!23'; PREM="${1:-2}"; MET="${2:-2}"
JAR="$(mktemp)"; trap 'rm -f "$JAR"' EXIT
. sources/tests/connect_lib.sh
pass=0; fail=0
check() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1  ${3:-}"; fail=$((fail+1)); fi; }
token() { curl -s -b "$JAR" -c "$JAR" "$BASE${1:-/login.php}" | sed -n 's/.*name="_csrf" value="\([^"]*\)".*/\1/p' | head -1; }
body()  { curl -s -b "$JAR" -c "$JAR" "$@"; }
post()  { local page="$1"; shift; local t; t="$(token "$page")"; curl -s -b "$JAR" -c "$JAR" -L --data-urlencode "_csrf=$t" "$@" "$BASE$page"; }
okmsg() { sed -n 's/.*class="flash ok" role="status">\([^<]*\)<.*/\1/p' | head -1; }
alert() { sed -n 's/.*role="alert">\([^<]*\)<.*/\1/p' | head -1; }
sql()   { "$SQLCMD" -S 127.0.0.1,11433 -U sa -d mdms2 -C -I -b -W -h -1 -Q "SET NOCOUNT ON; $1" 2>&1 | tr -d '\r' | grep -v '^Warning: Null value'; }
LAST_MONTH_END=$(date -u -d "$(date -u +%Y-%m-01) -1 day" +%Y-%m-%d)
echo "# premise $PREM / meter $MET, check as of $LAST_MONTH_END, $(date -u +%FT%TZ)"

echo "before: threshold $(sql "SELECT ISNULL(CAST(monthly_threshold_kwh AS varchar(20)),'NULL') FROM dbo.PREMISE WHERE premise_id=$PREM");" \
     "THRESHOLD_EXCEEDED events of meter $MET: $(sql "SELECT COUNT(*) FROM dbo.EVENT WHERE meter_id=$MET AND event_type='THRESHOLD_EXCEEDED'");" \
     "final DAY 1.8.0 total of ${LAST_MONTH_END:0:7}: $(sql "SELECT SUM(value) FROM dbo.AGGREGATE WHERE meter_id=$MET AND period_type='DAY' AND obis_code='1.8.0' AND is_final=1 AND period_start >= DATEFROMPARTS(${LAST_MONTH_END:0:4},${LAST_MONTH_END:5:2},1) AND period_start <= '$LAST_MONTH_END'") kWh"
maxev=$(sql "SELECT ISNULL(MAX(event_id),0) FROM dbo.EVENT")

: > "$JAR"; dbconnect; t="$(token)"
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -c "$JAR" --data-urlencode "_csrf=$t" --data-urlencode "email=consumer1@example.cy" --data-urlencode "password=$PW" "$BASE/login.php")
check "consumer1 logs in" '[ "$code" = 303 ]' "got $code"
out=$(post /consumer/events.php -d "action=threshold&premise_id=$PREM&threshold_kwh=10")
check "I-10 set the threshold of premise $PREM to 10 kWh on the page" 'echo "$out" | okmsg | grep -q "Threshold saved: 10"' "$(echo "$out" | alert)"
check "I-10 saving the threshold alone raises no event (by design: TR21 on new final totals, or the officers' check)" '[ "$(sql "SELECT COUNT(*) FROM dbo.EVENT WHERE meter_id=$MET AND event_type='"'"'THRESHOLD_EXCEEDED'"'"' AND event_id > $maxev")" = 0 ]'

echo "officers' threshold check as officer1 for $LAST_MONTH_END (as_of, premises_checked, alerts_raised):"
res=$(sql "DECLARE @o INT=(SELECT user_id FROM dbo.USER_ACCOUNT WHERE email='officer1@mdms.cy'); EXEC dbo.sp_CheckConsumptionThresholds @o, '$LAST_MONTH_END';"); echo "$res"
ev=$(sql "SELECT TOP 1 CONCAT(event_id,' | ',event_timestamp,' | ',description) FROM dbo.EVENT WHERE meter_id=$MET AND event_type='THRESHOLD_EXCEEDED' AND event_id > $maxev ORDER BY event_id DESC")
echo "new event: $ev"; eid=${ev%% *}
check "I-10 a new THRESHOLD_EXCEEDED event for meter $MET" '[ -n "$ev" ] && echo "$res" | grep -qE " 1$"' "$res"
nt=$(sql "SELECT CONCAT(channel,'=',status,' to ',CASE WHEN recipient IS NULL THEN 'none' ELSE 'the profile address' END) FROM dbo.NOTIFICATION WHERE event_id=${eid:-0} ORDER BY channel" | tr '\n' ';')
echo "NOTIFICATION rows of event $eid: $nt"
check "I-10 B11: EMAIL and SMS notifications recorded as SIMULATED (nothing SENT)" 'echo "$nt" | grep -q "EMAIL=SIMULATED" && echo "$nt" | grep -q "SMS=SIMULATED" && ! echo "$nt" | grep -q "=SENT"'
out=$(body "$BASE/consumer/events.php?premise_id=$PREM")
check "I-10 the events page of premise $PREM shows the new event and its SIMULATED notifications" 'echo "$out" | grep -q "above the threshold of 10" && echo "$out" | grep -c "SIMULATED" | grep -qv "^0$"'
out=$(post /consumer/events.php -d "action=threshold&premise_id=$PREM&clear=1")
check "cleanup: threshold of premise $PREM removed again" 'echo "$out" | okmsg | grep -q "Threshold removed"' "$(echo "$out" | alert)"
echo; echo "i10_demo_L.sh: $pass passed, $fail failed"; [ "$fail" -eq 0 ]
