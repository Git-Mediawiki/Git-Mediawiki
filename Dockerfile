#-*-tab-width: 4; fill-column: 76; whitespace-line-column: 77 -*-
# vi:shiftwidth=4 tabstop=4 textwidth=76

FROM debian:stretch-slim
RUN apt-get update -q
RUN apt-get install -y              \
	git                             \
	libdatetime-format-iso8601-perl \
	liblwp-protocol-https-perl      \
	libmediawiki-api-perl           \
	lighttpd						\
	make							\
	php-apcu						\
	php-gd							\
	php-cgi							\
	php-cli							\
	php-curl						\
	php-intl						\
	php-mbstring			        \
	php-sqlite3			        	\
	php-xml							\
	strace							\
	wget
COPY run.sh /
COPY Makefile /
ENTRYPOINT sh -x run.sh

