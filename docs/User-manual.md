## Installation

You need to have Git installed on your machine, see the [help with setup for windows] (http://help.github.com/win-set-up-git/), [mac](http://help.github.com/mac-set-up-git/) or [linux](http://help.github.com/linux-set-up-git/).

Dependencies: You need to have the following packages installed :

> libmediawiki-api-perl

> libdatetime-format-iso8601-perl

Available on common repositories. The latest version of Git-MediaWiki is available in Git's source tree, in the directory `contrib/mw-to-git`. You can download it from http://git.kernel.org/?p=git/git.git;a=tree;f=contrib/mw-to-git if needed. You need to have the script `git-remote-mediawiki` in your PATH (and it needs to be executable) to use it. Alternatively, you may install it in Git's exec path (run `git --exec-path` to find out where it is).

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
### Limit the pages to be imported

If you don't want to clone the whole wiki, you can import only some pages with:

    git clone -c remote.origin.pages='A_page Another_page' mediawiki::http://yourwikiadress.com

and/or select the content of MediaWiki Categories with:

    git clone -c remote.origin.categories='First Second' mediawiki::http://yourwikiadress.com

### Shallow imports

It is also possible to import only the last revision of a wiki. This is done using the `remote.origin.shallow` configuration variable. To set it during a clone, use:

    git -c remote.origin.shallow=true clone mediawiki::http://example.com/wiki/

Alternatively, you may let clone write the value to the `.git/config` file to have further `git fetch` import only the last revision of each page too with

    git clone -c remote.origin.shallow=true mediawiki::http://example.com/wiki/

(i.e. `-c` option used after `clone` in the command)

## Authentication

Some wiki require login/password. You can specify a login and password using the `remote.origin.mwLogin` and `remote.origin.mwPassword` configuration variables. If you need to do that at clone time, the best way is

    git init new-repo
    chmod 600 .git/config # you're going to put a password there
                          # so don't keep it world-readable!
    git remote add origin mediawiki::http://example.com/
    # edit .git/config and set the right variables in the [remote "origin"] section
    git fetch origin

If you wiki requires specifying a domain when logging in (if you use LDAP authentication for instance), then you can set `remote.origin.mwDomain` to the corresponding value.

## Configuring and understanding how `push` works

By default, when running `git push` to a MediaWiki, Git will update the metadata (remote reference, and the last imported MediaWiki revision stored in notes) during push to reflect the fact that your local revisions correspond to the exported MediaWiki revisions. This way, the next `git pull` will already know that the new revisions on MediaWiki come from your repository, and will not have to re-import them.

While this is convenient, this comes with a drawback: your view of history is the one you've created from Git, and other users cloning the MediaWiki will have a slightly different view of history. If your push loses data (because MediaWiki cannot store a few things that Git can), you may not notice it, but other users will. Also, this means you have no chance to have the same commit identifiers as other cloners of the MediaWiki. An alternative is to set the `mediawiki.dumbPush` configuration variable to `true` (if needed, this can also be done on a per-remote basis with `remote.<name>.dumbPush`). If you do so, `git push` will not touch the MediaWiki metadata, and will ask you to reimport history after a successful push, typically with `git pull --rebase`. For those who know `git svn`: in this mode, `git push; git pull --rebase` is the equivalent of `git svn dcommit`.