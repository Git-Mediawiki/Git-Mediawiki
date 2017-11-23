We needed some sort of metadata to store information on each commit regarding which mediawiki revision it refers to. The solution we use is to store them in git notes.
The format is `mediawiki_revision: <id>`. 

When the script imports revisions from mediawiki, a formatted note is associated to each commit. That way, it is easy to know which was the last revision imported for further imports (git pulls, mostly).

More information :
[Man page of git-notes](http://www.kernel.org/pub/software/scm/git/docs/git-notes.html)