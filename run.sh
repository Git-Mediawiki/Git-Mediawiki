#!/bin/sh -e

mkdir -p /WEB/var/lighttpd /WEB/db /WEB/www/ /WEB/var/lighttpd/ /WEB/log
chmod 1777 /WEB/db /WEB/var/lighttpd/ /WEB/log

cd /WEB
test -f mediawiki-1.32.1.tar.gz || wget https://releases.wikimedia.org/mediawiki/1.32/mediawiki-1.32.1.tar.gz
cd /WEB/www/
test -f index.php || tar --strip-components=1 -xzf /WEB/mediawiki-1.32.1.tar.gz
test -f LocalSettings.php || php maintenance/install.php --dbtype=sqlite --dbpath=/WEB/db --scriptpath= --pass=none1234 wiki admin
cd /
make test
