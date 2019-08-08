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
GIT_MEDIAWIKI_PM=Git/MediaWiki.pm
SCRIPT_PERL=${files}/git-remote-mediawiki
SCRIPT_PERL+=${files}/git-mw
MW_VERSION_MAJOR ?= 1.33
MW_VERSION_MINOR ?= 0
MW_TGZ ?= mediawiki-${MW_VERSION_MAJOR}.${MW_VERSION_MINOR}.tar.gz
MW_URLBASE ?= https://releases.wikimedia.org/mediawiki
MW_URL ?= ${MW_URLBASE}/${MW_VERSION_MAJOR}/${MW_TGZ}

INSTALL = install

SCRIPT_PERL_FULL=$(patsubst %,$(shell pwd)/%,$(SCRIPT_PERL))
INSTLIBDIR=$(PREFIX)/share/perl5/

test:
	echo running target ${CMD}
	$(MAKE) -C /t $(if ${T},T="${T}") ${CMD}

check: perlcritic test

install_pm:
	$(INSTALL) -d -m 755 '$(DESTDIR)$(INSTLIBDIR)Git'
	cd ${files} && $(INSTALL) -m 644 $(GIT_MEDIAWIKI_PM) \
		'$(DESTDIR)$(INSTLIBDIR)/$(GIT_MEDIAWIKI_PM)'

install: install_pm
	$(INSTALL) $(SCRIPT_PERL) $(DESTDIR)$(PREFIX)/lib/git-core/

perlcritic:
	perlcritic -5 $(SCRIPT_PERL)
	-perlcritic -2 $(SCRIPT_PERL)

dockerBuild:
	docker build -t mabs .

docker:
	. t/test.config && docker run --rm -p $$PORT:$$PORT -v `pwd`/t:/t mabs	\
		$(if ${T},--env T="${T}") ${CMD}

.PHONY: all test check install_pm install clean perlcritic
