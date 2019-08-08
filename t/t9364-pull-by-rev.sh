#!/bin/sh

test_description='Test the Git MediaWiki remote helper: git pull by revision'

. ./test-gitmw-lib.sh
. ./push-pull-tests.sh
. ./sharness/sharness.sh

test_check_precond

test_expect_success 'configuration' '
	git config --global mediawiki.fetchStrategy by_rev
'

test_push_pull

test_done
