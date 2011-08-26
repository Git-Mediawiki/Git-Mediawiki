## Installation

You need to have Git installed on your machine, see the [help with setup for windows] (http://help.github.com/win-set-up-git/), [mac](http://help.github.com/mac-set-up-git/) or [linux](http://help.github.com/linux-set-up-git/).

Dependencies: You need to have the following packages installed :

> libmediawiki-api-perl

> libdatetime-format-iso8601-perl

Available on common repositories.

## Getting started with Git-Mediawiki

Then, the first operation you should do is cloning the remote mediawiki. To do so, run the command

    git clone mediawiki::http://yourwikiadress.com

You can commit your changes locally as usual with the command

    git commit

You can pull the last revision from mediawiki with the command 

    git pull --rebase

You can push the changes you commited as usual with the command

    git push

It is strongly recommanded to run `git pull --rebase` after each `git push`.

Knowing those commands, you can now edit your wiki with your favorite text editor!

## Partial import of a Wiki

If you don't want to clone the whole wiki, you can import only some pages with:

    git clone -c remote.origin.pages='A_page Another_page' mediawiki::http://yourwikiadress.com

and/or select the content of MediaWiki Categories with:

    git clone -c remote.origin.categories='First Second' mediawiki::http://yourwikiadress.com

## Authentication

Some wiki require login/password. You can specify a login and password using the `remote.origin.mwLogin` and `remote.origin.mwPassword` configuration variables. If you need to do that at clone time, the best way is

    git init new-repo
    chmod 600 .git/config # you're going to put a password there
                          # so don't keep it world-readable!
    git remote add origin mediawiki::http://example.com/
    git fetch origin