This project is using remote helpers to feature complete transparency to git users. Instead of creating brand new git-mw commands, using remote helpers also assure that any change to the original git commands would be transferable to our project.

A few details are required for the different functionalities of the remote-helper

##Function details

###Capabilities
Prints the list of capabilities of our remote helper. 

###List

Prints a list of refs for the repository. In our case, mediawiki has no repository refs. The list command prints

`? refs/heads/master`

`@refs/heads/master HEAD`

###Option

Allows different options such as 'Verbosity' and 'Progress' to be set up.
Prints 'unsupported' if we don't support it, sets the variable and prints 'ok' if we do.

###Fetch

Fetch seems to make no sense in our case. We simply can't fetch objects from mediawiki since it's not a repository. Fetch only prints out a blank line for now

###Import

Import prints a fast-import stream of the mediawiki to the standard output. It is interfaced with the mediawiki API. Using [[git notes]], it is possible to know which revision was the last imported from the mediawiki. If it's a git clone, the value is 0 and every revision is imported from the wiki. Otherwise, it only imports revisions that were created after the last one. Finally, it prints the fast-import stream with this format for each revision :

`commit refs/heads/master`

`mark :<int>`

`commiter <user> <address> <timestamp> +0000`

`data <sizeofcomment>`

`<comment>`

`M 644 inline <title>.wiki`

`data <sizeoffile>`

`<content>`

###Push

* Check if git has the latest revision of mediawiki. If not, print a fast forward error message and abort. The user will have to pull to then push.

* Send the files one by one. Before sending one file, git has to check that it has not been updated on the mediawiki. If it has been modified, git should catch an error message from mediawiki and act consequently (still to be determined)


## Documentation 

[Man page of git remote-helpers](http://www.kernel.org/pub/software/scm/git/docs/git-remote-helpers.html)