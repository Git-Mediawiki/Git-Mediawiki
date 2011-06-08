## Getting started with Git-Mediawiki

You need to have git installed on your machine, see the [help with setup for windows] (http://help.github.com/win-set-up-git/), [mac](http://help.github.com/mac-set-up-git/) or [linux](http://help.github.com/linux-set-up-git/).

Dependencies: You need to have the following packages installed :

> libmediawiki-api-perl

> libdatetime-format-iso8601-perl

Available on common repositories.

Then, the first operation you should do is cloning the remote mediawiki. To do so, run the command

`git clone mediawiki::http://yourwikiadress.com`

If you don't want to clone the whole wiki, you can run the command

`git clone mediawiki::http://yourwikiadress.com#One_page#One_other_page`

You can commit your changes as usual with the command

`git commit`

You can pull the last revision from mediawiki with the command 

`git pull --rebase`

You can push the changes you commited as usual with the command

`git push`

Knowing those commands, you can now edit your wiki with your favorite text editor !