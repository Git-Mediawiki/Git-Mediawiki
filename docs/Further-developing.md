#Sandbox for further developing

[Last status mail](http://www.spinics.net/lists/git/msg158701.html)


## Possibility to add more pages overtime
One would like to track other pages. We need to create a command to add these pages to the repository.
Issue : Necessity to rewrite the entire history

## Possibility to log in to the wiki
The mediawiki->login method from the API returns a sessionid. If we cross it with mediawiki->{ua}->{cookie_jar}, it should be able to maintain session between two calls without having to re-login. To go further, it could be really nice to type something in the lines of "git config remote.$remotename.username" to get the username pretending it is stored in .git/config and use Term::ReadKey; ReadMode('noecho'); $password = ReadLine(0); to get the password

## Clone tracked pages
Combining Partial clones and login possibilities, it could be also nice to login and only clone pages that are tracked by a user.

## Merge patterns
We strongly advise the use of git pull --rebase using this script, to keep things clean between git and mediawiki. Maybe other solutions are to be found. [See status mail](http://www.spinics.net/lists/git/msg158701.html)

## Sending attached files to wiki pages
In mediawiki one can upload and download images, videos, archives, etc to wiki pages. The MediaWiki enables that thanks to [MediaWiki::API->dowload($params_hash)](http://search.cpan.org/~exobuzz/MediaWiki-API-0.24/lib/MediaWiki/API.pm#MediaWiki::API-%3Eupload%28_$params_hash_%29) and [MediaWiki::API->download($params_hash)](http://search.cpan.org/~exobuzz/MediaWiki-API-0.24/lib/MediaWiki/API.pm#MediaWiki::API-%3Edownload%28_$params_hash_%29).

## Renaming and deleting files
MediaWiki has its own norms regarding these actions.

### Renaming files
* Not investigated. MediaWiki behaves in its own way with file renaming and should be investigated further.

### Deleting files
* Import deleted file signals from mediawiki : if during the mediawiki API call for pages (git pull), a page is not found, a 'delete' info should be written in the fast-import stream. 
* Export deleted file signals to mediawiki : this is trickier because of the rights required to remove a file. With git diff --raw, the status of a file ([M]odified, [D]eleted ...) can be get. If it's 'D', send a remove query to mediawiki