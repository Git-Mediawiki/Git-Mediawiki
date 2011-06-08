The format of data exchanged between mediawiki is the fast-import / fast-export format of git.

Both directions - import and export - use the [mediawiki API](http://www.mediawiki.org/wiki/API:Main_page). 
Scripts are written in Perl mainly because mediawiki's API in perl was a fit to our needs and we already had at our disposal a perl script to help us.

## Mediawiki -> Git

The goal here is to fetch data from the mediawiki using the API and then, format them in fast-import. Our code was based on a script snippet created by Jeff King [[Link to discussion](http://article.gmane.org/gmane.comp.version-control.git/167560)]
Here is the flow-chart of this part 

## Git -> Mediawiki

This part is fully



## References

1. [Man page of git fast-import](http://www.kernel.org/pub/software/scm/git/docs/git-fast-import.html)
2. [Man page of git fast-export](http://www.kernel.org/pub/software/scm/git/docs/git-fast-export.html)