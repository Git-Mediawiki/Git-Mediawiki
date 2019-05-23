<?php
/**
 * This script generates a SQLite database for a MediaWiki
 * You must specify the login of the admin (argument 1) and its
 * password (argument 2) and the folder where the database file
 * is located (absolute path in argument 3).
 * It is used by the script install-wiki.sh in order to make easy the
 * installation of a MediaWiki.
 */
$argc = $_SERVER['argc'];
$argv = $_SERVER['argv'];

$login = $argv[2];
$pass = $argv[3];
$tmp = $argv[4];
$port = $argv[5];

