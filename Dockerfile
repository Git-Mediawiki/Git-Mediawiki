#-*-tab-width: 4; fill-column: 76; whitespace-line-column: 77 -*-
# vi:shiftwidth=4 tabstop=4 textwidth=76

FROM mediawiki:latest

RUN cd /var/www/html && mkdir -p /wiki/db && mkdir -p /files/Git			\
	chown www-data /wiki/db &&												\
	&& php maintenance/install.php --dbtype=sqlite --dbpath=/wiki/db		\
	--scriptpath=/ --pass=none123456 wiki admin
RUN git clone -b dockerized-testing											\
	https://github.com/hexmode/mediawikiapi/tree/dockerized-testing			\
	/files/MediaWiki

COPY Makefile /
COPY Git/* /files/Git/
COPY git-* /files/
RUN make -C / install DESTDIR=/files

ENTRYPOINT ["make",	"-f", "/Makefile"]
