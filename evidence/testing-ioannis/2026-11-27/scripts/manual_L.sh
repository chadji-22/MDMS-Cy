#!/usr/bin/env bash
# Ioannis's manual tests I-08..I-14 (TESTING_PLAN.md 4.1) scripted with curl against L (writes: local copy only).
# Usage (repo root): BASE_URL=http://127.0.0.1:8081 SQLCMD=<path to sqlcmd> bash manual_L.sh
# SQL checks use the sa login of the local container, password from SQLCMDPASSWORD in the environment (not printed).
BASE="${BASE_URL:?}"; PW='Passw0rd!23'
P=$(printf '%s' "$BASE" | sed -E 's#^https?://[^/]+##; s#/+$##')
JAR="$(mktemp)"; trap 'rm -f "$JAR"' EXIT
. sources/tests/connect_lib.sh
pass=0; fail=0
check() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1  ${3:-}"; fail=$((fail+1)); fi; }
token() { curl -s -b "$JAR" -c "$JAR" "$BASE${1:-/login.php}" | sed -n 's/.*name="_csrf" value="\([^"]*\)".*/\1/p' | head -1; }
body()  { curl -s -b "$JAR" -c "$JAR" "$@"; }
login() { : > "$JAR"; dbconnect; local t; t="$(token)"; curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -c "$JAR" \
            --data-urlencode "_csrf=$t" --data-urlencode "email=$1" --data-urlencode "password=$PW" "$BASE/login.php"; }
post()  { local page="$1"; shift; local t; t="$(token "$page")"; curl -s -b "$JAR" -c "$JAR" -L --data-urlencode "_csrf=$t" "$@" "$BASE$page"; }
alert() { sed -n 's/.*role="alert">\([^<]*\)<.*/\1/p' | head -1; }
okmsg() { sed -n 's/.*class="flash ok" role="status">\([^<]*\)<.*/\1/p' | head -1; }
sql()   { "$SQLCMD" -S 127.0.0.1,11433 -U sa -d mdms2 -C -I -b -W -h -1 -Q "SET NOCOUNT ON; $1" 2>&1 | tr -d '\r'; }
LAST_MONTH_FROM=$(date -u -d "$(date -u +%Y-%m-01) -1 month" +%Y-%m-%d); LAST_MONTH_END=$(date -u -d "$(date -u +%Y-%m-01) -1 day" +%Y-%m-%d)
LAST_MONTH=${LAST_MONTH_FROM:0:7}; D1=$(date -u -d "$LAST_MONTH_END -1 day" +%Y-%m-%d)
echo "# target $BASE; last month $LAST_MONTH; imported days $D1 and $LAST_MONTH_END; $(date -u +%FT%TZ)"

code=$(login consumer1@example.cy); check "consumer1 logs in" '[ "$code" = 303 ]' "got $code"

echo; echo "## I-11 Past data: buy access to an older month (premise 1, $LAST_MONTH)"
out=$(body "$BASE/consumer/readings.php?premise_id=1&from=$D1&to=$LAST_MONTH_END")
if echo "$out" | grep -q "not bought for this period"; then
  echo "before: readings of premise 1 for $D1..$LAST_MONTH_END -> '$(echo "$out" | alert)'"
  q=$(body "$BASE/consumer/history.php?premise_id=1&from=$LAST_MONTH&to=$LAST_MONTH"); echo "quote: $(echo "$q" | grep -o 'Buy access for[^<]*' | head -1)"
  out=$(post /consumer/history.php -d "premise_id=1&from=$LAST_MONTH&to=$LAST_MONTH&method=CARD")
  echo "flash: $(echo "$out" | okmsg)"
  check "I-11 buy $LAST_MONTH for premise 1: confirmed" 'echo "$out" | okmsg | grep -q "bought for"' "$(echo "$out" | alert)"
else
  echo "premise 1, $LAST_MONTH was already bought on this database (an earlier run): only the 'visible' check runs"
fi
out=$(body "$BASE/consumer/readings.php?premise_id=1&from=$D1&to=$LAST_MONTH_END")
check "I-11 the older readings are now visible (no 'not bought' message, slots listed)" '! echo "$out" | grep -q "not bought" && echo "$out" | grep -q "slots"' "$(echo "$out" | alert)"
echo "sql: access payments for meter 1 -> $(sql "SELECT CONCAT('payment ',payment_id,' ',access_from,'..',access_to,' ',amount,' EUR') FROM dbo.PAYMENT WHERE access_meter_id=1" | tr '\n' ' ')"

echo; echo "## I-08 My premises; Readings for a premise (consumer1)"
out=$(body "$BASE/consumer/")
check "I-08 My premises: Greek addresses intact (Λεωφ. Στροβόλου 101, Οδός Γρίβα Διγενή 12)" 'echo "$out" | grep -q "Λεωφ. Στροβόλου 101" && echo "$out" | grep -q "Οδός Γρίβα Διγενή 12" && echo "$out" | grep -q "Στρόβολος"'
out=$(body "$BASE/consumer/readings.php?premise_id=1&from=$D1&to=$LAST_MONTH_END")
echo "readings page: $(echo "$out" | grep -oE '[0-9]+ slots[^<]*' | head -1); headers: $(echo "$out" | grep -oE '<th[^>]*>[^<]*</th>' | sed 's/<[^>]*>//g' | tr '\n' '|')"
n1=$(echo "$out" | grep -o "$D1 [0-9][0-9]:[0-9][0-9]" | sort -u | wc -l); n2=$(echo "$out" | grep -o "$LAST_MONTH_END [0-9][0-9]:[0-9][0-9]" | sort -u | wc -l)
echo "distinct 15-minute slots shown: $D1 -> $n1, $LAST_MONTH_END -> $n2 (96 per day = every 15 minutes)"
check "I-08 readings of premise 1 (scheme NONE): 15-minute rows with the import 1.8.0 column" 'echo "$out" | grep -q "slots" && echo "$out" | grep -q "Import 1.8.0" && [ "$n1" -ge 90 ]'
echo "premise 1 is not a prosumer (scheme NONE), so the page shows no export column; import + export: consumer2 premise 3 below"
code=$(login consumer2@example.cy)
out=$(body "$BASE/consumer/readings.php?premise_id=3&from=$D1&to=$LAST_MONTH_END")
check "I-08 prosumer premise 3 (consumer2): import and export side by side" 'echo "$out" | grep -q "Import 1.8.0" && echo "$out" | grep -q "Export 2.8.0" && echo "$out" | grep -q "slots"' "$(echo "$out" | alert)"
code=$(login consumer1@example.cy)

echo; echo "## I-09 Totals: daily and monthly (premise 1)"
out=$(body "$BASE/consumer/aggregates.php?premise_id=1&period=DAY&from=$D1&to=$LAST_MONTH_END")
echo "daily: $(echo "$out" | grep -oE '<td[^>]*>[^<]*</td>' | sed 's/<[^>]*>//g' | head -8 | tr '\n' '|')"
check "I-09 daily totals of the two imported days" 'echo "$out" | grep -q "<td class=\"mono\">$D1</td>" && echo "$out" | grep -q "<td class=\"mono\">$LAST_MONTH_END</td>"' "$(echo "$out" | alert)"
out=$(body "$BASE/consumer/aggregates.php?premise_id=1&period=MONTH&from=$LAST_MONTH_FROM&to=$LAST_MONTH_END")
echo "monthly: $(echo "$out" | grep -oE '<td[^>]*>[^<]*</td>' | sed 's/<[^>]*>//g' | head -6 | tr '\n' '|')"
check "I-09 monthly total of premise 1 for $LAST_MONTH" 'echo "$out" | grep -q "<td class=\"mono\">$LAST_MONTH" && ! echo "$out" | grep -q "role=\"alert\""' "$(echo "$out" | alert)"

echo; echo "## I-10 Events and alerts: threshold of premise 1 = 10 kWh -> THRESHOLD_EXCEEDED, notification SIMULATED (B11)"
before=$(sql "SELECT COUNT(*) FROM dbo.EVENT WHERE meter_id=1 AND event_type='THRESHOLD_EXCEEDED'")
out=$(post /consumer/events.php -d "action=threshold&premise_id=1&threshold_kwh=10")
check "I-10 set the threshold to 10 kWh on the page" 'echo "$out" | okmsg | grep -q "Threshold saved: 10"' "$(echo "$out" | alert)"
echo "THRESHOLD_EXCEEDED events of meter 1 before the check: $before"
echo "the event is raised by TR21 (new final DAY totals) or by the officers' check; run the check as officer1 (SQL, L only):"
sql "DECLARE @o INT=(SELECT user_id FROM dbo.USER_ACCOUNT WHERE email='officer1@mdms.cy'); EXEC dbo.sp_CheckConsumptionThresholds @o;"
ev=$(sql "SELECT TOP 1 CONCAT(event_id,' ',event_timestamp,' ',description) FROM dbo.EVENT WHERE meter_id=1 AND event_type='THRESHOLD_EXCEEDED' ORDER BY event_id DESC")
echo "newest THRESHOLD_EXCEEDED of meter 1: $ev"
eid=${ev%% *}
nt=$(sql "SELECT CONCAT(channel,'=',status) FROM dbo.NOTIFICATION WHERE event_id=$eid ORDER BY channel" | tr '\n' ' ')
echo "NOTIFICATION rows of event $eid (read-only query): $nt"
after=$(sql "SELECT COUNT(*) FROM dbo.EVENT WHERE meter_id=1 AND event_type='THRESHOLD_EXCEEDED'")
echo "month-to-date 1.8.0 consumption of meter 1 (why the check may add nothing new): $(sql "SELECT ISNULL(SUM(delta_value),0) FROM dbo.METER_READING WHERE meter_id=1 AND obis_code='1.8.0' AND reading_timestamp >= DATEFROMPARTS(YEAR(SYSUTCDATETIME()),MONTH(SYSUTCDATETIME()),1)" | grep -v Warning) kWh"
check "I-10 a THRESHOLD_EXCEEDED event exists for premise 1 (one per month whose total is above 10 kWh)" '[ -n "$eid" ] && [ "$after" -ge 1 ]' "before $before after $after"
check "I-10 B11: its notifications are recorded with status SIMULATED (EMAIL and SMS, as consumer1 chose)" 'echo "$nt" | grep -q "EMAIL=SIMULATED" && echo "$nt" | grep -q "SMS=SIMULATED"'
out=$(body "$BASE/consumer/events.php?premise_id=1")
check "I-10 the events page shows the event to consumer1" 'echo "$out" | grep -q "THRESHOLD_EXCEEDED\|Threshold exceeded\|above the threshold"'
check "I-10 the events page lists the notifications as SIMULATED and says delivery is simulated" 'echo "$out" | grep -q "SIMULATED" && echo "$out" | grep -q "delivery is <strong>simulated</strong>"'

echo; echo "## I-12 Requests: submit a check request; open its History"
out=$(post /consumer/requests.php -d "premise_id=1&work_type=TECHNICAL_CHECK" --data-urlencode "description=I-12 test: please check the meter")
id=$(echo "$out" | sed -n 's/.*Request #\([0-9]*\) submitted.*/\1/p' | head -1)
echo "flash: $(echo "$out" | okmsg)"
check "I-12 check request submitted, its page shows state SUBMITTED" '[ -n "$id" ] && echo "$out" | grep -q "SUBMITTED"' "$(echo "$out" | alert)"
out=$(body "$BASE/consumer/request.php?id=$id")
check "I-12 History of request #$id is listed" 'echo "$out" | grep -qi "history" && echo "$out" | grep -q "SUBMITTED"'
out=$(body "$BASE/consumer/requests.php"); check "I-12 the request is in My requests" 'echo "$out" | grep -q ">$id<"'
out=$(post /consumer/request.php -d "id=$id" --data-urlencode "reason=I-12 test cleanup")
check "I-12 cleanup: cancelled again (history SUBMITTED -> CANCELLED)" 'echo "$out" | grep -q "CANCELLED"' "$(echo "$out" | alert)"

echo; echo "## I-13 Bills and payments: pay part of an open bill"
out=$(body "$BASE/consumer/bills.php")
bill=$(echo "$out" | sed -n 's/.*name="bill_id" value="\([0-9]*\)".*/\1/p' | head -1)
row() { echo "$1" | tr -d '\n' | sed 's#</tr>#</tr>\n#g' | grep "<td>#$bill</td>" | sed 's/<[^>]*>/ /g' | tr -s ' '; }
echo "before: $(row "$out")"
out=$(post /consumer/bills.php -d "action=pay_bill&bill_id=$bill&amount=1.00&method=CARD")
echo "flash: $(echo "$out" | okmsg)"; echo "after:  $(row "$out")"
check "I-13 part payment of 1.00 on open bill #$bill recorded (PARTIALLY_PAID, left updated)" '[ -n "$bill" ] && echo "$out" | okmsg | grep -q "Payment #.*Bill #$bill is now PARTIALLY_PAID"' "$(echo "$out" | alert)"
echo "sql: $(sql "SELECT CONCAT('bill ',b.bill_id,' amount ',b.amount,' paid ',ISNULL(SUM(p.amount),0),' status ',b.status) FROM dbo.BILL b LEFT JOIN dbo.PAYMENT p ON p.bill_id=b.bill_id WHERE b.bill_id=$bill GROUP BY b.bill_id,b.amount,b.status")"

echo; echo "## I-14 Privacy (GDPR): consumer9 submits a right-to-be-forgotten request"
code=$(login consumer9@example.cy); check "consumer9 logs in" '[ "$code" = 303 ]' "got $code"
out=$(post /consumer/gdpr.php -d "request_type=RIGHT_TO_BE_FORGOTTEN&confirm=1")
gid=$(echo "$out" | okmsg | sed -n 's/Request #\([0-9]*\) submitted.*/\1/p')
echo "flash: $(echo "$out" | okmsg) $(echo "$out" | alert)"
check "I-14 right-to-be-forgotten request #$gid listed as SUBMITTED" '[ -n "$gid" ] && echo "$out" | tr -d "\n" | grep -q "RIGHT_TO_BE_FORGOTTEN.*SUBMITTED"' "$(echo "$out" | alert)"
if [ -n "$gid" ]; then
  echo "cleanup on L (so consumer9 stays usable for consumer_pages.sh): officer1 rejects request #$gid"
  sql "DECLARE @o INT=(SELECT user_id FROM dbo.USER_ACCOUNT WHERE email='officer1@mdms.cy'); EXEC dbo.sp_AdvanceGdprRequest @o, $gid, 'REJECTED';" | head -3
  echo "status now: $(sql "SELECT status FROM dbo.GDPR_REQUEST WHERE gdpr_request_id=$gid")"
fi

echo; echo "manual_L.sh: $pass passed, $fail failed"; [ "$fail" -eq 0 ]
