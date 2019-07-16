# Copyright (C) 2012
#     Charles Roussel <charles.roussel@ensimag.imag.fr>
#     Simon Cathebras <simon.cathebras@ensimag.imag.fr>
#     Julien Khayat <julien.khayat@ensimag.imag.fr>
#     Guillaume Sasdy <guillaume.sasdy@ensimag.imag.fr>
#     Simon Perrat <simon.perrat@ensimag.imag.fr>
# License: GPL v2 or later

#
# CONFIGURATION VARIABLES
# You might want to change these ones
#

. ./test.config

WIKI_URL=http://"$SERVER_ADDR:$PORT/$WIKI_DIR_NAME"
CURR_DIR=$(pwd)
TEST_OUTPUT_DIRECTORY=$(pwd)
WEB_ERROR_LOG="$WEB_TMP/lighttpd.error.log"
PHP_ERROR_LOG="$WEB_TMP/php_errors.log"

export TEST_OUTPUT_DIRECTORY CURR_DIR

if test "$LIGHTTPD" = "false" ; then
	PORT=80
else
	WIKI_DIR_INST="$WEB_WWW"
fi

wiki_upload_file () {
	"$CURR_DIR"/test-gitmw.pl upload_file "$@"
}

wiki_getpage () {
	"$CURR_DIR"/test-gitmw.pl get_page "$@"
}

wiki_delete_page () {
	"$CURR_DIR"/test-gitmw.pl delete_page "$@"
}

wiki_editpage () {
	"$CURR_DIR"/test-gitmw.pl edit_page "$@"
}

die () {
	die_with_status 1 "$@"
}

die_with_status () {
	status=$1
	shift
	echo >&2 "$*"
	exit "$status"
}


# Check the preconditions to run git-remote-mediawiki's tests
test_check_precond () {
	GIT_EXEC_PATH=$(cd "$(dirname "$0")/.." && pwd)
	PATH="$GIT_EXEC_PATH"'/bin-wrapper:'"$PATH"
	echo "$WIKI_DIR_INST/$WIKI_DIR_NAME"
	if [ ! -d "$WIKI_DIR_INST/$WIKI_DIR_NAME" ];
	then
		skip_all='skipping gateway git-mw tests, no mediawiki found'
		test_done
	fi
}

# missing from sharness
# debugging-friendly alternatives to "test [-f|-d|-e]"
# The commands test the existence or non-existence of $1. $2 can be
# given to provide a more precise diagnosis.
test_path_is_file () {
	if ! test -f "$1"
	then
		echo "File $1 doesn't exist. $2"
		false
	fi
}

test_path_is_dir () {
	if ! test -d "$1"
	then
		echo "Directory $1 doesn't exist. $2"
		false
	fi
}

# Check if the directory exists and is empty as expected, barf otherwise.
test_dir_is_empty () {
	test_path_is_dir "$1" &&
	if test -n "$(ls -a1 "$1" | egrep -v '^\.\.?$')"
	then
		echo "Directory '$1' is not empty, it contains:"
		ls -la "$1"
		return 1
	fi
}

test_path_is_missing () {
	if test -e "$1"
	then
		echo "Path exists:"
		ls -ld "$1"
		if test $# -ge 1
		then
			echo "$*"
		fi
		false
	fi
}

# Use this instead of "grep expected-string actual" to see if the
# output from a git command that can be translated either contains an
# expected string, or does not contain an unwanted one.  When running
# under GETTEXT_POISON this pretends that the command produced expected
# results.
test_i18ngrep () {
	if test -n "$GETTEXT_POISON"
	then
		: # pretend success
	elif test "x!" = "x$1"
	then
		shift
		! grep "$@"
	else
		grep "$@"
	fi
}

# test_diff_directories <dir_git> <dir_wiki>
#
# Compare the contents of directories <dir_git> and <dir_wiki> with diff
# and errors if they do not match. The program will
# not look into .git in the process.
# Warning: the first argument MUST be the directory containing the git data
test_diff_directories () {
	rm -rf "$1_tmp"
	mkdir -p "$1_tmp"
	cp "$1"/*.mw "$1_tmp"
	diff -r -b "$1_tmp" "$2"
}

# $1=<dir>
# $2=<N>
#
# Check that <dir> contains exactly <N> files
test_contains_N_files () {
	if test $(ls -- "$1" | wc -l) -ne "$2"; then
		echo "directory $1 should contain $2 files"
		echo "it contains these files:"
		ls "$1"
		false
	fi
}


# wiki_check_content <file_name> <page_name>
#
# Compares the contents of the file <file_name> and the wiki page
# <page_name> and exits with error 1 if they do not match.
wiki_check_content () {
	mkdir -p wiki_tmp
	wiki_getpage "$2" wiki_tmp
	# replacement of forbidden character in file name
	page_name=$(printf "%s\n" "$2" | sed -e "s/\//%2F/g")

	diff -b "$1" wiki_tmp/"$page_name".mw
	if test $? -ne 0
	then
		rm -rf wiki_tmp
		error "ERROR: file $2 not found on wiki"
	fi
	rm -rf wiki_tmp
}

# wiki_page_exist <page_name>
#
# Check the existence of the page <page_name> on the wiki and exits
# with error if it is absent from it.
wiki_page_exist () {
	mkdir -p wiki_tmp
	wiki_getpage "$1" wiki_tmp
	page_name=$(printf "%s\n" "$1" | sed "s/\//%2F/g")
	if test -f wiki_tmp/"$page_name".mw ; then
		rm -rf wiki_tmp
	else
		rm -rf wiki_tmp
		error "test failed: file $1 not found on wiki"
	fi
}

# wiki_getallpagename
#
# Fetch the name of each page on the wiki.
wiki_getallpagename () {
	"$CURR_DIR"/test-gitmw.pl getallpagename
}

# wiki_getallpagecategory <category>
#
# Fetch the name of each page belonging to <category> on the wiki.
wiki_getallpagecategory () {
	"$CURR_DIR"/test-gitmw.pl getallpagename "$@"
}

# wiki_getallpage <dest_dir> [<category>]
#
# Fetch all the pages from the wiki and place them in the directory
# <dest_dir>.
# If <category> is define, then wiki_getallpage fetch the pages included
# in <category>.
wiki_getallpage () {
	if test -z "$2";
	then
		wiki_getallpagename
	else
		wiki_getallpagecategory "$2"
	fi
	mkdir -p "$1"
	while read -r line; do
		wiki_getpage "$line" $1;
	done < all.txt
}

# ================= Install part =================

error () {
	echo "$@" >&2
	exit 1
}

# config_lighttpd
#
# Create the configuration files and the folders necessary to start lighttpd.
# Overwrite any existing file.
config_lighttpd () {
	mkdir -p $WEB
	mkdir -p $WEB_TMP
	mkdir -p $WEB_WWW

	cat > $WEB/lighttpd.conf <<EOF
	server.document-root = "$WEB_WWW"
	server.port = $PORT
	server.pid-file = "$WEB_TMP/pid"

	server.modules = (
	"mod_rewrite",
	"mod_redirect",
	"mod_access",
	"mod_accesslog",
	"mod_fastcgi"
	)

	server.errorlog = "$WEB_ERROR_LOG"

	index-file.names = ("index.php" , "index.html")

	mimetype.assign		    = (
	".pdf"		=>	"application/pdf",
	".sig"		=>	"application/pgp-signature",
	".spl"		=>	"application/futuresplash",
	".class"	=>	"application/octet-stream",
	".ps"		=>	"application/postscript",
	".torrent"	=>	"application/x-bittorrent",
	".dvi"		=>	"application/x-dvi",
	".gz"		=>	"application/x-gzip",
	".pac"		=>	"application/x-ns-proxy-autoconfig",
	".swf"		=>	"application/x-shockwave-flash",
	".tar.gz"	=>	"application/x-tgz",
	".tgz"		=>	"application/x-tgz",
	".tar"		=>	"application/x-tar",
	".zip"		=>	"application/zip",
	".mp3"		=>	"audio/mpeg",
	".m3u"		=>	"audio/x-mpegurl",
	".wma"		=>	"audio/x-ms-wma",
	".wax"		=>	"audio/x-ms-wax",
	".ogg"		=>	"application/ogg",
	".wav"		=>	"audio/x-wav",
	".gif"		=>	"image/gif",
	".jpg"		=>	"image/jpeg",
	".jpeg"		=>	"image/jpeg",
	".png"		=>	"image/png",
	".xbm"		=>	"image/x-xbitmap",
	".xpm"		=>	"image/x-xpixmap",
	".xwd"		=>	"image/x-xwindowdump",
	".css"		=>	"text/css",
	".html"		=>	"text/html",
	".htm"		=>	"text/html",
	".js"		=>	"text/javascript",
	".asc"		=>	"text/plain",
	".c"		=>	"text/plain",
	".cpp"		=>	"text/plain",
	".log"		=>	"text/plain",
	".conf"		=>	"text/plain",
	".text"		=>	"text/plain",
	".txt"		=>	"text/plain",
	".dtd"		=>	"text/xml",
	".xml"		=>	"text/xml",
	".mpeg"		=>	"video/mpeg",
	".mpg"		=>	"video/mpeg",
	".mov"		=>	"video/quicktime",
	".qt"		=>	"video/quicktime",
	".avi"		=>	"video/x-msvideo",
	".asf"		=>	"video/x-ms-asf",
	".asx"		=>	"video/x-ms-asf",
	".wmv"		=>	"video/x-ms-wmv",
	".bz2"		=>	"application/x-bzip",
	".tbz"		=>	"application/x-bzip-compressed-tar",
	".tar.bz2"	=>	"application/x-bzip-compressed-tar",
	""		=>	"text/plain"
	)

	fastcgi.server = ( ".php" =>
	("localhost" =>
	( "socket" => "$WEB_TMP/php.socket",
	"bin-path" => "$PHP_DIR/php-cgi -c $WEB/php.ini"

	)
	)
	)
EOF

	cat > $WEB/php.ini <<EOF
	error_reporting = E_ALL
	error_log = $PHP_ERROR_LOG
	session.save_path ='$CURR_DIR/$WEB_TMP'
EOF
}

# start_lighttpd
#
# Start or restart daemon lighttpd. If restart, rewrite configuration files.
start_lighttpd () {
	pid=$1 # $WEB_TMP/pid
	path=$2 # $LIGHTTPD_DIR
	confdir=$3 # $WEB
	errorLog=$4 # $WEB_ERROR_LOG

	if test -f "$pid"; then
		echo "Instance already running. Restarting..."
		stop_lighttpd
	fi
	config_lighttpd
	$path/lighttpd -f $confdir/lighttpd.conf

	if test $? -ne 0 ; then
		output_log $errorLog "Could not execute http deamon lighttpd. Error log:"
	fi
}

output_log () {
	logFile=$1
	header=$2

	if [ -f $logFile ]; then
		echo $header
		echo "**************************************************"
		cat $logFile
		echo "**************************************************"
		rm -f $logFile
	fi
}

# stop_lighttpd
#
# Kill daemon lighttpd and removes files and folders associated.
stop_lighttpd () {
	pid=$1 # $WEB_TMP/pid
	errorLog=$2 # $WEB_ERROR_LOG
	phpErrorLog=$3 # $PHP_ERROR_LOG
	wikiDebugLog=$4 # $MW_DEBUG_LOG
	test -f $pid && kill $(cat $pid)

	output_log $errorLog "Output from lighttpd error log:"
	output_log $phpErrorLog "Output from PHP error log:"
	output_log $wikiDebugLog "MediaWiki debug log:"
}

download_if_needed () {
	url=$1
	ver=$2
	dldir=$3
	target=mediawiki-$ver.tar.gz
	url=${url}/${target}

	# Fetch MediaWiki's archive if not already present in the TMP directory
	cd "$dldir" && (
		if [ ! -f $target ] ; then
			echo "Downloading $ver sources ..."
			wget $url || error "Unable to download $url :"					\
							   "Please fix your connection and launch the"	\
							   "script again."
			echo "$tgz downloaded in $dldir."
		else
			echo "Reusing existing $target downloaded in $dldir."
		fi
	)
}

copy_localsettings () {
	from=$1
	to=$2
	dir=$3 # $WIKI_DIR_NAME
	server=$4 # $SERVER_ADDR
	dbDir=$5 # $TMP

	# Copy the generic LocalSettings.php in the web server's directory
	# And modify parameters according to the ones set at the top
	# of this script.
	# Note that LocalSettings.php is never modified.
	if [ ! -f "$from" ] ; then
		error "Can't find $from in the current folder. "\
			  "Please run the script inside its folder."
	fi
	cp "$from" "$to" || error "Unable to copy $from to $to"

	# Parse and set the LocalSettings file of the user according to the
	# CONFIGURATION VARIABLES section at the beginning of this script
	sed -i "s,@WG_SCRIPT_PATH@,/$dir," "$to" 							||	\
		error "failed replacing WG_SCRIPT_PATH"
	sed -i "s,@WG_SERVER@,http://$server," "$to" 						||	\
		error "failed replacing WG_SERVER"
	sed -i "s,@WG_SQLITE_DATADIR@,$dbDir," "$to"						||	\
		error "failed replacing WG_SQLITE_DATADIR"
	sed -i "s,@WG_SQLITE_DATAFILE@,$(basename $DB_FILE .sqlite)," "$to" ||	\
		error "failed replacing WG_SQLITE_DATAFILE"
	echo "File $from is set in $base"
}

setup_dir () {
	dir=$1

	mkdir -p "$dir"
	if [ ! -d "$dir" ] ; then
		error "Folder $dir doesn't exist."									\
			  "Please create it and launch the script again."
	fi
}

create_db () {
	installDir=$1
	dbDir=$2
	path=$3
	rm -f $dbDir/*.sqlite

	echo CREDENTIALS: $WIKI_ADMIN $WIKI_PASSW
	cd $installDir														&&	\
		php maintenance/install.php --dbtype=sqlite --dbpath="$dbDir"		\
			--scriptpath=$path --pass=$WIKI_PASSW wiki $WIKI_ADMIN
	echo '$wgDebugLogFile = "'$MW_DEBUG_LOG'";' >> LocalSettings.php
}

# Install a wiki in your web server directory.
wiki_install () {
	files=$1          # $FILES_FOLDER
	dir=$2            # $WIKI_DIR_INST/$WIKI_DIR_NAME
	url=$3            # $MW_URL
	ver=$4            # "$MW_VERSION_MAJOR.$MW_VERSION_MINOR"
	server=$5         # $SERVER_ADDR:$PORT
	tgz=$6            # $MW_TGZ
	tmp=$7			  # $TMP
	path=$8			  # $WIKI_DIR_NAME

	# In this part, we change directory to $TMP in order to download,
	# unpack and copy the files of MediaWiki
	(
		setup_dir $dir
		download_if_needed $url $ver $tmp
		archive_abs_path=$(pwd)/$tgz
		tar -C $dir -xzf "$archive_abs_path" --strip-components=1 ||
			error "Unable to extract MediaWiki's files from"				\
					"$archive_abs_path to $dir"
	) || exit 1

	create_db $dir $tmp $path

	echo "Your wiki has been installed: http://$server/$path"
}

# Reset the database of the wiki and the password of the admin
#
# Warning: This function must be called only in a subdirectory of t/
# directory
wiki_reset () {
	# Copy initial database of the wiki
	if [ ! -f "$FILES_FOLDER/$DB_FILE" ] ; then
		error "Can't find $FILES_FOLDER/$DB_FILE in the current folder."
	fi
	cp "$FILES_FOLDER/$DB_FILE" "$TMP" ||
		error "Can't copy $FILES_FOLDER/$DB_FILE in $TMP"
	echo "File $FILES_FOLDER/$DB_FILE is set in $TMP"
}

# Delete the wiki created in the web server's directory and all its content
# saved in the database.
wiki_delete () {
	if test $LIGHTTPD = "true"; then
		stop_lighttpd
		rm -fr "$WEB"
	else
		# Delete the wiki's directory.
		rm -rf "$WIKI_DIR_INST/$WIKI_DIR_NAME" ||
			error "Wiki's directory $WIKI_DIR_INST/" \
			"$WIKI_DIR_NAME could not be deleted"
		# Delete the wiki's SQLite database.
		rm -f "$TMP/$DB_FILE" ||
			error "Database $TMP/$DB_FILE could not be deleted."
	fi

	# Delete the wiki's SQLite database
	rm -f "$TMP/$DB_FILE" || error "Database $TMP/$DB_FILE could not be deleted."
	rm -f "$FILES_FOLDER/$DBFILE"
	rm -rf "$TMP/mediawiki-$MW_VERSION_MAJOR.$MW_VERSION_MINOR.tar.gz"
}
