#!/usr/bin/env bash
# Runs every HTTP test against one running instance and prints a summary.
#   BASE_URL=http://localhost:8080 bash tests/run_all.sh                          read-only suites
#   BASE_URL=http://localhost:8080 WRITE=1 bash tests/run_all.sh                  + the write flows (OWN database only)
#   BASE_URL=https://students.cs.ucy.ac.cy/~login/mdms DB_FORM_PASS=... bash tests/run_all.sh   (Connect page)
# WRITE=1 changes data and accounts.sh creates users: never against the shared course database.
# smoke.sh makes failed logins on purpose: more than 3 runs in 15 minutes trip the login lock (wait 15 minutes).
cd "$(dirname "$0")/.." || exit 2
BASE="${BASE_URL:-http://localhost:8080}"
results=()
run() {   # $1 name, then the command
  local name="$1"; shift
  echo; echo "===== $name"
  local log; log="$("$@" 2>&1)"; local code=$?
  printf '%s\n' "$log" | grep -E "^FAIL|passed|failed|pages, |problems" | tail -12
  results+=("$(printf '%-20s %s' "$name" "$([ $code -eq 0 ] && echo PASS || echo "FAIL (exit $code)")")")
}

echo "Target: $BASE   WRITE=${WRITE:-0}   Connect page: $([ -n "${DB_FORM_PASS:-}" ] && echo yes || echo no)"
run smoke.sh           bash tests/smoke.sh
[ -n "${DB_FORM_PASS:-}" ] && run connect.sh bash tests/connect.sh
run consumer_pages.sh  bash tests/consumer_pages.sh
run market_dso_tso.sh  bash tests/market_dso_tso.sh
if [ "${WRITE:-}" = 1 ]; then run accounts.sh bash tests/accounts.sh; else results+=("$(printf '%-20s %s' accounts.sh 'skipped (needs WRITE=1: creates users)')"); fi
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' 2>/dev/null; then PY=python3; else PY=python; fi
run crawl_links.py     "$PY" tests/crawl_links.py "$BASE"

echo; echo "===== summary"; printf '%s\n' "${results[@]}"
! printf '%s\n' "${results[@]}" | grep -q "FAIL"
