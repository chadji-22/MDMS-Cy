# Sourced by the HTTP tests. Support for the Connect page (an instance without DB_PASS in its settings, e.g. the
# department web server): with DB_FORM_PASS set, dbconnect logs the cookie jar $JAR into the database first.
# DB_FORM_NAME / DB_FORM_USER default to the values the page pre-fills (DB_NAME / DB_USER of the settings).
# The password goes to curl through a pipe, so it is never on a command line or in the output.
# Without DB_FORM_PASS, dbconnect does nothing and the tests run as before.
dbconnect() {
  [ -n "${DB_FORM_PASS:-}" ] || return 0
  local page t n u
  page=$(curl -s -b "$JAR" -c "$JAR" "$BASE/connect.php")
  t=$(printf '%s' "$page" | sed -n 's/.*name="_csrf" value="\([^"]*\)".*/\1/p' | head -1)
  n=${DB_FORM_NAME:-$(printf '%s' "$page" | sed -n 's/.*name="dbName" value="\([^"]*\)".*/\1/p' | head -1)}
  u=${DB_FORM_USER:-$(printf '%s' "$page" | sed -n 's/.*name="userName" value="\([^"]*\)".*/\1/p' | head -1)}
  printf '%s' "$DB_FORM_PASS" | curl -s -o /dev/null -b "$JAR" -c "$JAR" --data-urlencode "_csrf=$t" \
    --data-urlencode "dbName=$n" --data-urlencode "userName=$u" --data-urlencode "pswd@-" "$BASE/connect.php"
}
