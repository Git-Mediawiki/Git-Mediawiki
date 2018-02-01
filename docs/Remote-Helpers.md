This project is using remote helpers to feature complete transparency to git users. Instead of creating brand new git-mw commands, using remote helpers also assure that any change to the original git commands would be transferable to our project.

A few details are required for the different functionalities of the remote-helper

## Function details

### Capabilities
Prints the list of capabilities of our remote helper. 

### List

Prints a list of refs for the repository. In our case, mediawiki has no repository refs. The list command prints

`? refs/heads/master`

`@refs/heads/master HEAD`

Revisions are imported to the private namespace refs/mediawiki/$remotename/ by the helper and fetched into refs/remotes/$remotename later by fetch.


### Option

Allows different options such as 'Verbosity' and 'Progress' to be set up.
Prints 'unsupported' if we don't support it, sets the variable and prints 'ok' if we do.

### Import

Import prints a fast-import stream of the mediawiki to the standard output. It is interfaced with the mediawiki API. Using [git notes](Git-notes.md), it is possible to know which revision was the last imported from the mediawiki. If it's a git clone, the value is 0 and every revision is imported from the wiki. Otherwise, it only imports revisions that were created after the last one. Finally, it prints the fast-import stream with this format for each revision :

This chunk handles the data part :

```
commit refs/mediawiki/'$remotename'/master #Where $remotename is 'origin' by default
mark :<int>
committer <user> <mail> <timestamp> +0000
data <sizeofcomment>
<comment>
M 644 inline <title>.wiki
data <sizeoffile>
<content>
```

Note that we need to use a secondary ref refs/mediawiki/origin/master otherwise it bugs out. We cannot write directly into refs/remotes/origin/master without errors being thrown. This ref is also a blessing as it always points to the last git note metadata, making things easier to know the last local revision.

This part creates a note that contains our metadata : 

```
commit refs/notes/commits
committer <user> <mail> <timestamp> +0000
data <sizeofnotecomment>
<notecomment> # In our case : note added by git-mediawiki
N inline :<markabove>
data <sizeofnotecontent>
<notecontent> # In our case : mediawiki_revision: <revisionid>
```

### Push

Thanks to git notes, it is possible to know the last local revision fetched. With the mediawiki API, it is also possible to know the last remote revision on the server. If the server is ahead from us, a fast forward error message is thrown.

> We may have an issue here. If one track about a thousand very active pages, even if they want to push a small change on one page, they may never be able to do so and get this message every time.

If they are equal, "Everything up-to-date".

Otherwise, for each commit between remotes/origin/master and HEAD, catch every blob related to these commit and push them in chronological order. To do so, we use git rev-list --children HEAD and travel the tree from remotes/origin/master to HEAD through children. In other words :

* Shortest path from remotes/origin/master to HEAD
* For each commit encountered
* Push blobs related to this commit

> We need to add conflict support if files have been changed on the mediawiki between the time the user typed git push and the file is pushed. Mediawiki should already send an exception or a message of some sort. We need to catch it and handle it.

Once done, an automatic git pull --rebase is executed to keep a clean and close to mediawiki history. Most of the merges done will be trivial anyway.

## Documentation 

[Man page of git remote-helpers](http://www.kernel.org/pub/software/scm/git/docs/git-remote-helpers.html)
