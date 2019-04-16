package Git::Mediawiki;

use 5.008;
use strict;
use POSIX;
use Git;

BEGIN {

our ($VERSION, @ISA, @EXPORT, @EXPORT_OK);

# Totally unstable API.
$VERSION = '0.01';

require Exporter;

@ISA = qw(Exporter);

@EXPORT = ();

# Methods which can be called as standalone functions as well:
@EXPORT_OK = qw(clean_filename smudge_filename connect_maybe
				EMPTY HTTP_CODE_OK HTTP_CODE_PAGE_NOT_FOUND);
}

# Mediawiki filenames can contain forward slashes. This variable decides by which pattern they should be replaced
use constant SLASH_REPLACEMENT => '%2F';

# Used to test for empty strings
use constant EMPTY => q{};

# HTTP codes
use constant HTTP_CODE_OK => 200;
use constant HTTP_CODE_PAGE_NOT_FOUND => 404;

sub SUFFIX {
  return run_git("config --get --bool remote.${remotename}.fileextension") || ".mw"
}

# usage: $out = run_git("command args");
#        $out = run_git("command args", "raw"); # don't interpret output as UTF-8.
sub run_git {
	my $args = shift;
	my $encoding = (shift || 'encoding(UTF-8)');
	open(my $git, "-|:${encoding}", "git ${args}")
	    or die "Unable to fork: $!\n";
	my $res = do {
		local $/ = undef;
		<$git>
	};
	close($git);

	return $res;
}

sub clean_filename {
	my $filename = shift;
	$filename =~ s{@{[SLASH_REPLACEMENT]}}{/}g;
	# [, ], |, {, and } are forbidden by MediaWiki, even URL-encoded.
	# Do a variant of URL-encoding, i.e. looks like URL-encoding,
	# but with _ added to prevent MediaWiki from thinking this is
	# an actual special character.
	$filename =~ s/[\[\]\{\}\|]/sprintf("_%%_%x", ord($&))/ge;
	# If we use the uri escape before
	# we should unescape here, before anything

	return $filename;
}

sub smudge_filename {
	my $filename = shift;
	$filename =~ s{/}{@{[SLASH_REPLACEMENT]}}g;
	$filename =~ s/ /_/g;
	# Decode forbidden characters encoded in clean_filename
	$filename =~ s/_%_([0-9a-fA-F][0-9a-fA-F])/sprintf('%c', hex($1))/ge;
	return substr($filename, 0, NAME_MAX-length(SUFFIX));
}

sub connect_maybe {
	my $wiki = shift;
	if ($wiki) {
		return $wiki;
	}

	my $remote_name = shift;
	my $remote_url = shift;
	my ($wiki_login, $wiki_password, $wiki_domain);

	$wiki_login = Git::config("remote.${remote_name}.mwLogin");
	$wiki_password = Git::config("remote.${remote_name}.mwPassword");
	$wiki_domain = Git::config("remote.${remote_name}.mwDomain");

	$wiki = MediaWiki::API->new;

	$wiki->{ua}->agent("git-mediawiki/$Git::Mediawiki::VERSION " . $wiki->{ua}->agent());
	$wiki->{ua}->conn_cache({total_capacity => undef});

	$wiki->{config}->{api_url} = "${remote_url}/api.php";
	if ($wiki_login) {
		my %credential = (
			'url' => $remote_url,
			'username' => $wiki_login,
			'password' => $wiki_password
		);
		Git::credential(\%credential);
		my $request = {lgname => $credential{username},
			       lgpassword => $credential{password},
			       lgdomain => $wiki_domain};
		if ($wiki->login($request)) {
			Git::credential(\%credential, 'approve');
			print {*STDERR} qq(Logged in mediawiki user "$credential{username}".\n);
		} else {
			print {*STDERR} qq(Failed to log in mediawiki user "$credential{username}" on ${remote_url}\n);
			print {*STDERR} '  (error ' .
				$wiki->{error}->{code} . ': ' .
				$wiki->{error}->{details} . ")\n";
			Git::credential(\%credential, 'reject');
			exit 1;
		}
	}

	return $wiki;
}

1; # Famous last words
