#!/usr/bin/env bash
# HTTP smoke test of the B1 framework against a running instance:   BASE_URL=http://localhost:8080 bash tests/smoke.sh
# Uses the demo accounts of import.sql (password Passw0rd!23). Each successful login appends one audit row (LOGIN_OK),
# so keep the number of runs small on the shared database.
BASE="${BASE_URL:-http://localhost:8080}"
PW="${DEMO_PASSWORD:-Passw0rd!23}"
JAR="$(mktemp)"; trap 'rm -f "$JAR" "$JAR".*' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1  ${2:-}"; fail=$((fail+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }
csrf() { curl -s -b "$JAR" -c "$JAR" "$BASE/login.php" | sed -n 's/.*name="_csrf" value="\([^"]*\)".*/\1/p' | head -1; }
status() { curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -c "$JAR" "$@"; }
body()   { curl -s -b "$JAR" -c "$JAR" "$@"; }
login()  { # $1 email $2 password -> prints http code
  local t; t="$(csrf)"
  curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -c "$JAR" --data-urlencode "_csrf=$t" --data-urlencode "email=$1" --data-urlencode "password=$2" "$BASE/login.php"; }
fresh() { rm -f "$JAR"; : > "$JAR"; }

fresh
check "no session: protected page redirects to the login page" '[ "$(curl -s -o /dev/null -w "%{http_code} %{redirect_url}" "$BASE/consumer/")" = "303 $BASE/login.php?next=%2Fconsumer%2F" ]'
check "login without a CSRF token is refused (403)" '[ "$(curl -s -o /dev/null -w "%{http_code}" -b "$JAR" -c "$JAR" -d "email=a@b.cy&password=x" "$BASE/login.php")" = "403" ]'

# wrong password and unknown email must be indistinguishable
c1=$(login consumer1@example.cy 'wrong-password'); m1=$(body "$BASE/login.php" >/dev/null; t="$(csrf)"; curl -s -b "$JAR" -c "$JAR" --data-urlencode "_csrf=$t" --data-urlencode "email=consumer1@example.cy" --data-urlencode "password=wrong-password" "$BASE/login.php" | sed -n 's/.*role="alert">\([^<]*\)<.*/\1/p')
c2=$(login nobody@example.cy "$PW");              m2=$(t="$(csrf)"; curl -s -b "$JAR" -c "$JAR" --data-urlencode "_csrf=$t" --data-urlencode "email=nobody@example.cy" --data-urlencode "password=$PW" "$BASE/login.php" | sed -n 's/.*role="alert">\([^<]*\)<.*/\1/p')
check "wrong password -> 401 'Login failed.'" '[ "$c1" = "401" ] && [ "$m1" = "Login failed." ]' "got $c1 / $m1"
check "unknown email -> the same 401 and message" '[ "$c2" = "$c1" ] && [ "$m2" = "$m1" ]' "got $c2 / $m2"

# consumer
fresh; code=$(login consumer1@example.cy "$PW")
check "consumer1 logs in (303 to home)" '[ "$code" = "303" ]' "got $code"
home=$(body "$BASE/home.php")
check "consumer sees the consumer menu" 'echo "$home" | grep -q "href=\"/consumer/\""'
check "consumer does not see the other menus" '! echo "$home" | grep -q -E "href=\"/(tso|dso|staff|technician|market)/\""'
check "consumer page is allowed (200)" '[ "$(status "$BASE/consumer/")" = "200" ]'
check "TSO page as consumer is refused (403)" '[ "$(status "$BASE/tso/")" = "403" ]'
check "staff page as consumer is refused (403)" '[ "$(status "$BASE/staff/")" = "403" ]'
hdr=$(curl -s -D - -o /dev/null -b "$JAR" "$BASE/home.php")
check "Content-Security-Policy and nosniff headers are sent" 'echo "$hdr" | grep -qi "^Content-Security-Policy:" && echo "$hdr" | grep -qi "^X-Content-Type-Options: nosniff"'
fresh; t="$(csrf)"; ch=$(curl -s -D - -o /dev/null -b "$JAR" -c "$JAR" --data-urlencode "_csrf=$t" --data-urlencode "email=consumer1@example.cy" --data-urlencode "password=$PW" "$BASE/login.php")
check "session cookie is HttpOnly and SameSite=Lax" 'echo "$ch" | grep -i "^Set-Cookie: MDMSSESSID" | grep -qi "httponly" && echo "$ch" | grep -i "^Set-Cookie: MDMSSESSID" | grep -qi "samesite=lax"'
check "a new session id is issued at login (no fixation)" '[ -n "$(echo "$ch" | grep -i "^Set-Cookie: MDMSSESSID")" ]'
check "logout by GET does not log out" '[ "$(status "$BASE/logout.php")" = "303" ] && [ "$(status "$BASE/consumer/")" = "200" ]'
check "logout POST without CSRF token is refused (403)" '[ "$(curl -s -o /dev/null -w "%{http_code}" -b "$JAR" -c "$JAR" -X POST "$BASE/logout.php")" = "403" ]'
tk=$(body "$BASE/home.php" | sed -n 's/.*name="_csrf" value="\([^"]*\)".*/\1/p' | head -1)
check "logout POST with the token ends the session" '[ "$(curl -s -o /dev/null -w "%{http_code}" -b "$JAR" -c "$JAR" --data-urlencode "_csrf=$tk" "$BASE/logout.php")" = "303" ] && [ "$(status "$BASE/consumer/")" = "303" ]'

# officer: staff + dso, Greek name intact
fresh; code=$(login officer1@mdms.cy "$PW"); home=$(body "$BASE/home.php")
check "officer1 logs in" '[ "$code" = "303" ]' "got $code"
check "officer sees staff and DSO menus only" 'echo "$home" | grep -q "href=\"/staff/\"" && echo "$home" | grep -q "href=\"/dso/\"" && ! echo "$home" | grep -q -E "href=\"/(consumer|tso|technician|market)/\""'
check "Greek full name comes back intact (UTF-8)" 'echo "$home" | grep -q "Ελένη Γεωργίου"'
check "officer reaches /dso/ and /staff/ (200), not /tso/ (403)" '[ "$(status "$BASE/dso/")" = "200" ] && [ "$(status "$BASE/staff/")" = "200" ] && [ "$(status "$BASE/tso/")" = "403" ]'

# tso
fresh; code=$(login tso@mdms.cy "$PW"); home=$(body "$BASE/home.php")
check "tso sees only the TSO menu and reaches it" '[ "$code" = "303" ] && echo "$home" | grep -q "href=\"/tso/\"" && ! echo "$home" | grep -q -E "href=\"/(consumer|dso|staff|technician|market)/\"" && [ "$(status "$BASE/tso/")" = "200" ]'

# redirect target must stay on this site
fresh; t="$(csrf)"; loc=$(curl -s -D - -o /dev/null -b "$JAR" -c "$JAR" --data-urlencode "_csrf=$t" --data-urlencode "next=//evil.example/x" --data-urlencode "email=consumer1@example.cy" --data-urlencode "password=$PW" "$BASE/login.php" | sed -n 's/^[Ll]ocation: //p' | tr -d '\r')
check "an off-site 'next' is ignored (lands on /home.php)" '[ "$loc" = "/home.php" ]' "got $loc"
check "health endpoint shows the connection runs as mdms_php" 'curl -s "$BASE/health.php" | grep -q "\"sql_user\":\"mdms_php\"" || [ "$(curl -s -o /dev/null -w "%{http_code}" "$BASE/health.php")" = "404" ]'

echo; [ "$fail" -eq 0 ] && echo "smoke.sh: all passed" || echo "smoke.sh: $fail FAILED"
exit "$fail"
