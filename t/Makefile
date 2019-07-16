#
# Copyright (C) 2012
#     Charles Roussel <charles.roussel@ensimag.imag.fr>
#     Simon Cathebras <simon.cathebras@ensimag.imag.fr>
#     Julien Khayat <julien.khayat@ensimag.imag.fr>
#     Guillaume Sasdy <guillaume.sasdy@ensimag.imag.fr>
#     Simon Perrat <simon.perrat@ensimag.imag.fr>
#
## Test git-remote-mediawiki
mkfilePath := $(abspath $(lastword $(MAKEFILE_LIST)))
mkfileDir := $(patsubst %/,%,$(dir $(mkfilePath)))

T=$(wildcard ${mkfileDir}/t[0-9][0-9][0-9][0-9]-*.sh)

all: test

.PHONY: help test clean all

help:
	@echo 'Run "$(MAKE) test" to launch test scripts'
	@echo 'Run "$(MAKE) clean" to remove trash folders'

test:
	. ${mkfileDir}/test-gitmw-lib.sh					 				&&	\
	rm -f "$$WIKI_DIR_INST/$$WIKI_DIR_NAME/LocalSettings.php"				\
		$$TMP/*.sqlite $$FILES_FOLDER/*.sqlite 							&&	\
	mkdir -p $$FILES_FOLDER												&&	\
	start_lighttpd $$WEB_TMP/pid $$LIGHTTPD_DIR $$WEB $$WEB_ERROR_LOG	&&	\
	wiki_install $$FILES_FOLDER "$$WIKI_DIR_INST/$$WIKI_DIR_NAME" $$MW_URL	\
		"$$MW_VERSION_MAJOR.$$MW_VERSION_MINOR"	"$$SERVER_ADDR:$$PORT" 		\
		$$MW_TGZ $$TMP $$WIKI_DIR_NAME									&&	\
	cp -r $$TMP/*.sqlite $$FILES_FOLDER/								&&	\
	for t in ${T}; do 	\
		cd ${mkfileDir};													\
		"$$t" --verbose || ( stop_lighttpd $$WEB_TMP/pid $$WEB_ERROR_LOG	\
			$$PHP_ERROR_LOG $$MW_DEBUG_LOG; exit 1 )						\
	done																&&	\
	stop_lighttpd $$WEB_TMP/pid $$WEB_ERROR_LOG $$PHP_ERROR_LOG				\
		$$MW_DEBUG_LOG

clean:
	$(RM) -r 'trash directory'.*
