The format of data exchanged between mediawiki is the fast-import / fast-export format of git.

Both directions of the gate also make use of the [mediawiki API](http://www.mediawiki.org/wiki/API:Main_page). The scripts are written in Perl.

## Mediawiki -> Git

The goal here is to fetch data from mediawiki using the API and format them in fast-import. We based our code on a script snippet created by Jeff King [[Link to discussion](http://article.gmane.org/gmane.comp.version-control.git/167560)]

## Git -> Mediawiki

Fully supported by the mediawiki api ? [More info needed]

## References

1. [Man page of git fast-import](http://www.kernel.org/pub/software/scm/git/docs/git-fast-import.html)
2. [Man page of git fast-export](http://www.kernel.org/pub/software/scm/git/docs/git-fast-export.html)