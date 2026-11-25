#!/usr/bin/env bash
# HTTP test of the Connect page (an instance WITHOUT DB_PASS in its settings, like the department web server):
#   BASE_URL=https://.../~login/mdms DB_FORM_PASS=... bash tests/connect.sh
# DB_FORM_NAME / DB_FORM_USER default to what the page pre-fills. The password is never printed.
# CONNECT_THROTTLE=1 also checks the 6th wrong password is refused: that blocks the Connect page from this address for
# 15 minutes, so it runs last and only on request. Every run makes 2 refused connection attempts (wrong password, wrong
# database), then a successful one, which resets the count.
BASE="${BASE_URL:-http://localhost:8080}"; PW="${DEMO_PASSWORD:-Passw0rd!23}"
P=$(printf '%s' "$BASE" | sed -E 's#^https?://[^/]+##; s#/+$##'); EP=$(printf '%s' "$P" | sed 's#/#%2F#g')
[ -n "${DB_FORM_PASS:-}" ] || { echo "set DB_FORM_PASS (the database password; it is not printed)"; exit 2; }
DIR="$(mktemp -d)"; command -v cygpath > /dev/null && DIR="$(cygpath -m "$DIR")"; trap 'rm -rf "$DIR"' EXIT
JAR="$DIR/jar"; OUT="$DIR/out"; HDR="$DIR/hdr"; fail=0; pass=0; CODE=
. "$(dirname "$0")/connect_lib.sh"
check() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1  (code $CODE) $(grep -o 'role="alert">[^<]*' "$OUT" | head -1)"; fail=$((fail+1)); fi; }
get()   { CODE=$(curl -s -o "$OUT" -D "$HDR" -w '%{http_code}' -b "$JAR" -c "$JAR" "$BASE$1"); }
token() { curl -s -b "$JAR" -c "$JAR" "$BASE$1" | sed -n 's/.*name="_csrf" value="\([^"]*\)".*/\1/p' | head -1; }
loc()   { tr -d '\r' < "$HDR" | sed -n 's/^[Ll]ocation: //p'; }
has()   { grep -qF -- "$1" "$OUT"; }
nopw()  { ! grep -qF -- "$DB_FORM_PASS" "$OUT"; }               # the password never comes back in a page
# $1 dbName (empty: pre-filled), $2 password source: "good" or a literal wrong password
connect_as() {
  local t n u; t="$(token /connect.php)"
  n=${1:-${DB_FORM_NAME:-$(curl -s -b "$JAR" -c "$JAR" "$BASE/connect.php" | sed -n 's/.*name="dbName" value="\([^"]*\)".*/\1/p' | head -1)}}
  u=${DB_FORM_USER:-$(curl -s -b "$JAR" -c "$JAR" "$BASE/connect.php" | sed -n 's/.*name="userName" value="\([^"]*\)".*/\1/p' | head -1)}
  if [ "$2" = good ]; then printf '%s' "$DB_FORM_PASS"; else printf '%s' "$2"; fi > "$DIR/pw"
  CODE=$(curl -s -o "$OUT" -D "$HDR" -w '%{http_code}' -b "$JAR" -c "$JAR" --data-urlencode "_csrf=$t" \
         --data-urlencode "dbName=$n" --data-urlencode "userName=$u" --data-urlencode "pswd@$DIR/pw" "$BASE/connect.php"); }
login() {
  local t; t="$(token /login.php)"
  CODE=$(curl -s -o "$OUT" -D "$HDR" -w '%{http_code}' -b "$JAR" -c "$JAR" --data-urlencode "_csrf=$t" \
         --data-urlencode "email=$1" --data-urlencode "password=$PW" "$BASE/login.php"); }
cookie() { sed 's/^#HttpOnly_//' "$JAR" | grep -v '^#' | awk '$6=="MDMSSESSID"{print $7}' | tail -1; }   # HttpOnly cookies start with #HttpOnly_

: > "$JAR"
# --- not connected
get /login.php;   check "login page without a database login goes to the Connect page" '[ $CODE = 303 ] && [ "$(loc)" = "$P/connect.php?next=${EP}%2Flogin.php" ]'
get /register.php; check "registration too" '[ $CODE = 303 ] && loc | grep -q "^$P/connect.php?next="'
get /consumer/;   check "a protected page asks for the application login first" '[ $CODE = 303 ] && loc | grep -q "^$P/login.php?next="'
get /market/api/portfolio.php; check "a JSON endpoint answers 401 JSON" '[ $CODE = 401 ] && has "\"error\""'
get /connect.php; check "Connect page: the three Lab 7 fields, the password field empty" '[ $CODE = 200 ] && has "name=\"dbName\"" && has "name=\"userName\"" && has "name=\"pswd\"" && ! grep -q "name=\"pswd\"[^>]*value=" "$OUT"'
CODE=$(curl -s -o "$OUT" -w '%{http_code}' -b "$JAR" -c "$JAR" -d "dbName=x&userName=y&pswd=z" "$BASE/connect.php")
check "Connect without the form token is refused (403)" '[ $CODE = 403 ]'

# --- refused logins (2 attempts)
connect_as "" "wrong-password-$RANDOM"
check "wrong password: 401 and a clear message" '[ $CODE = 401 ] && has "Login failed: check the login name and the password." && nopw'
get /login.php;   check "... and still not connected" '[ $CODE = 303 ]'
connect_as "no_such_db_$RANDOM" good
check "right password, wrong database: 401 'cannot open the database', password not echoed" '[ $CODE = 401 ] && has "cannot open the database" && nopw'

# --- connect
before="$(cookie)"
connect_as "" good
check "right login: 303 back to the login page" '[ $CODE = 303 ] && [ "$(loc)" = "$P/login.php" ]'
check "a new session id after connecting" '[ -n "$(cookie)" ] && [ "$(cookie)" != "$before" ]'
get /login.php
check "login page now shows the database and a Disconnect button, never the password" '[ $CODE = 200 ] && has "Database: " && has "value=\"disconnect\"" && nopw'
get /connect.php; check "Connect page says connected" '[ $CODE = 200 ] && has "Connected to" && nopw'

# --- application logins on top of the database login
login consumer1@example.cy; check "consumer1 logs in" '[ $CODE = 303 ] && [ "$(loc)" = "$P/home.php" ]'
get /home.php;    check "home with the consumer menu" '[ $CODE = 200 ] && has "href=\"$P/consumer/\""'
get /consumer/;   check "a consumer page reads the database" '[ $CODE = 200 ] && ! has "Service problem"'
t="$(token /home.php)"; CODE=$(curl -s -o "$OUT" -D "$HDR" -w '%{http_code}' -b "$JAR" -c "$JAR" --data-urlencode "_csrf=$t" "$BASE/logout.php")
check "log out" '[ $CODE = 303 ] && [ "$(loc)" = "$P/login.php" ]'
get /login.php;   check "after log out the database login is kept (no Connect page)" '[ $CODE = 200 ] && has "name=\"email\""'
login tso@mdms.cy; check "another role logs in without typing the database password again" '[ $CODE = 303 ]'
get /tso/tree.php; check "tso page reads the database" '[ $CODE = 200 ] && ! has "Service problem"'

# --- disconnect (from the login page form after logging out)
t="$(token /home.php)"; curl -s -o /dev/null -b "$JAR" -c "$JAR" --data-urlencode "_csrf=$t" "$BASE/logout.php"
t="$(token /login.php)"; CODE=$(curl -s -o "$OUT" -D "$HDR" -w '%{http_code}' -b "$JAR" -c "$JAR" --data-urlencode "_csrf=$t" --data-urlencode "action=disconnect" "$BASE/connect.php")
check "Disconnect: 303 to the Connect page" '[ $CODE = 303 ] && [ "$(loc)" = "$P/connect.php" ]'
get /login.php;   check "after Disconnect the login page asks for the database again" '[ $CODE = 303 ] && loc | grep -q "^$P/connect.php"'

# --- off-site next is ignored
: > "$JAR"; t="$(token /connect.php)"; printf '%s' "$DB_FORM_PASS" > "$DIR/pw"
n=${DB_FORM_NAME:-$(curl -s -b "$JAR" -c "$JAR" "$BASE/connect.php" | sed -n 's/.*name="dbName" value="\([^"]*\)".*/\1/p' | head -1)}
u=${DB_FORM_USER:-$(curl -s -b "$JAR" -c "$JAR" "$BASE/connect.php" | sed -n 's/.*name="userName" value="\([^"]*\)".*/\1/p' | head -1)}
CODE=$(curl -s -o "$OUT" -D "$HDR" -w '%{http_code}' -b "$JAR" -c "$JAR" --data-urlencode "_csrf=$t" --data-urlencode "next=//evil.example/x" \
       --data-urlencode "dbName=$n" --data-urlencode "userName=$u" --data-urlencode "pswd@$DIR/pw" "$BASE/connect.php")
check "an off-site next after Connect is ignored" '[ $CODE = 303 ] && [ "$(loc)" = "$P/home.php" ]'

# --- throttle (optional, last)
if [ "${CONNECT_THROTTLE:-}" = 1 ]; then
  : > "$JAR"; for i in 1 2 3 4 5; do connect_as "" "wrong-$i-$RANDOM"; done
  connect_as "" "wrong-6-$RANDOM"; check "the 6th wrong password in 15 minutes is refused (429)" '[ $CODE = 429 ]'
fi

echo; echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ] && echo "connect.sh: all passed"
exit "$fail"
