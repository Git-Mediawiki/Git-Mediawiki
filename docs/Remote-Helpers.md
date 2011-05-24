This project is using remote helpers to feature complete transparency to git users. Instead of creating brand new git-mw commands, using remote helpers also assure that any change to the original git commands would be transferable to our project.

Here, the special interest is with the 'fetch' and 'pull' commands, see man : 

>   fetch <sha1> <name>

> > Fetches the given object, writing the necessary objects to the database. Fetch commands are sent in a batch, one per line, terminated with a blank line. Outputs a single blank line when all fetch commands in the same batch are complete. Only objects which were reported in the ref list with a sha1 may be fetched this way.
Optionally may output a lock <file> line indicating a file under GIT_DIR/objects/pack which is keeping a pack until refs can be suitably updated.
Supported if the helper has the "fetch" capability.

>push :

> > Pushes the given local <src> commit or branch to the remote branch described by <dst>. A batch sequence of one or more push commands is terminated with a blank line.
Zero or more protocol options may be entered after the last push command, before the batch’s terminating blank line.
When the push is complete, outputs one or more ok <dst> or error <dst> <why>? lines to indicate success or failure of each pushed ref. The status report output is terminated by a blank line. The option field <why> may be quoted in a C style string if it contains an LF.
Supported if the helper has the "push" capability.



as they are then the ones that differ the most from original 'fetch' and 'push'. 

Moreover functions such as 'list' :

> list

> > Lists the refs, one per line, in the format "<value> <name> [<attr> …]". The value may be a hex sha1 hash, "@<dest>" for a symref, or "?" to indicate that the helper could not get the value of the ref. A space-separated list of attributes follows the name; unrecognized attributes are ignored. The list ends with a blank line.
    If push is supported this may be called as list for-push to obtain the current refs prior to sending one or more push commands to the helper.
 
is also tricky because refs has to be defined for the mediawiki ... [ À COMPLÉTER]

[Man page of git remote-helpers](http://www.kernel.org/pub/software/scm/git/docs/git-remote-helpers.html)