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

@ISA = qw(Exporter MediaWiki::API);

@EXPORT = ();

# Methods which can be called as standalone functions as well:
@EXPORT_OK = qw(connect_maybe
								EMPTY HTTP_CODE_OK HTTP_CODE_PAGE_NOT_FOUND);
}

# Used to test for empty strings
use constant EMPTY => q{};

# HTTP codes
use constant HTTP_CODE_OK => 200;
use constant HTTP_CODE_PAGE_NOT_FOUND => 404;

# Mediawiki filenames can contain forward slashes. This variable
# decides by which pattern they should be replaced
sub SLASH_REPLACEMENT {
  my $self = shift;
  if ( $self && !$self->{slashReplacment} ) {
		($self->{slashReplacment}) = Git::config("mediawiki.slashReplacement") || '%2F';
  }
  return $self->{slashReplacment};
}

sub SUFFIX {
	my $self = shift;
	if ( !$self->{suffix} ) {
		($self->{suffix}) = Git::config("mediawiki.fileExtension") || ".mw";
	}
	return $self->{suffix};
}

sub clean_filename {
	my $self = shift;
	my $filename = shift;
	my $sr = $self->SLASH_REPLACEMENT;
	$filename =~ s{$sr}{/}g;
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
	my $self = shift;
	my $filename = shift;
	my $sr = $self->SLASH_REPLACEMENT;
	$filename =~ s{/}{$sr}g;
	$filename =~ s/ /_/g;
	# Decode forbidden characters encoded in clean_filename
	$filename =~ s/_%_([0-9a-fA-F][0-9a-fA-F])/sprintf('%c', hex($1))/ge;
	return substr($filename, 0, NAME_MAX-length($self->SUFFIX));
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
	bless $wiki;
	$wiki->{remote_name} = $remote_name;

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

# Local Variables:
# eval: (setenv "GITPERLLIB" ".")
# tab-width: 2
# indent-tabs-mode: t
# End:
