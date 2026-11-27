#!/usr/bin/env bash
# HTTP test of task B2 (registration, profile, password, technician documents) against a running instance:
#     BASE_URL=http://localhost:8080 bash tests/accounts.sh
# Every run creates one consumer and one technician that stay in the database (users are never deleted): run it on your
# own database, not on the shared one.
BASE="${BASE_URL:-http://localhost:8080}"
# the application may be served from a sub-folder (BASE_PATH): P is the path part of BASE_URL, EP the same URL-encoded
P=$(printf '%s' "$BASE" | sed -E 's#^https?://[^/]+##; s#/+$##'); EP=$(printf '%s' "$P" | sed 's#/#%2F#g')
DIR="$(mktemp -d)"; command -v cygpath > /dev/null && DIR="$(cygpath -m "$DIR")"; trap 'rm -rf "$DIR"' EXIT
JAR="$DIR/jar"; OUT="$DIR/out"; RUN="$(date +%s)$RANDOM"
. "$(dirname "$0")/connect_lib.sh"   # dbconnect: the Connect page, when DB_FORM_PASS is set
PW='Κωδικός 12!'; PW2='Another-pass-34'
fail=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1  (code $CODE) $(grep -o 'role="alert">[^<]*' "$OUT" | tr '\n' ' ')"; fail=$((fail+1)); fi; }
get()   { CODE=$(curl -s -o "$OUT" -w '%{http_code}' -b "$JAR" -c "$JAR" "$BASE$1"); }
token() { curl -s -b "$JAR" -c "$JAR" "$BASE$1" | sed -n 's/.*name="_csrf" value="\([^"]*\)".*/\1/p' | head -1; }
post()  {  # $1 page, then --form-string name=value / -F name=@file. Values go through files: curl.exe would damage Greek arguments
  local page="$1" t args=() n=0; shift; t="$(token "$page")"
  while [ $# -gt 0 ]; do
    if [ "$1" = --form-string ]; then n=$((n+1)); printf '%s' "${2#*=}" > "$DIR/v$n"; args+=(-F "${2%%=*}=<$DIR/v$n"); else args+=("$1" "$2"); fi; shift 2
  done
  CODE=$(curl -s -o "$OUT" -D "$DIR/hdr" -w '%{http_code}' -b "$JAR" -c "$JAR" -F "_csrf=$t" "${args[@]}" "$BASE$page"); }
to()    { [ "$CODE" = 303 ] && tr -d '' < "$DIR/hdr" | grep -qix -- "location: $P$1"; }   # redirected exactly there ($1 is an application path)
fresh() { rm -f "$JAR"; : > "$JAR"; dbconnect; }
login() { post /login.php --form-string "email=$1" --form-string "password=$2"; }
has()   { grep -qF -- "$1" "$OUT"; }

printf '%%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%%%EOF\n' > "$DIR/doc.pdf"
printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==' | base64 -d > "$DIR/photo.png"
printf '<?php echo 1; ?>' > "$DIR/evil.png"
head -c 2500000 /dev/zero > "$DIR/big.pdf"

# --- consumer registration
C="c$RUN@test.cy"
reg() { post /register.php --form-string "email=$C" --form-string 'full_name=Δοκιμή <script>' --form-string 'phone=+357 99123456' \
        --form-string 'iban=cy17 0020 0128 0000 0012 0052 7600' --form-string "password=$PW" --form-string "password2=$PW" --form-string 'notify_email=1' "$@"; }
fresh
get /login.php;  check "the login page links to both registrations" 'has /register.php && has /register-technician.php'
CODE=$(curl -s -o "$OUT" -w '%{http_code}' -b "$JAR" -c "$JAR" --form-string 'email=x@y.cy' "$BASE/register.php"); check "registration without a CSRF token is refused" '[ $CODE = 403 ]'
post /register.php --form-string 'email=bad' --form-string 'full_name= ' --form-string 'phone=abc' --form-string 'iban=1' --form-string 'password=short' --form-string 'password2=short'
check "bad input: 422 and one message per field" '[ $CODE = 422 ] && [ $(grep -o "role=\"alert\"" "$OUT" | wc -l) = 5 ]'
check "a password is never sent back to the browser" '! has "value=\"short\""'
post /register.php --form-string "email=$C" --form-string 'full_name=A' --form-string 'phone=99123456' --form-string 'iban=CY17002001280000001200527600' --form-string "password=$PW" --form-string 'password2=different-1'
check "different repeated password is refused" '[ $CODE = 422 ] && has "not the same"'
LONG=$(printf 'Ω%.0s' $(seq 129))
post /register.php --form-string "email=$C" --form-string 'full_name=A' --form-string 'phone=99123456' --form-string 'iban=CY17002001280000001200527600' --form-string "password=$LONG" --form-string "password2=$LONG"
check "a password the login would refuse (> 128 characters) is refused at registration" '[ $CODE = 422 ] && has "too long"'
post /register.php --form-string 'email[]=x' --form-string 'full_name[]=x' --form-string 'password[]=x'
check "array parameters are handled (422, no server error)" '[ $CODE = 422 ]'
reg;             check "a valid consumer is created (303 to the login page)" 'to /login.php'
get /login.php;  check "...and the success message is shown" 'has "Your account was created"'
reg;             check "the same email again: 409 duplicate" '[ $CODE = 409 ] && has "already registered"'
login "$C" "$PW"; check "the new consumer logs in with a Greek password" 'to /home.php'
get /register.php; check "a logged-in user is sent away from the registration" '[ $CODE = 303 ]'

# --- profile
get /account/profile.php
check "profile: own email and IBAN (spaces removed, upper case)" '[ $CODE = 200 ] && has "$C" && has "CY17002001280000001200527600"'
check "profile: the name is escaped (no script tag)" 'has "&lt;script&gt;" && ! has "<script>"'
check "profile: no password or hash in the page" '! grep -qi "hash\|salt" "$OUT"'
check "profile: notification choices kept (email yes, SMS no)" 'grep -q "name=\"notify_email\" value=\"1\" checked" "$OUT" && ! grep -q "name=\"notify_sms\" value=\"1\" checked" "$OUT"'
post /account/profile.php --form-string 'full_name=Νέο Όνομα' --form-string 'phone=99000111' --form-string 'iban=CY60002001280000001200527699' --form-string 'notify_sms=1' --form-string 'user_id=1' --form-string 'actor_user_id=1'
check "profile saved (303)" 'to /account/profile.php'
get /account/profile.php; check "profile: new values and header name shown, notification choices swapped" 'has "Νέο Όνομα ·" && has 99000111 && has 527699 && grep -q "name=\"notify_sms\" value=\"1\" checked" "$OUT" && ! grep -q "name=\"notify_email\" value=\"1\" checked" "$OUT"'
post /account/profile.php --form-string 'full_name=' --form-string 'phone=x' --form-string 'iban=x'; check "profile: bad input is 422" '[ $CODE = 422 ]'
post /account/profile.php --form-string 'full_name=Νέο Όνομα' --form-string 'phone=99000111' --form-string 'iban=CY17002001280000001200527699'
check "profile: an IBAN with wrong check digits is refused (422)" '[ $CODE = 422 ] && has "check digits"'
get /account/profile.php; check "...and the saved IBAN is unchanged" 'has "CY60002001280000001200527699"'
post /account/profile.php --form-string 'full_name=Νέο Όνομα' --form-string 'phone=99000111' --form-string 'iban=CY6000200128000000120052769'
check "profile: a Cyprus IBAN of 27 characters is refused (422)" '[ $CODE = 422 ]'
get /account/documents.php; check "the documents page is refused to a consumer (403)" '[ $CODE = 403 ]'
get /account/photo.php;     check "the photo page is refused to a consumer (403)" '[ $CODE = 403 ]'

# --- password
post /account/password.php --form-string 'old_password=wrong-one-1' --form-string "password=$PW2" --form-string "password2=$PW2"; check "wrong current password: 422 and a clear message" '[ $CODE = 422 ] && has "current password is not correct"'
post /account/password.php --form-string "old_password=$PW" --form-string "password=$PW" --form-string "password2=$PW"; check "the same password again is refused" '[ $CODE = 422 ] && has "must be different"'
post /account/password.php --form-string "old_password=$PW" --form-string "password=$PW2" --form-string "password2=$PW2"; check "password changed (303) with a new session id" 'to /account/profile.php && grep -qi "^set-cookie: MDMSSESSID" "$DIR/hdr"'
get /account/profile.php; check "...the session goes on" '[ $CODE = 200 ]'
fresh; login "$C" "$PW";  check "the old password no longer works" '[ $CODE = 401 ]'
fresh; login "$C" "$PW2"; check "the new password works" 'to /home.php'

# --- technician registration
T="t$RUN@test.cy"
regt() { post /register-technician.php --form-string "email=$T" --form-string 'full_name=Τεχνικός Δοκιμής' --form-string 'phone=99123456' --form-string "birth_date=$1" \
         --form-string 'specialty=Τηλεπικοινωνίες' --form-string "password=$PW" --form-string "password2=$PW" -F "photo=@$2"; }
fresh
regt 1990-05-05 "$DIR/evil.png";  check "a PHP file named .png is refused as a photo" '[ $CODE = 422 ] && has "must be JPG or PNG"'
regt 1990-02-30 "$DIR/photo.png"; check "a date that does not exist is refused" '[ $CODE = 422 ] && has "valid birth date"'
regt 2020-01-01 "$DIR/photo.png"; check "under 18: the message of the database is shown" '[ $CODE = 422 ] && has "18 years"'
regt 1990-05-05 "$DIR/photo.png"; check "a valid technician is registered (303)" 'to "/login.php?next=${EP}%2Faccount%2Fdocuments.php"'
login "$T" "$PW";                 check "the pending technician can log in" 'to /home.php'
get /home.php;                    check "home says the registration is PENDING" 'has PENDING'
get /account/photo.php;           check "the own photo is served as an image" '[ $CODE = 200 ] && cmp -s "$OUT" "$DIR/photo.png"'
get /account/documents.php;       check "all three documents are missing" 'has "Identity card, Installer licence, Training certificate."'

# --- documents
doc() { post /account/documents.php --form-string action=add --form-string "doc_type=$1" --form-string "doc_code=$2" --form-string "issue_date=$3" --form-string "expiry_date=$4" -F "file=@$5"; }
doc ID_CARD "ID$RUN" 2024-01-01 2023-01-01 "$DIR/doc.pdf";   check "expiry before issue is refused" '[ $CODE = 422 ] && has "before the issue date"'
doc ID_CARD "ID$RUN" 2024-01-01 2034-01-01 "$DIR/photo.png"; check "a file that is not a PDF is refused" '[ $CODE = 422 ] && has "must be PDF"'
doc ID_CARD "ID$RUN" 2024-01-01 2034-01-01 "$DIR/big.pdf";   check "a file over 2 MB is refused" '[ $CODE = 422 ] && has "larger than 2 MB"'
doc CE_DECLARATION "ID$RUN" 2024-01-01 '' "$DIR/doc.pdf";    check "a meter certificate type is refused" '[ $CODE = 422 ] && has "document type"'
doc ID_CARD "ID$RUN" 2024-01-01 2034-01-01 "$DIR/doc.pdf";   check "identity card uploaded (303)" 'to /account/documents.php'
doc ID_CARD "ID$RUN" 2024-01-01 2034-01-01 "$DIR/doc.pdf";   check "the same document number again: 409" '[ $CODE = 409 ] && has Duplicate'
doc INSTALLER_LICENSE "LIC$RUN" 2024-01-01 '' "$DIR/doc.pdf"; check "installer licence without expiry uploaded (303)" 'to /account/documents.php'
doc TRAINING_CERT "TRN$RUN" 2024-01-01 '' "$DIR/doc.pdf";    check "training certificate uploaded (303)" 'to /account/documents.php'
get /account/documents.php; check "three PENDING documents, nothing missing, no file path shown" '[ $(grep -c "<td>PENDING</td>" "$OUT") = 3 ] && ! has "Still missing" && ! has technician-documents/'
post /account/documents.php --form-string action=resubmit --form-string document_id=1 --form-string issue_date=2024-01-01 -F "file=@$DIR/doc.pdf"; check "another person's document cannot be replaced" '[ $CODE = 403 ]'
post /account/documents.php --form-string action=reapply; check "apply again is refused while PENDING (409)" '[ $CODE = 409 ]'
CODE=$(curl -s -o "$OUT" -w '%{http_code}' "$BASE/account/profile.php"); check "no session: the profile redirects to the login" '[ $CODE = 303 ]'

echo; [ "$fail" -eq 0 ] && echo "accounts.sh: all passed" || echo "accounts.sh: $fail FAILED"
exit "$fail"
