## Installation

You need to have Git installed on your machine, see the [help with setup for windows] (http://help.github.com/win-set-up-git/), [mac](http://help.github.com/mac-set-up-git/) or [linux](http://help.github.com/linux-set-up-git/).

Dependencies: You need to have the following packages installed :

> libmediawiki-api-perl (recent version. Version 0.39 works. Version 0.34 won't work with mediafiles)

> libdatetime-format-iso8601-perl

Available on common repositories.

To access HTTPS wikis, you may also need

> perl-lwp-protocol-https

The latest version of Git-MediaWiki is available in Git's source tree, in the directory `contrib/mw-to-git`. You can download it from http://git.kernel.org/?p=git/git.git;a=tree;f=contrib/mw-to-git if needed.

After configuring Git's tree (either ./configure --prefix=... or edit config.mak manually), run `make install` from the directory `contrib/mw-to-git`. This will install the script `git-remote-mediawiki` in your PATH. Alternatively, you may install it in manually by copying `git-remote-mediawiki` in Git's exec path (run `git --exec-path` to find out where it is) and make sure it's executable.

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

## Optimizing git fetch

By default, git-remote-mediawiki will list new revisions for each wiki page (`remote.<name>.fetchStrategy` set to `by_page`). This is the most efficient method when cloning a small subset of a very active wiki. On the other hand, fetching from a wiki with little activity but many pages is long (the tool has to query every page even to say "Everything up to date").

One can set `remote.<name>.fetchStrategy` to `by_rev`. Then, git-remote-mediawiki will query the whole wiki for new revisions, and will filter-out revisions that should not be fetched because they do not touch tracked pages. In this case, for example, fetching from an up-to-date wiki is done in constant time (not O(number of pages)).

## Issues with SSL, self-signed or unrecognized certificates

By default, git-remote-mediawiki will verify SSL certificate with recent versions of libwww-perl (but not with older versions, for which the library does not do it by default).

If your wiki uses a self-signed certificate, git-remote-mediawiki won't be able to connect to it. There are several solutions:

* The insecure way: disable SSL verification:

        PERL_LWP_SSL_VERIFY_HOSTNAME=0 git pull
     
* The more secure way: download, install, and trust the certificate. This won't give you 100% guarantee that the certificate is correct, but if an attacker tries to spoof the hostname after you've downloaded the certificate, you should notice it:

        echo | openssl s_client -showcerts -connect wiki.example.com:443 > certs.pem
        HTTPS_CA_FILE=certs.pem git pull