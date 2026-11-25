#!/usr/bin/env bash
# HTTP test of tasks B4 (market), B7 (dso), B8 (tso), B9 (map) and B10 (throttling) against a running instance:
#   BASE_URL=http://localhost:8080 bash tests/market_dso_tso.sh            reads and refused writes only
#   BASE_URL=http://localhost:8080 WRITE=1 bash tests/market_dso_tso.sh    also writes that change data: own database only
# Needs the demo accounts of import.sql (password Passw0rd!23). Every login appends one audit row.
BASE="${BASE_URL:-http://localhost:8080}"; PW="${DEMO_PASSWORD:-Passw0rd!23}"
# the application may be served from a sub-folder (BASE_PATH): P is the path part of BASE_URL, EP the same URL-encoded
P=$(printf '%s' "$BASE" | sed -E 's#^https?://[^/]+##; s#/+$##'); EP=$(printf '%s' "$P" | sed 's#/#%2F#g')
DIR="$(mktemp -d)"; command -v cygpath > /dev/null && DIR="$(cygpath -m "$DIR")"; trap 'rm -rf "$DIR"' EXIT
JAR="$DIR/jar"; OUT="$DIR/out"; fail=0; pass=0; CODE=
. "$(dirname "$0")/connect_lib.sh"   # dbconnect: the Connect page, when DB_FORM_PASS is set
check() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1  (code $CODE) $(grep -o 'role="alert">[^<]*' "$OUT" | tr '\n' ' ')"; fail=$((fail+1)); fi; }
get()   { CODE=$(curl -s -o "$OUT" -D "$DIR/hdr" -w '%{http_code}' -b "$JAR" -c "$JAR" "$BASE$1"); }
token() { curl -s -b "$JAR" -c "$JAR" "$BASE$1" | sed -n 's/.*name="_csrf" value="\([^"]*\)".*/\1/p' | head -1; }
post()  { # $1 page, then name=value ... ; values go through files because curl.exe would damage Greek arguments
  local page="$1" t args=() n=0; shift; t="$(token "$page")"
  for kv in "$@"; do n=$((n+1)); printf '%s' "${kv#*=}" > "$DIR/v$n"; args+=(-F "${kv%%=*}=<$DIR/v$n"); done
  CODE=$(curl -s -o "$OUT" -D "$DIR/hdr" -w '%{http_code}' -b "$JAR" -c "$JAR" -F "_csrf=$t" "${args[@]}" "$BASE$page"); }
to()    { [ "$CODE" = 303 ] && tr -d '\r' < "$DIR/hdr" | grep -qix -- "location: $P$1"; }   # $1 is an application path
has()   { grep -qF -- "$1" "$OUT"; }
login() { rm -f "$JAR"; : > "$JAR"; dbconnect; post /login.php "email=$1" "password=$PW"; to /home.php || echo "     (login of $1 failed: $CODE)"; }

MARKET="/market/ /market/day-ahead.php /market/intraday.php /market/data.php"
CHAIN="/dso/ /dso/ingest.php /dso/vee.php /dso/suspects.php /dso/finalize.php"
TSO="/tso/ /tso/shedding.php /tso/transformer.php"
BOTH="/tso/state.php /tso/frequency.php"
ALL="$MARKET /market/bills.php $CHAIN /dso/reports.php /dso/events.php $TSO $BOTH /tso/tree.php /tso/map.php"

# --- nobody gets in without a session or with the wrong role
: > "$JAR"
for p in $ALL; do get "$p"; check "no session: $p goes to the login" '[ $CODE = 303 ] && grep -qi "^location: $P/login.php" "$DIR/hdr"'; done
for p in /market/api/portfolio.php /market/api/day-ahead.php /market/api/intraday.php /tso/map-data.php; do
  get "$p"; check "no session: $p answers 401 as JSON" '[ $CODE = 401 ] && has "\"error\"" && grep -qi "application/json" "$DIR/hdr"'; done
login consumer1@example.cy
for p in $ALL; do get "$p"; check "consumer on $p: 403" '[ $CODE = 403 ]'; done
for p in /market/api/day-ahead.php /tso/map-data.php; do get "$p"; check "consumer on $p: 403 as JSON" '[ $CODE = 403 ] && has "\"error\""'; done
login dso@mdms.cy
for p in $MARKET $TSO; do get "$p"; check "DSO on $p: 403" '[ $CODE = 403 ]'; done
login tso@mdms.cy
for p in $MARKET $CHAIN /dso/reports.php; do get "$p"; check "TSO on $p: 403" '[ $CODE = 403 ]'; done
login officer1@mdms.cy
for p in $MARKET $TSO $BOTH /dso/reports.php; do get "$p"; check "officer on $p: 403" '[ $CODE = 403 ]'; done
for p in $CHAIN /dso/events.php /tso/tree.php /tso/map.php; do get "$p"; check "officer opens $p" '[ $CODE = 200 ]'; done

# --- B4 market
login billing@eacsupply.cy
for p in $MARKET /market/bills.php; do get "$p"; check "supplier opens $p" '[ $CODE = 200 ]'; done
get "/market/day-ahead.php?from=2026-10-31&to=2026-10-30"; check "Day-Ahead, from after to: message of the database (422)" '[ $CODE = 422 ] && has "from &lt;= to"'
get "/market/day-ahead.php?from=xx&to=2026-10-30"; check "Day-Ahead, not a date: 422, the value is escaped" '[ $CODE = 422 ] && has "must be dates"'
get "/market/day-ahead.php?level=0"; check "Day-Ahead, level 0: 422" '[ $CODE = 422 ]'
get "/market/intraday.php?from=2026-10-30T00:00&to=2026-11-02T00:00"; check "Intraday, more than 24 hours: 422" '[ $CODE = 422 ] && has "24 hours"'
get "/market/intraday.php?from[]=1"; check "array parameter: no server error" '[ $CODE = 200 ] || [ $CODE = 422 ]'
get "/market/api/portfolio.php"; check "JSON portfolio" '[ $CODE = 200 ] && has "\"rows\":["'
get "/market/api/day-ahead.php?from=2026-10-01&to=2026-11-30&level=3"; check "JSON Day-Ahead with the filters used" '[ $CODE = 200 ] && has "\"level\":3" && has "\"count\":"'
get "/market/api/intraday.php?from=2026-10-30T00:00&to=2026-11-02T00:00"; check "JSON error: 422 and a message" '[ $CODE = 422 ] && has "\"error\":\"Invalid input"'
get "/market/bills.php"; check "bills show no consumer id" '! has "user_id"'
post /market/bills.php month=2099-01; check "bill run for a month that has not ended is refused" '[ $CODE = 422 ] && has "not ended"'
login desk@flexpool.cy
for p in $MARKET; do get "$p"; check "aggregator opens $p" '[ $CODE = 200 ]'; done
get /market/bills.php; check "aggregator on the bills: 403" '[ $CODE = 403 ]'

# --- B7 dso
login dso@mdms.cy
for p in $CHAIN /dso/reports.php /dso/events.php /tso/state.php /tso/frequency.php /tso/tree.php /tso/map.php; do get "$p"; check "DSO opens $p" '[ $CODE = 200 ]'; done
post /dso/ingest.php mode=packet payload=; check "ingest: empty packet is refused" '[ $CODE = 422 ]'
post /dso/ingest.php mode=batch 'payload={"a":1}'; check "ingest: a batch must be an array" '[ $CODE = 422 ] && has "JSON array"'
head -c 4100 /dev/zero | tr '\0' x > "$DIR/long"; post /dso/ingest.php mode=packet "payload=$(cat "$DIR/long")"; check "ingest: a packet over 4000 characters is refused, not cut" '[ $CODE = 422 ] && has "4000"'
post /dso/vee.php from=2026-10-31T00:00 to=2026-10-30T00:00 meter_id=; check "VEE: wrong window" '[ $CODE = 422 ]'
post /dso/suspects.php action=accept reading_id=abc; check "suspects: wrong reading number" '[ $CODE = 422 ]'
post /dso/suspects.php action=edit reading_id=999999999 new_value=1e9; check "suspects: 1e9 is not a decimal" '[ $CODE = 422 ] && has "must be a number"'
post /dso/suspects.php action=edit reading_id=999999999 new_value=-1,5; check "suspects: unknown reading (the database answers 404)" '[ $CODE = 404 ]'
post /dso/finalize.php action=finalize day=2099-01-01 meter_id=; check "finalize: a day in the future is refused" '[ $CODE = 422 ] && has "has ended"'
get "/dso/reports.php?report=losses&transformer=999999&from=2026-10-01T00:00&to=2026-11-01T00:00"; check "reports: unknown transformer" '[ $CODE = 404 ]'
get "/dso/reports.php?report=voltage&transformer=1&from=2026-10-01T00:00&to=2026-12-01T00:00"; check "reports: voltage" '[ $CODE = 200 ] && ! has "role=\"alert\""'
get "/dso/reports.php?report=unbalance&transformer=1&from=2026-10-01T00:00&to=2026-12-01T00:00&threshold=20"; check "reports: unbalance" '[ $CODE = 200 ]'
get "/dso/reports.php?report=unbalance&transformer=1&from=2026-10-01T00:00&to=2026-12-01T00:00&action=raise"; check "reports: a GET never records events (no flash)" '[ $CODE = 200 ] && ! has "events were recorded"'
post /dso/events.php network_id=NO-SUCH-METER; check "tamper alert for an unknown meter: 404" '[ $CODE = 404 ]'
post /tso/frequency.php transformer_id=1 slot=2026-11-01T00:00 obis_code=14.7.0 value=abc; check "frequency: not a number" '[ $CODE = 422 ]'
CODE=$(curl -s -o "$OUT" -w '%{http_code}' -b "$JAR" -c "$JAR" -d 'action=finalize&day=2026-10-30' "$BASE/dso/finalize.php"); check "a POST without the CSRF token is refused (403)" '[ $CODE = 403 ]'
login officer1@mdms.cy
t="$(token /dso/ingest.php)"; CODE=$(curl -s -o "$OUT" -w '%{http_code}' -b "$JAR" -d "_csrf=$t&network_id=X" "$BASE/dso/events.php"); check "an officer cannot raise a tamper alert (403)" '[ $CODE = 403 ]'

# --- B8 / B9 tso
login tso@mdms.cy
for p in $TSO $BOTH /tso/tree.php /tso/map.php /dso/events.php; do get "$p"; check "TSO opens $p" '[ $CODE = 200 ]'; done
get "/tso/tree.php?root=999999"; check "tree: unknown root" '[ $CODE = 404 ]'
get "/tso/transformer.php?id=999999"; check "transformer: unknown" '[ $CODE = 404 ]'
post /tso/transformer.php id= name=X level=1 capacity_kva=-5 latitude=35 longitude=33 parent_transformer_id=; check "transformer: negative capacity" '[ $CODE = 422 ]'
post /tso/shedding.php action=shed transformer_id=1 command_type=DISCONNECT reason=test; check "shedding without the confirmation does nothing" '[ $CODE = 422 ] && has "confirmation"'
post /tso/shedding.php action=shed transformer_id=1 command_type=FIRMWARE_UPGRADE reason=test confirm=1; check "shedding: another command type is refused" '[ $CODE = 422 ]'
get "/tso/shedding.php?transformer_id=1&command_type=DISCONNECT&reason=test"; check "shedding: the check page asks for a confirmation" '[ $CODE = 200 ] && has "2. Confirm"'
t="$(token /tso/shedding.php)"; CODE=$(curl -s -o "$OUT" -w '%{http_code}' -b "$JAR" -d "_csrf=$t&transformer_id=1&slot=2026-11-01T00:00&obis_code=14.7.0&value=50" "$BASE/tso/frequency.php"); check "a TSO cannot record a measurement (403)" '[ $CODE = 403 ]'
get /tso/map-data.php; check "map data: transformers and meters" '[ $CODE = 200 ] && has "\"transformers\":[{" && has "\"meters\":["'
get "/tso/map-data.php?lat=35.1&lon=33.25"; check "map data: geofence of a point" '[ $CODE = 200 ] && has "\"path\":["'
get "/tso/map-data.php?lat=abc&lon=33"; check "map data: wrong coordinates" '[ $CODE = 422 ]'
get /tso/map.php; check "map: own scripts only, tiles allowed for images" 'grep -i "^content-security-policy:" "$DIR/hdr" | grep -q "img-src [^;]*https://tile.openstreetmap.org" && ! grep -qE "<script[^>]+src=\"https?:" "$OUT"'
for a in leaflet/leaflet.js leaflet/leaflet.css map.js map.css; do get "/assets/$a"; check "asset $a is served" '[ $CODE = 200 ]'; done

# --- writes
if [ "${WRITE:-0}" = 1 ]; then
  login dso@mdms.cy
  post /dso/ingest.php mode=packet 'payload=this is not JSON Ωμέγα'; check "W ingest: a broken packet is stored (303)" 'to /dso/ingest.php'
  get /dso/ingest.php; check "W ...as COMM_ERROR" 'has COMM_ERROR'
  post /dso/ingest.php mode=batch 'payload=[{"Meter_Network_ID":"NO-SUCH","Transmission_Timestamp":"2026-11-01T10:00:00Z","Telemetry_Payload":[]}]'; check "W ingest: batch (303)" 'to /dso/ingest.php'
  get /dso/ingest.php; check "W ...one unmatched" 'has "Batch stored: 1 packets"'
  post /dso/vee.php from=2026-10-30T00:00 to=2026-10-31T23:45 meter_id=; check "W VEE runs" 'to /dso/vee.php'
  get /dso/vee.php; check "W ...and shows its result" 'has "meters processed"'
  login tso@mdms.cy
  post /tso/ slot=; check "W refresh of the grid state" 'to /tso/'
  get /tso/; check "W ...and its message" 'has "was computed for"'
fi

# --- B10: throttling (one email that does not exist, so no real account is locked)
rm -f "$JAR"; : > "$JAR"; dbconnect; E="nobody$RANDOM$RANDOM@example.cy"
for i in 1 2 3 4 5; do post /login.php "email=$E" password=wrong-password; done; check "five wrong passwords: still 401" '[ $CODE = 401 ]'
post /login.php "email=$E" password=wrong-password; check "the sixth is refused for a while (429)" '[ $CODE = 429 ] && grep -qi "^retry-after:" "$DIR/hdr"'
login consumer1@example.cy; get /home.php; check "other users are not affected" '[ $CODE = 200 ]'

echo; echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ] && echo "market_dso_tso.sh: all passed"
exit "$fail"
