#
# Copyright (C) 2013
#     Matthieu Moy <Matthieu.Moy@imag.fr>
#
# To build and test:
#
#   make
#   bin-wrapper/git mw preview Some_page.mw
#   bin-wrapper/git clone mediawiki::http://example.com/wiki/
#
# To install, run Git's toplevel 'make install' then run:
#
#   make install
mkfilePath := $(abspath $(lastword $(MAKEFILE_LIST)))
mkfileDir := $(patsubst %/,%,$(dir $(mkfilePath)))

CMD ?= test
PREFIX ?= /usr
files ?= ${mkfileDir}/files
GIT_MEDIAWIKI_PM=Git/Mediawiki.pm
SCRIPT_PERL=${files}/git-remote-mediawiki
SCRIPT_PERL+=${files}/git-mw

INSTALL = install

SCRIPT_PERL_FULL=$(patsubst %,$(shell pwd)/%,$(SCRIPT_PERL))
INSTLIBDIR=$(PREFIX)/share/perl5/
DESTDIR_SQ = $(subst ','\'',$(DESTDIR))
INSTLIBDIR_SQ = $(subst ','\'',$(INSTLIBDIR))

test:
	$(MAKE) -C /t
#/usr/local/lib/perl5/site_perl/5.30.0/DateTime/Format/ISO8601.pm

check: perlcritic test

install_pm:
	$(INSTALL) -d -m 755 '$(DESTDIR_SQ)$(INSTLIBDIR_SQ)Git'
	cd ${files} && $(INSTALL) -m 644 $(GIT_MEDIAWIKI_PM) \
		'$(DESTDIR_SQ)$(INSTLIBDIR_SQ)/$(GIT_MEDIAWIKI_PM)'

install: install_pm
	$(INSTALL) $(SCRIPT_PERL) $(DESTDIR)$(PREFIX)/lib/git-core/

perlcritic:
	perlcritic -5 $(SCRIPT_PERL)
	-perlcritic -2 $(SCRIPT_PERL)

dockerBuild:
	docker build -t mabs .

docker:
	docker run -v `pwd`/WEB:/WEB -v `pwd`/t:/t mabs ${CMD}

.PHONY: all test check install_pm install clean perlcritic
