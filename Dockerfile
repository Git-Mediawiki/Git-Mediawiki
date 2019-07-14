#-*-tab-width: 4; fill-column: 76; whitespace-line-column: 77 -*-
# vi:shiftwidth=4 tabstop=4 textwidth=76

FROM perl-php-git

ENV MWURL=https://releases.wikimedia.org/mediawiki/1.33/mediawiki-1.33.0.tar.gz

RUN mkdir -p /wiki/var/lighttpd					\
	/wiki/db /wiki/www /wiki/log &&				\
	chmod 1777 /wiki/db /wiki/log				\
	/wiki/var/lighttpd

RUN wget -O /wiki/mediawiki.tar.gz ${MWURL}		\
	&& tar -C /wiki/www --strip-components=1 -xzf /wiki/mediawiki.tar.gz

RUN cd /wiki/www								\
	&& php maintenance/install.php				\
		--dbtype=sqlite --dbpath=/wiki/db		\
		--scriptpath=/ --pass=none1234			\
		wiki admin

COPY Makefile /
COPY Git/* /files/Git/
COPY git-* /files/
RUN make -C / install files=/files

ENTRYPOINT ["make",	"-f", "/Makefile"]
