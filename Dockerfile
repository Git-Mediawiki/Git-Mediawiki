#-*-tab-width: 4; fill-column: 76; whitespace-line-column: 77 -*-
# vi:shiftwidth=4 tabstop=4 textwidth=76

FROM perl-php-git

ARG MW_VERSION_MAJOR=1.33
ARG MW_VERSION_MINOR=0
ARG MW_TGZ=mediawiki-${MW_VERSION_MAJOR}.${MW_VERSION_MINOR}.tar.gz
ARG MW_URLBASE=https://releases.wikimedia.org/mediawiki
ARG MW_URL=${MW_URLBASE}/${MW_VERSION_MAJOR}/${MW_TGZ}

RUN mkdir -p /wiki/var/lighttpd	/wiki/db /wiki/www /wiki/log &&	\
	chmod 1777 /wiki/db /wiki/log /wiki/var/lighttpd

RUN wget -O /wiki/db/${MW_TGZ} ${MW_URL}						\
	&& tar -C /wiki/www --strip-components=1 -xzf /wiki/db/${MW_TGZ}

RUN cd /wiki/www												\
	&& php maintenance/install.php --dbtype=sqlite				\
		--dbpath=/wiki/db --scriptpath=/ --pass=none1234		\
		wiki admin

COPY Makefile /
COPY Git/* /files/Git/
COPY git-* /files/
RUN make -C / install files=/files

ENTRYPOINT ["make",	"-f", "/Makefile"]
