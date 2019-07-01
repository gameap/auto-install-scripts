#!/usr/bin/env bash

set -u
set -e
shopt -s dotglob

echo
echo "Start building"
echo "Web-server: ${WEB_SERVER}"
echo "Database: ${DATABASE}"
echo

echo "127.0.0.1 test.gameap" > /etc/hosts
./debian/install-en.sh --github --path=/var/www/gameap --host=test.gameap --web-server=${WEB_SERVER} --database=${DATABASE}

echo
echo "Checking available gameap host"
echo
curl -sL -w "HTTP CODE: %{http_code}\\n" "http://test.gameap/login" -o /dev/null

echo
echo "Checking GameAP Daemon installation"

echo "Illuminate\Support\Facades\Cache::put('gdaemonAutoSetupToken', 'fake', 300);" | /var/www/gameap/artisan tinker
export createToken=fake; export panelHost=http://test.gameap; ./debian/install-gdaemon-en.sh