#!/usr/bin/env bash
# I-05 on R: Connect + log in as consumer1, stay idle > 30 minutes, then open a menu page.
# Expected: the session is forgotten -> 303 to the login page, and the login page then asks for the Connect page.
# Usage (repository root, run it in the background): DB_FORM_PASS=... bash <this file> <BASE_URL> <out file> [idle seconds]
BASE="$1"; OUTF="$2"; IDLE="${3:-1900}"; PW='Passw0rd!23'
P=$(printf '%s' "$BASE" | sed -E 's#^https?://[^/]+##; s#/+$##')
DIR="$(mktemp -d)"; command -v cygpath > /dev/null && DIR="$(cygpath -m "$DIR")"; trap 'rm -rf "$DIR"' EXIT
JAR="$DIR/jar"; : > "$JAR"
. sources/tests/connect_lib.sh       # run from the repository root
log() { echo "$(date -u +%FT%TZ) $*" >> "$OUTF"; }
st()  { curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -b "$JAR" -c "$JAR" "$BASE$1"; }
{ echo "# I-05 idle timeout on R ($BASE), idle $IDLE s (SESSION_IDLE_MIN = 30)"
  echo "# DB_FORM_PASS=<not printed> bash i05_idle.sh $BASE <out> $IDLE"; } > "$OUTF"
dbconnect
t=$(curl -s -b "$JAR" -c "$JAR" "$BASE/login.php" | sed -n 's/.*name="_csrf" value="\([^"]*\)".*/\1/p' | head -1)
c=$(curl -s -o /dev/null -w '%{http_code}' -b "$JAR" -c "$JAR" --data-urlencode "_csrf=$t" \
     --data-urlencode "email=consumer1@example.cy" --data-urlencode "password=$PW" "$BASE/login.php")
log "connect + login consumer1: $c (expect 303)"
before=$(st /consumer/); log "GET /consumer/ before idle: $before (expect 200)"
log "sleeping $IDLE s"; sleep "$IDLE"
after=$(st /consumer/events.php); log "GET /consumer/events.php after idle: $after (expect 303 -> $P/login.php?next=...)"
lp=$(st /login.php); log "GET /login.php after idle: $lp (expect 303 -> $P/connect.php...: database login forgotten too)"
if [ "$c" = 303 ] && [ "${before%% *}" = 200 ] && [[ "$after" == "303 "*"$P/login.php?next="* ]] && [[ "$lp" == "303 "*"$P/connect.php"* ]]; then
  log "RESULT I-05: PASS"; else log "RESULT I-05: FAIL"; fi
