#!/usr/bin/env bash
# MDMS-Cy: install OR update the web application on the department web server.
# 1. Remote Desktop to a Linux lab machine; copy mdms-app.zip and this file into your home folder (NOT public_html).
# 2. Either leave the zip there, or extract it yourself in the home folder (it creates ~/mdms).
# 3. In a terminal:   bash ~/install.sh          then open https://students.cs.ucy.ac.cy/~<your login>/mdms/
# Safe to run again for every new zip: your settings file and the uploaded files in ~/mdms/var are kept.
set -e
cd ~
if [ -f mdms-app.zip ]; then
  unzip -o -q mdms-app.zip && rm mdms-app.zip
elif [ -d ~/mdms/public ] && [ -d ~/mdms/src ]; then
  echo "No mdms-app.zip in your home folder: using the ~/mdms you extracted, setting its permissions"
else
  echo "Neither mdms-app.zip nor an extracted ~/mdms is in your home folder: copy the zip there first"; exit 1
fi

# code: readable by the web server (PHP runs as the user "apache", which is "other" to your files)
find ~/mdms -type d ! -path "$HOME/mdms/var*" -exec chmod 711 {} +
find ~/mdms/public -type d -exec chmod 755 {} +
chmod 755 ~/mdms/areas                                  # the menus are found by listing this folder
find ~/mdms -type f ! -path "$HOME/mdms/var/*" -exec chmod 644 {} +

# give the code today's date: the zip stores every file with one fixed date (build_zip.py), and the server's PHP OPcache
# only compiles a file again when its date changes, so without this a changed page keeps running the old cached code
find ~/mdms -name '*.php' ! -path "$HOME/mdms/var/*" -exec touch {} +

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
