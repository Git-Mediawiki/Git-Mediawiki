## Installation

You need to have Git installed on your machine. See the [help with setup for Windows](http://help.github.com/win-set-up-git/), [Mac](http://help.github.com/mac-set-up-git/) or [Linux](http://help.github.com/linux-set-up-git/).

### Dependencies

You need to have the following Perl packages installed:

* __MediaWiki::API__ (recent version. Version 0.39 works. Version 0.34 won't work with mediafiles)
* __DateTime::Format::ISO8601__
* __LWP::Protocol::https__ (for TLS access)


#### Linux in general

On many Linux distributions these can be installed from packages `libmediawiki-api-perl`,  `libdatetime-format-iso8601-perl`, and `perl-lwp-protocol-https` respectively.

#### Gentoo

For Gentoo-based Linux distributions, they can be installed by emerging `dev-perl/MediaWiki-API` and `dev-perl/DateTime-Format-ISO8601`.

On OS X, they can be installed using the CPAN installation tool:

```shell
sudo cpan MediaWiki::API
sudo cpan DateTime::Format::ISO8601
```

#### FreeBSD

On FreeBSD, both dependencies are available from ports or packages:

```shell
# Through packages
pkg install p5-MediaWiki-API p5-DateTime-Format-ISO8601

# Through ports
cd /usr/ports/devel/p5-DateTime-Format-ISO8601
make install
cd /usr/ports/devel/p5-MediaWiki-API
make install
```

#### Debian

On Debian-based systems __LWP::Protocol::https__ is available as `liblwp-protocol-https-perl` package.

### Git-Mediawiki

The latest version of Git-Mediawiki is available in Git's source tree, in the directory `contrib/mw-to-git`. You can download it from http://git.kernel.org/?p=git/git.git;a=tree;f=contrib/mw-to-git if needed. The recommended way to install Git-Mediawiki is to install both Git itself and Git-Mediawiki at the same time (so that you get the latest version of both). If you install Git-Mediawiki on top of an existing Git installation, you need Git >= 1.8.3, or use an old Git-Mediawiki version (the last commit which works with older versions is [commit edca4152](https://github.com/git/git/commit/edca4152560522a431a51fc0a06147fc680b5b18)).

#### Installing from source

After configuring Git's tree (either `./configure --prefix=...` or edit `config.mak` manually), run `make install` from the directory `contrib/mw-to-git`. This will install the script `git-remote-mediawiki` in your `PATH`.

#### Installing manually

Alternatively, you may install Git-Mediawiki manually:

1. Copy or symlink `git-remote-mediawiki` to Git's exec path (run `git --exec-path` to find out where it is). Make sure it is called `git-remote-mediawiki` with no suffix, _not_ `git-remote-mediawiki.perl`.
2. Ensure that `git-remote-mediawiki` is marked as executable.
3. Optionally, do the same for `git-mw`, which contains various helper commands for Git/MediaWiki integration.
4. Set your `PERL5LIB` environment variable to include the necessary directories: `$GIT/perl:$GIT/contrib/mw-to-git`, where `$GIT` is the path to your Git source tree. Without this step, you may receive errors about missing Perl dependencies `Git.pm` and/or `Git::Mediawiki.pm`.

## Getting started with Git-Mediawiki

Then, the first operation you should do is cloning the remote mediawiki. To do so, run the command

    git clone mediawiki::http://yourwikiadress.com
		
*Note: Only the main namespace is fetched this way! How to expand the clone to more namespaces, *

You can commit your changes locally as usual with the command

    git commit

You can pull the last revision from mediawiki with the command 

    git pull --rebase

You can push the changes you commited as usual with the command

    git push

It is strongly recommanded to run `git pull --rebase` after each `git push`.

Knowing those commands, you can now edit your wiki with your favorite text editor!

## Modify import scope

### Limit the pages to be imported

If you don't want to clone the whole wiki, you can import only some pages with:

    git clone -c remote.origin.pages='A_page Another_page' mediawiki::http://yourwikiadress.com
		
and/or select the content of MediaWiki Categories with:

    git clone -c remote.origin.categories='First Second' mediawiki::http://yourwikiadress.com

### Changing processed namespaces

To extend the import to more than the `(Main)` namespace, you can specify a list of the namespaces to process:

    git clone -c remote.origin.namespaces='(Main) Talk Template Template_talk' mediawiki::http://yourwikiadress.com
		
*Note: Namespaces are addressed with their cannonical name, spaces in the name need to be replaced with underscores.*

You can get  all cannonical namespaces of a wiki as a list from the API,  by sending this request:
    api.php?action=query&meta=siteinfo&siprop=namespaces&formatversion=2

### Shallow imports

It is also possible to import only the last revision of a wiki. This is done using the `remote.origin.shallow` configuration variable. To apply the variable once during the clone, use:

    git -c remote.origin.shallow=true clone mediawiki::http://example.com/wiki/

 You can set this variable permanently by using the `-c` option behind the clone command. This will write the value to git's repository config. Any consecutive pull or fetch will skip the intermediary versions, and only fetch the latest version of the pages.

    git clone -c remote.origin.shallow=true mediawiki::http://example.com/wiki/


## Authentication

Some wiki require login/password. You can specify a login and password using the `remote.origin.mwLogin` and `remote.origin.mwPassword` configuration variables. If you need to do that at clone time, the best way is

    git init new-repo
    chmod 600 .git/config # you're going to put a password there
                          # so don't keep it world-readable!
    cd new-repo
    git remote add origin mediawiki::http://example.com/
    git config remote.origin.mwLogin 'UserName'
    git config remote.origin.mwPassword 'PassWord'
    git pull
    git push

If you wiki requires specifying a domain when logging in (if you use LDAP authentication for instance), then you can set `remote.origin.mwDomain` to the corresponding value.

## Previewing changes

(This is work in progress, you need to apply Benoit Person's patches to get this)

You can preview a page without actually pushing it to the wiki using "git mw preview". Run "git mw help" for more information.

## Configuring and understanding how `push` works

By default, when running `git push` to a MediaWiki, Git will update the metadata (remote reference, and the last imported MediaWiki revision stored in notes) during push to reflect the fact that your local revisions correspond to the exported MediaWiki revisions. This way, the next `git pull` will already know that the new revisions on MediaWiki come from your repository, and will not have to re-import them.

While this is convenient, this comes with a drawback: your view of history is the one you've created from Git, and other users cloning the MediaWiki will have a slightly different view of history. If your push loses data (because MediaWiki cannot store a few things that Git can), you may not notice it, but other users will. Also, this means you have no chance to have the same commit identifiers as other cloners of the MediaWiki. An alternative is to set the `mediawiki.dumbPush` configuration variable to `true` (if needed, this can also be done on a per-remote basis with `remote.<name>.dumbPush`). If you do so, `git push` will not touch the MediaWiki metadata, and will ask you to reimport history after a successful push, typically with `git pull --rebase`. For those who know `git svn`: in this mode, `git push; git pull --rebase` is the equivalent of `git svn dcommit`.

## Uploads (files and images)

To include uploaded files, set the two config options `mediaimport` and `mediaexport`:
~~~
git config --bool remote.origin.mediaimport true
git config --bool remote.origin.mediaexport true
~~~

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

## Cloning mediawiki repositories

It may happen that you need to clone a repository that was created from a mediawiki instance. Just a regular clone will not be enough, because there is extra metadata in the repository that is not cloned by default. Furthermore, you will need to synchronize the configuration. For example, I had to do this to completely clone my repository:

```
git clone orig.example.com:mirror/wiki.example.com
cd wiki.example.com
git fetch origin refs/notes/*:refs/notes/*
git fetch origin refs/mediawiki/*:refs/mediawiki/*
git remote set-url origin mediawiki::http://wiki.example.com/
git config remote.origin.fetchstrategy by_rev
git config remote.origin.mediaimport true
git pull
```

The configuration will, of course, vary according to your original configuration.
