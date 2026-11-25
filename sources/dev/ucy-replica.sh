#!/usr/bin/env bash
# Replica of students.cs.ucy.ac.cy for testing deploy/mdms-app.zip BEFORE it goes to the real server:
# PHP 8.0.30 + sqlsrv 5.11, Apache with mod_userdir (~user/public_html), PHP running as another user than the owner of
# the files (like "apache"), no ACLs, the app installed by deploy/install.sh exactly as on the server, no password on disk.
#
# Needs: Podman (or Docker with "podman" aliased), the local SQL Server container of the README (network mdms-net) with
# the MDMS build, and the image:   podman build -t mdms-php80 -f sources/dev/Containerfile.php80 sources/dev
# Usage (from the repository root, Git Bash: prefix MSYS_NO_PATHCONV=1):
#   python deploy/build_zip.py
#   DB_HOST=mdms-sql DB_NAME=mdms DB_USER=mdms_web bash sources/dev/ucy-replica.sh [port, default 8090]
#   DB_FORM_PASS=<that login's password> BASE_URL=http://127.0.0.1:8090/~student/mdms WRITE=1 bash sources/tests/run_all.sh
# Remove it afterwards with:   podman rm -f mdms-ucy-replica
set -e
PORT="${1:-8090}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
command -v cygpath >/dev/null && ROOT="$(cygpath -m "$ROOT")"
[ -f "$ROOT/deploy/mdms-app.zip" ] || { echo "build the zip first: python deploy/build_zip.py"; exit 1; }
: "${DB_HOST:?set DB_HOST (e.g. mdms-sql)}" "${DB_NAME:?set DB_NAME}" "${DB_USER:?set DB_USER}"

podman run -d --name mdms-ucy-replica --network mdms-net -p "127.0.0.1:$PORT:80" \
  -v "$ROOT/deploy:/pkg:ro" \
  -e DB_HOST="$DB_HOST" -e DB_NAME="$DB_NAME" -e DB_USER="$DB_USER" -e APACHE_DOCUMENT_ROOT=/var/www/empty \
  --entrypoint sh localhost/mdms-php80 -c '
set -e
apt-get update -qq >/dev/null && apt-get install -y -qq --no-install-recommends unzip >/dev/null
groupadd -g 2024 cs24 && useradd -u 10027 -g cs24 -m -d /home/student -s /bin/bash student
cp /pkg/mdms-app.zip /pkg/install.sh /home/student/ && chown student:cs24 /home/student/mdms-app.zip /home/student/install.sh
su student -c "bash ~/install.sh"
a2enmod -q userdir && mkdir -p /var/www/empty
exec docker-php-entrypoint apache2-foreground' >/dev/null
echo "starting...";
until podman logs mdms-ucy-replica 2>&1 | grep -qE "resuming normal operations|rror"; do sleep 2; done
podman logs mdms-ucy-replica 2>&1 | grep -E "^Done|rror" || true
echo "Replica: http://127.0.0.1:$PORT/~student/mdms/   (DB_PASS is not set: use the Connect page / DB_FORM_PASS)"
