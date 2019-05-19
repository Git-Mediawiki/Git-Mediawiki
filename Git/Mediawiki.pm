package Git::Mediawiki;

# Copyright (C) 2013  Benoit Person  <benoit.person@ensimag.imag.fr>
# Copyright (C) 2017  Antoine Beaupré
# Copyright (C) 2017  Torbjörn Lönnemark
# Copyright (C) 2018  Simon Legner
# Copyright (C) 2019  Mark A. Hershberger

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301, USA.

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
		($self->{slashReplacment}) = Git::config("mediawiki.slashReplacement")
			|| '%2F';
	}
	return $self->{slashReplacment};
}

sub SUFFIX {
	my $self = shift;
	if ( !$self->{suffix} ) {
		for(Git::config("mediawiki.fileExtension")) {
			if ( substr( $_, 0, 1 ) eq '.' ) {
				$_ = substr( $_, 1 );
			}
			$self->{suffix} = $_;
		}
		$self->{suffix} ||= "mw";

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
	$wiki->{remote_url} = $remote_url;

	$wiki->{ua}->agent(
		"git-mediawiki/$Git::Mediawiki::VERSION " . $wiki->{ua}->agent()
	);
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
			warn  qq(Logged in mediawiki user "$credential{username}".\n);
		} else {
			warn  qq(Failed to log in mediawiki user "$credential{username}" )
				. "on ${remote_url}\n";
			warn  sprintf(
				'  (error %s:%s)', $wiki->{error}->{code}, $wiki->{error}->{details}
			) . "\n";
			Git::credential(\%credential, 'reject');
			exit 1;
		}
	}

	return $wiki;
}

sub upload_file {
	my $self = shift;
	my $complete_file_name = shift;
	my $new_sha1 = shift;
	my $extension = shift;
	my $file_deleted = shift;
	my $summary = shift;
	my $newrevid;
	my $path = "File:${complete_file_name}";
	my %hashFiles = $self->get_allowed_file_extensions();
	if (!exists($hashFiles{$extension})) {
		warn  "${complete_file_name} is not a permitted file on this wiki.\n";
		warn  "Check the configuration of file uploads in your mediawiki.\n";
		return $newrevid;
	}
	# Deleting and uploading a file requires a privileged user
	if ($file_deleted) {
		my $query = {
			action => 'delete',
			title => $path,
			reason => $summary
		};
		if (!$self->edit($query)) {
			warn  "Failed to delete file on remote wiki\n";
			warn  "Check your permissions on the remote site. Error code:\n";
			warn  $self->{error}->{code} . ':' . $self->{error}->{details} . "\n";
			exit 1;
		}
	} else {
		# Don't let perl try to interpret file content as UTF-8 => use "raw"
		my $handle = Git::command_output_pipe('cat-file', 'blob', $new_sha1);
		binmode $handle, ':raw';
		my $content = <$handle>;
		if ($content ne EMPTY) {
			$self->{config}->{upload_url} =
				$self->{remote_url} . "index.php/Special:Upload";
			$self->edit({
				action => 'upload',
				filename => $complete_file_name,
				comment => $summary,
				file => [undef,
								 $complete_file_name,
								 Content => $content],
				ignorewarnings => 1,
			}, {
				skip_encoding => 1
			} ) || die $self->{error}->{code} . ':'
				. $self->{error}->{details} . "\n";
			my $last_file_page = $self->get_page({title => $path});
			$newrevid = $last_file_page->{revid};
			warn  "Pushed file: ${new_sha1} - ${complete_file_name}.\n";
		} else {
			warn  "Empty file ${complete_file_name} not pushed.\n";
		}
	}
	return $newrevid;
}

sub get_allowed_file_extensions {
	my $self = shift;

	my $query = {
		action => 'query',
		meta => 'siteinfo',
		siprop => 'fileextensions'
		};
	my $result = $self->api($query);
	my @file_extensions = map {$_->{ext}} @{$result->{query}->{fileextensions}};
	my %hashFile = map { $_ => 1 } @file_extensions;

	return %hashFile;
}


1; # Famous last words

# Local Variables:
# tab-width: 2
# indent-tabs-mode: t
# End:
