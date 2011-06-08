# UTF-8 Encoding

Data encoding is a little tricky here. The mediawiki should be encoded in utf8. However, our script is caught in between git and mediawiki, and itself written in perl. That's a lot to consider.

Typically, every character is authorized in the URL of a mediawiki page (and consequently its title). When the file is to be imported locally, a correct file name has to be found. UTF-8 encoding is the best to allow this. It is very important to make sure that mediawiki files and local files keep the same encoding for both its title and its content.

The entire perl script is told that utf8 is the norm thanks to 
> use encoding 'utf8';

## Mediawiki -> Git

Since utf8 is the norm, the real character that raises a problem is '/'. It needs to be replaced somehow to avoid unwanted directories to be created. In the script, it is replaced by a string described by the variable $slash_replacement. 

## Git -> Mediawiki

The data that need to be send to mediawiki are stored in git blobs. To get that data, the command `git cat-file -p` is used. Consequently, further encoding is needed here
>	open(my $git, "-|:encoding(UTF-8)", <command>);
>	my $res = do { local $/; <$git> };
>	close($git);
This helps encoding in-file data. 

To get titles, a `git diff` command is used. If it is used without the '-z' parameter, non-iso characters are weirly encoded with \\###\\### type of characters. Furthermore, the mediawiki API needs to be told that everything we are sending to it is already utf-8 encoded, requiring us to add the option `skip_encoding => 1` in the mediawiki edit call.

## Further implementation regarding encoding

* Mediawiki has a norm : every blank characters (spaces, \n) are removed before sent to the server when a file is edited. That implies that before the file is sent to mediawiki, a filter has to be applied to get rid of every blank character at the end of it.
* Different file systems have different ways to handle non-iso characters in file names. That implies that every file should not have this type of characters in its name. To get rid of this, a smart use of uri_escape could be used. We ran into some problems since because of the utf8 general encoding of the file, uri_unescape is not the inverse of uri_escape.