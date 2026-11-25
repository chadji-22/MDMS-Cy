#!/usr/bin/env bash
# MDMS-Cy: install OR update the web application on the department web server.
# 1. Upload mdms-app.zip and this file to your home folder (U:\ on a lab PC, NOT public_html).
# 2. In a terminal on a department Linux machine:   bash ~/install.sh
# 3. Open https://students.cs.ucy.ac.cy/~<your login>/mdms/
# Safe to run again for every new zip: your settings file and the uploaded files in ~/mdms/var are kept.
set -e
cd ~
[ -f mdms-app.zip ] || { echo "mdms-app.zip is not in your home folder: upload it first"; exit 1; }
unzip -o -q mdms-app.zip && rm mdms-app.zip

# code: readable by the web server (PHP runs as the user "apache", which is "other" to your files)
find ~/mdms -type d ! -path "$HOME/mdms/var*" -exec chmod 711 {} +
find ~/mdms/public -type d -exec chmod 755 {} +
chmod 755 ~/mdms/areas                                  # the menus are found by listing this folder
find ~/mdms -type f ! -path "$HOME/mdms/var/*" -exec chmod 644 {} +

# uploads: PHP may write, other accounts can neither list nor delete (sticky bit)
mkdir -p ~/mdms/var/throttle ~/mdms/var/technician-documents ~/mdms/var/technician-photos ~/mdms/var/meter-certificates
chmod 1733 ~/mdms/var ~/mdms/var/*

# settings (no password in them): created once from the sample, with your login in the URL
if [ ! -f ~/mdms/src/config.local.php ]; then
  sed "s/__USER__/$USER/" ~/mdms/src/config.ucy.sample.php > ~/mdms/src/config.local.php
fi
chmod 644 ~/mdms/src/config.local.php

# publish only ~/mdms/public, through a link in public_html (Lab 7 permissions)
chmod 701 ~
mkdir -p ~/public_html && chmod 755 ~/public_html
ln -sfn ~/mdms/public ~/public_html/mdms

echo "Done. Open https://students.cs.ucy.ac.cy/~$USER/mdms/"
