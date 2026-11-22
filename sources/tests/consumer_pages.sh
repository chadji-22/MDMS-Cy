#!/usr/bin/env bash
# HTTP test of the consumer pages (task B3) against a running instance:
#   BASE_URL=http://localhost:8080 bash tests/consumer_pages.sh            read-only checks (+ refused writes)
#   BASE_URL=http://localhost:8080 WRITE=1 bash tests/consumer_pages.sh    also the write flows, as consumer9 (keeps demo consumers 1-4 intact)
# Needs the data of import.sql (password Passw0rd!23). Every login appends one audit row (LOGIN_OK).
# [project.pdf §1.1-§1.4 p.5-7; §IV p.13 security: unauthorised access is refused]
BASE="${BASE_URL:-http://localhost:8080}"
PW="${DEMO_PASSWORD:-Passw0rd!23}"
JAR="$(mktemp)"; trap 'rm -f "$JAR"' EXIT
fail=0; pass=0
ok()  { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1  ${2:-}"; fail=$((fail+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }
token() { curl -s -b "$JAR" -c "$JAR" "$BASE${1:-/login.php}" | sed -n 's/.*name="_csrf" value="\([^"]*\)".*/\1/p' | head -1; }
status() { curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -c "$JAR" "$@"; }
body()   { curl -s -b "$JAR" -c "$JAR" "$@"; }
login()  { : > "$JAR"; local t; t="$(token)"; curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -c "$JAR" \
             --data-urlencode "_csrf=$t" --data-urlencode "email=$1" --data-urlencode "password=$PW" "$BASE/login.php"; }
post()   { local page="$1"; shift; local t; t="$(token "$page")"; curl -s -b "$JAR" -c "$JAR" -L --data-urlencode "_csrf=$t" "$@" "$BASE$page"; }
alert()  { sed -n 's/.*role="alert">\([^<]*\)<.*/\1/p' | head -1; }
ok_msg() { sed -n 's/.*class="flash ok" role="status">\([^<]*\)<.*/\1/p' | head -1; }

PAGES="/consumer/ /consumer/readings.php /consumer/aggregates.php /consumer/history.php /consumer/events.php /consumer/requests.php /consumer/request.php?id=1 /consumer/bills.php /consumer/gdpr.php"
LAST_MONTH_FROM=$(date -u -d "$(date -u +%Y-%m-01) -1 month" +%Y-%m-%d)
LAST_MONTH_END=$(date -u -d "$(date -u +%Y-%m-01) -1 day" +%Y-%m-%d)
LAST_MONTH=${LAST_MONTH_FROM:0:7}
D1=$(date -u -d "$LAST_MONTH_END -1 day" +%Y-%m-%d)     # the two imported days of import.sql

# --- guards: no session, wrong roles -----------------------------------------------------------------
: > "$JAR"
for p in $PAGES; do check "no session: $p redirects to login (303)" '[ "$(status "$BASE$p")" = "303" ]'; done
for who in officer1@mdms.cy tech1@mdms.cy dso@mdms.cy billing@eacsupply.cy; do
  login "$who" >/dev/null
  for p in /consumer/ /consumer/readings.php /consumer/bills.php /consumer/gdpr.php; do
    check "$who on $p is refused (403)" '[ "$(status "$BASE$p")" = "403" ]'
  done
done

# --- consumer2: every page opens; prosumer import/export; history rule ---------------------------------
code=$(login consumer2@example.cy); check "consumer2 logs in" '[ "$code" = "303" ]' "got $code"
home=$(body "$BASE/home.php")
check "consumer menu lists the 8 pages" '[ "$(echo "$home" | grep -o "href=\"/consumer/[a-z]*\(\.php\)\?\"" | sort -u | wc -l)" -ge 8 ]'
for p in $PAGES; do
  [ "$p" = "/consumer/request.php?id=1" ] && continue
  check "consumer2 opens $p (200)" '[ "$(status "$BASE$p")" = "200" ]'
done
out=$(body "$BASE/consumer/readings.php?premise_id=3&from=$D1&to=$LAST_MONTH_END")
check "prosumer premise 3, bought days: import and export side by side" 'echo "$out" | grep -q "Export 2.8.0" && echo "$out" | grep -q "slots"' "$(echo "$out" | alert)"
out=$(body "$BASE/consumer/readings.php?premise_id=4&from=$D1&to=$LAST_MONTH_END")
check "premise 4, past month not bought: 50008 message and the reason, not an empty table" \
      'echo "$out" | grep -q "not bought for this period" && echo "$out" | grep -q "See the price and buy access" && ! echo "$out" | grep -q "<th class=\"num\">Import"'
out=$(body "$BASE/consumer/aggregates.php?premise_id=4&period=DAY&from=$LAST_MONTH_FROM&to=$LAST_MONTH_END")
check "totals of premise 4, past month not bought: 50008 message" 'echo "$out" | grep -q "not bought for this period"'
out=$(body "$BASE/consumer/aggregates.php?premise_id=3&period=DAY&from=$D1&to=$LAST_MONTH_END")
check "totals of premise 3 (bought): daily table with import and export" 'echo "$out" | grep -q "Export 2.8.0 (PV)" && echo "$out" | grep -q "<td class=\"mono\">$D1</td>"'
out=$(body "$BASE/consumer/readings.php?premise_id=1&from=$D1&to=$LAST_MONTH_END")
check "another consumer's premise: 'Permission denied: not your premise.'" '[ "$(echo "$out" | alert)" = "Permission denied: not your premise." ]' "$(echo "$out" | alert)"
out=$(body "$BASE/consumer/readings.php?premise_id=3&from=$LAST_MONTH_FROM&to=$(date -u +%Y-%m-%d)")
check "window longer than 31 days: 50004 message" 'echo "$out" | alert | grep -q "at most 31 days"'
out=$(body "$BASE/consumer/history.php?premise_id=4&from=$LAST_MONTH&to=$LAST_MONTH")
check "history quote for premise 4, last month: price and buy button" 'echo "$out" | grep -q "Buy access for"'
out=$(body "$BASE/consumer/history.php?premise_id=4&from=$(date -u +%Y-%m)&to=$(date -u +%Y-%m)")
check "history quote for the current month: cannot be bought" 'echo "$out" | grep -q "This period cannot be bought"'
out=$(body "$BASE/consumer/request.php?id=999999")
check "unknown request id: 'Work order not found.'" '[ "$(echo "$out" | alert)" = "Work order not found." ]' "$(echo "$out" | alert)"
out=$(body "$BASE/consumer/events.php?premise_id=3")
check "events of premise 3: the 198.5 V undervoltage event" 'echo "$out" | grep -q "Undervoltage"'
out=$(body "$BASE/consumer/bills.php")
check "bills page: bills and payment history of consumer2" 'echo "$out" | grep -q "<h2>Bills</h2>" && echo "$out" | grep -q "HISTORICAL_ACCESS"'

# --- refused writes (nothing is stored) ----------------------------------------------------------------
check "POST without CSRF token is refused (403)" '[ "$(curl -s -o /dev/null -w "%{http_code}" -b "$JAR" -c "$JAR" -d "address=x" "$BASE/consumer/")" = "403" ]'
# Greek is sent percent-encoded (UTF-8): text typed on a Windows command line may reach curl in another code page
GR_NICOSIA='%CE%9B%CE%B5%CF%85%CE%BA%CF%89%CF%83%CE%AF%CE%B1'; GR_STROVOLOS='%CE%A3%CF%84%CF%81%CF%8C%CE%B2%CE%BF%CE%BB%CE%BF%CF%82'
out=$(post /consumer/ -d "address=Test+1&latitude=35.1&longitude=33.3&usage_type=RESIDENTIAL&district=$GR_NICOSIA" \
      -d "municipality=$GR_STROVOLOS&parish=$GR_STROVOLOS&postal_code=12a&prosumer_scheme=NONE&supplier_org_id=")
check "add premise with a bad postal code: 50004 from the database" '[ "$(echo "$out" | alert)" = "Invalid input: the postal code needs 4 digits." ]' "$(echo "$out" | alert)"
out=$(post /consumer/history.php -d "premise_id=4&from=$(date -u +%Y-%m)&to=$(date -u +%Y-%m)&method=CARD")
check "buy the current month: refused with 50008 ('current month is free')" 'echo "$out" | alert | grep -q "current month is free"' "$(echo "$out" | alert)"
out=$(post /consumer/bills.php -d "action=pay_bill&bill_id=1&amount=1.00&method=CARD")
check "pay someone else's bill #1: refused" 'echo "$out" | alert | grep -q -E "not your bill|already paid"' "$(echo "$out" | alert)"
out=$(post /consumer/gdpr.php -d "request_type=RIGHT_TO_BE_FORGOTTEN")
check "right to be forgotten without the confirmation box: refused, nothing submitted" 'echo "$out" | alert | grep -q "tick the box"'

# --- write flows (WRITE=1), as consumer9 ---------------------------------------------------------------
if [ "${WRITE:-0}" = "1" ]; then
  login consumer9@example.cy >/dev/null
  out=$(post /consumer/events.php -d "action=threshold&premise_id=11&threshold_kwh=250")
  check "W1 set a threshold of 250 kWh on premise 11" 'echo "$out" | ok_msg | grep -q "Threshold saved: 250"' "$(echo "$out" | alert)"
  out=$(post /consumer/events.php -d "action=threshold&premise_id=11&clear=1")
  check "W2 remove the threshold" 'echo "$out" | ok_msg | grep -q "Threshold removed"' "$(echo "$out" | alert)"
  out=$(post /consumer/events.php -d "action=notify&premise_id=11&notify_email=1&notify_sms=1")
  check "W3 notification preferences: email + SMS" 'echo "$out" | ok_msg | grep -q "preferences saved" && echo "$out" | grep -q "name=\"notify_sms\" value=\"1\" checked"' "$(echo "$out" | alert)"
  out=$(post /consumer/requests.php -d "premise_id=11&work_type=FAULT_REPAIR" --data-urlencode "description=B3 test: display blank")
  id=$(echo "$out" | sed -n 's/.*Request #\([0-9]*\) submitted.*/\1/p' | head -1)
  check "W4 submit a fault request, land on its history page" '[ -n "$id" ] && echo "$out" | grep -q "SUBMITTED"' "$(echo "$out" | alert)"
  out=$(post /consumer/request.php -d "id=$id" --data-urlencode "reason=B3 test cleanup")
  check "W5 cancel it; the history shows SUBMITTED -> CANCELLED" 'echo "$out" | grep -q "CANCELLED"' "$(echo "$out" | alert)"
  svc=$(body "$BASE/consumer/bills.php" | sed -n 's/.*<option value="\([0-9]*\)">METER_CHECK.*/\1/p' | head -1)
  out=$(post /consumer/bills.php -d "action=pay_service&service_type_id=$svc&method=CARD")
  check "W6 pay the METER_CHECK fee (amount taken from the database)" 'echo "$out" | ok_msg | grep -q "Payment #"' "$(echo "$out" | alert)"
  # consumer9's meter 11 keeps 1 month only (retention reduced in import.sql), so its past cannot be bought:
  out=$(post /consumer/history.php -d "premise_id=11&from=$LAST_MONTH&to=$LAST_MONTH&method=CARD")
  check "W7a buy last month for premise 11 (retention 1 month): refused with the retention reason" 'echo "$out" | alert | grep -q "outside the retention time"' "$(echo "$out" | alert)"
  out=$(post /consumer/gdpr.php -d "request_type=RETENTION_REDUCTION&premise_id=11")
  check "W8 retention request: submitted, or 50005 if one is already open" '{ echo "$out" | ok_msg | grep -q "submitted"; } || echo "$out" | alert | grep -q "Duplicate"' "$(echo "$out" | alert)"
  check "W9 the request is listed with its history" 'echo "$out" | grep -q "RETENTION_REDUCTION"'
  # consumer7 (premise 9, 3-year retention): buying last month makes the readings visible (once; then it is already bought)
  login consumer7@example.cy >/dev/null
  out=$(body "$BASE/consumer/readings.php?premise_id=9&from=$D1&to=$LAST_MONTH_END")
  if echo "$out" | grep -q "not bought for this period"; then
    out=$(post /consumer/history.php -d "premise_id=9&from=$LAST_MONTH&to=$LAST_MONTH&method=CARD")
    check "W7b buy last month for premise 9, then its readings are visible" 'echo "$out" | ok_msg | grep -q "bought" && echo "$out" | grep -q "slots"' "$(echo "$out" | alert)"
  else
    check "W7b premise 9: last month already bought, readings visible" 'echo "$out" | grep -q "slots"' "$(echo "$out" | alert)"
  fi
fi

echo "consumer_pages.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
