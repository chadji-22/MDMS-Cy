#!/usr/bin/env bash
# Ioannis's manual tests I-03, I-07, I-08, I-09 (TESTING_PLAN.md 4.1), READ-ONLY, for R or S.
# One successful Connect (when DB_FORM_PASS is set), three application logins (consumer1, tso, consumer2), GETs only
# (plus the two logout POSTs). No wrong password anywhere, so no throttle counts.
# Usage (repo root): [DB_FORM_PASS=...] BASE_URL=... bash manual_ro.sh
BASE="${BASE_URL:?}"; PW='Passw0rd!23'
P=$(printf '%s' "$BASE" | sed -E 's#^https?://[^/]+##; s#/+$##')
DIR="$(mktemp -d)"; command -v cygpath > /dev/null && DIR="$(cygpath -m "$DIR")"; trap 'rm -rf "$DIR"' EXIT
JAR="$DIR/jar"; : > "$JAR"
. sources/tests/connect_lib.sh
pass=0; fail=0
check() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1  ${3:-}"; fail=$((fail+1)); fi; }
token() { curl -s -b "$JAR" -c "$JAR" "$BASE${1:-/login.php}" | sed -n 's/.*name="_csrf" value="\([^"]*\)".*/\1/p' | head -1; }
body()  { curl -s -b "$JAR" -c "$JAR" "$@"; }
st()    { curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -c "$JAR" "$@"; }
login() { local t; t="$(token)"; curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -c "$JAR" \
            --data-urlencode "_csrf=$t" --data-urlencode "email=$1" --data-urlencode "password=$PW" "$BASE/login.php"; }
logout(){ local t; t="$(token /home.php)"; curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -c "$JAR" --data-urlencode "_csrf=$t" "$BASE/logout.php"; }
alert() { sed -n 's/.*role="alert">\([^<]*\)<.*/\1/p' | head -1; }
menus() { echo "$1" | grep -oE "href=\"$P/(consumer|tso|dso|staff|technician|market)/\"" | sed -E "s#href=\"$P/##; s#/\"##" | sort -u | tr '\n' ' '; }
LAST_MONTH_FROM=$(date -u -d "$(date -u +%Y-%m-01) -1 month" +%Y-%m-%d); LAST_MONTH_END=$(date -u -d "$(date -u +%Y-%m-01) -1 day" +%Y-%m-%d)
D1=$(date -u -d "$LAST_MONTH_END -1 day" +%Y-%m-%d)
echo "# target $BASE; imported days $D1 and $LAST_MONTH_END; Connect page: $([ -n "${DB_FORM_PASS:-}" ] && echo yes || echo no); $(date -u +%FT%TZ)"

dbconnect
c=$(st "$BASE/login.php"); check "connected once: the login page opens (200)" '[ "$c" = 200 ]' "got $c"
code=$(login consumer1@example.cy); check "consumer1 logs in (303)" '[ "$code" = 303 ]' "got $code"

echo; echo "## I-07 consumer1 opens $P/tso/ directly"
code=$(st "$BASE/tso/"); out=$(body "$BASE/tso/")
check "I-07 403 Access denied" '[ "$code" = 403 ] && echo "$out" | grep -qi "Access denied"' "got $code"

echo; echo "## I-08 My premises; Readings for a premise"
out=$(body "$BASE/consumer/")
check "I-08 My premises: Greek addresses intact" 'echo "$out" | grep -q "Λεωφ. Στροβόλου 101" && echo "$out" | grep -q "Οδός Γρίβα Διγενή 12" && echo "$out" | grep -q "Στρόβολος"'
out=$(body "$BASE/consumer/readings.php?premise_id=1&from=$D1&to=$LAST_MONTH_END")
if echo "$out" | grep -q "slots"; then
  n1=$(echo "$out" | grep -o "$D1 [0-9][0-9]:[0-9][0-9]" | sort -u | wc -l); echo "premise 1, $D1..$LAST_MONTH_END: rows shown, $n1 slots on $D1"
  check "I-08 premise 1: 15-minute rows (import 1.8.0)" '[ "$n1" -ge 90 ] && echo "$out" | grep -q "Import 1.8.0"'
else
  echo "premise 1, $D1..$LAST_MONTH_END: '$(echo "$out" | alert)'"
  check "I-08 premise 1: last month not bought on this database -> the 50008 reason and the way to buy it (by design, project §1.2)" 'echo "$out" | grep -q "not bought for this period" && echo "$out" | grep -q "See the price and buy access"'
fi

echo; echo "## I-09 Totals: daily and monthly (premise 1)"
out=$(body "$BASE/consumer/aggregates.php?premise_id=1&period=DAY&from=$D1&to=$LAST_MONTH_END")
if echo "$out" | grep -q "role=\"alert\""; then
  echo "premise 1 daily: '$(echo "$out" | alert)'"
  check "I-09 premise 1 daily: not bought -> 50008 message" 'echo "$out" | grep -q "not bought for this period"'
else
  echo "premise 1 daily: $(echo "$out" | grep -oE '<td[^>]*>[^<]*</td>' | sed 's/<[^>]*>//g' | head -8 | tr '\n' '|')"
  check "I-09 premise 1: daily totals of the two imported days" 'echo "$out" | grep -q "<td class=\"mono\">$D1</td>" && echo "$out" | grep -q "<td class=\"mono\">$LAST_MONTH_END</td>"'
  out=$(body "$BASE/consumer/aggregates.php?premise_id=1&period=MONTH&from=$LAST_MONTH_FROM&to=$LAST_MONTH_END")
  echo "premise 1 monthly: $(echo "$out" | grep -oE '<td[^>]*>[^<]*</td>' | sed 's/<[^>]*>//g' | head -4 | tr '\n' '|')"
  check "I-09 premise 1: monthly total" 'echo "$out" | grep -q "<td class=\"mono\">${LAST_MONTH_FROM:0:7}" && ! echo "$out" | grep -q "role=\"alert\""'
fi

echo; echo "## I-03 Log out, log in as tso: no second Connect; tso menu only"
code=$(logout); check "I-03 consumer1 logs out (303)" '[ "$code" = 303 ]' "got $code"
code=$(st "$BASE/login.php"); out=$(body "$BASE/login.php")
check "I-03 after log out the login form opens directly (200, no Connect page)" '[ "$code" = 200 ] && echo "$out" | grep -q "name=\"email\""' "got $code"
code=$(login tso@mdms.cy); home=$(body "$BASE/home.php")
echo "menus seen by tso: $(menus "$home")"
check "I-03 tso logs in without a second Connect and sees the tso menu only" '[ "$code" = 303 ] && [ "$(menus "$home")" = "tso " ]' "got $code"
code=$(st "$BASE/tso/tree.php"); check "I-03 a tso page reads the database (200)" '[ "$code" = 200 ]'
logout > /dev/null

echo; echo "## I-08 / I-09 with a prosumer premise that has bought data (consumer2, premise 3)"
code=$(login consumer2@example.cy); check "consumer2 logs in (303)" '[ "$code" = 303 ]' "got $code"
out=$(body "$BASE/consumer/readings.php?premise_id=3&from=$D1&to=$LAST_MONTH_END")
n3=$(echo "$out" | grep -o "$D1 [0-9][0-9]:[0-9][0-9]" | sort -u | wc -l)
check "I-08 premise 3: 15-minute rows with import and export ($n3 slots on $D1)" 'echo "$out" | grep -q "Import 1.8.0" && echo "$out" | grep -q "Export 2.8.0" && [ "$n3" -ge 90 ]' "$(echo "$out" | alert)"
echo "premise 3 address: $(echo "$(body "$BASE/consumer/")" | tr -d '\n' | grep -oE '<td>#?3</td>[^/]*' | sed 's/<[^>]*>/ /g' | head -1)"
out=$(body "$BASE/consumer/aggregates.php?premise_id=3&period=DAY&from=$D1&to=$LAST_MONTH_END")
echo "premise 3 daily: $(echo "$out" | grep -oE '<td[^>]*>[^<]*</td>' | sed 's/<[^>]*>//g' | head -10 | tr '\n' '|')"
check "I-09 premise 3: daily totals of the two imported days" 'echo "$out" | grep -q "<td class=\"mono\">$D1</td>" && echo "$out" | grep -q "<td class=\"mono\">$LAST_MONTH_END</td>"' "$(echo "$out" | alert)"
out=$(body "$BASE/consumer/aggregates.php?premise_id=3&period=MONTH&from=$LAST_MONTH_FROM&to=$LAST_MONTH_END")
echo "premise 3 monthly: $(echo "$out" | grep -oE '<td[^>]*>[^<]*</td>' | sed 's/<[^>]*>//g' | head -6 | tr '\n' '|')"
check "I-09 premise 3: monthly total" 'echo "$out" | grep -q "<td class=\"mono\">${LAST_MONTH_FROM:0:7}" && ! echo "$out" | grep -q "role=\"alert\""' "$(echo "$out" | alert)"
logout > /dev/null

echo; echo "manual_ro.sh: $pass passed, $fail failed"; [ "$fail" -eq 0 ]
