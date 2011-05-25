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

Import prints a fast-import stream of the mediawiki to the standard output. It is interfaced with the mediawiki API. It fetches every revision on the wiki and then prints the fast-import stream with this format for each revision :

`commit refs/heads/master`

`mark :<int>`

`commiter <user> <address> <timestamp> +0000`

`data <sizeofcomment>`

`<comment>`

`M 644 inline <title>.wiki`

`data <sizeoffile>`

`<content>`

It ends with a 

`reset refs/heads/master`

`from :<lastmark>`

## Further developing

* We need to decide if we need to fetch all the revisions with their content, order them by datetime and then print the fast-export stream or fetch only the revision ids and fetch the content file by file. The first alternative is easier on the server-side but may be hard on memory if the wiki that we fetch is huge (such as wikipedia)
* We need to figure out how to divide the import function because for now, it always imports the entire wiki and then diffs to see what files have changed, which is problematic for git pulls. 

## Documentation 

[Man page of git remote-helpers](http://www.kernel.org/pub/software/scm/git/docs/git-remote-helpers.html)