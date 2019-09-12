package Git::MediaWiki;    # -*-tab-width: 4; fill-column: 76 -*-

# vi:shiftwidth=4 tabstop=4 textwidth=76

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

use utf8;
use strict;
use warnings;
use feature qw( current_sub );

use Carp;
use Cwd;
use DateTime::Format::ISO8601;
use Git;
use IO::Handle;
use IO::Socket::SSL;
use List::MoreUtils qw(apply);
use MediaWiki::API;
use POSIX qw(NAME_MAX);
use Readonly;
use Try::Tiny;
use URI::Escape;

use autodie;

require Exporter;

use base qw(Exporter MediaWiki::API);

# Totally unstable API.
use version; our $VERSION = qv(0.02);

my @EXPORT = ();

# Methods which can be called as standalone functions as well:
my @EXPORT_OK = qw(
  $VERSION
  $EMPTY $HTTP_CODE_OK
  $HTTP_CODE_PAGE_NOT_FOUND
);

# It's not always possible to delete pages (may require some
# privileges). Deleted pages are replaced with this content.
Readonly my $DELETED_CONTENT => "[[Category:Deleted]]\n";

# It's not possible to create empty pages. New empty files in Git are
# sent with this content instead.
Readonly my $EMPTY_CONTENT => "<!-- empty page -->\n";

# used to reflect file creation or deletion in diff.
Readonly my $NULL_SHA1 => '0000000000000000000000000000000000000000';

# Used on Git's side to reflect empty edit messages on the wiki
Readonly my $EMPTY_MESSAGE => '*Empty MediaWiki Message*';

# Number of pages taken into account at once in submodule get_mw_page_list
Readonly my $SLICE_SIZE => 50;

# Number of linked mediafile to get at once in get_linked_mediafiles
# The query is split in small batches because of the MW API limit of
# the number of links to be returned (500 links max).
Readonly my $BATCH_SIZE => 10;

# Used to test for empty strings
Readonly my $EMPTY => q{};

# HTTP codes
Readonly my $HTTP_CODE_OK             => 200;
Readonly my $HTTP_CODE_PAGE_NOT_FOUND => 404;

# Debug Levels
Readonly my $DEBUG => 777;
Readonly my $NOISY => 776;

# Offset to caller
Readonly my $CALLING_PKG  => 0;
Readonly my $CALLING_FILE => 1;
Readonly my $CALLING_LINE => 2;
Readonly my $CALLING_SUBR => 3;

sub debug {
    my ( $self, $msg, $level ) = @_;

    if ( defined $ENV{DEBUG_LEVEL} && $level > $ENV{DEBUG_LEVEL} ) {
        $self->to_user->print("$msg\n");
    }
    return 1;
}

# MediaWiki filenames can contain forward slashes. This variable
# decides by which pattern they should be replaced
sub SLASH_REPLACEMENT {
    my $self = shift;
    if ( $self && !$self->{slashReplacment} ) {
        ( $self->{slashReplacment} ) =
          $self->repo->config('mediawiki.slashReplacement') || '%2F';
    }
    return $self->{slashReplacment};
}

sub SUFFIX {
    my $self = shift;
    if ( !$self->{suffix} ) {
        for ( $self->repo->config('mediawiki.fileExtension') ) {
            if ( substr( $_, 0, 1 ) eq q{.} ) {
                $_ = substr $_, 1;
            }
            $self->{suffix} = $_;
        }
        $self->{suffix} ||= 'mw';
    }
    return $self->{suffix};
}

sub _fh {
    my ( $self, $fh, $key, $mode ) = @_;

    if ($fh) {

        # Use UTF-8 to communicate with Git and the user
        binmode $fh, ':encoding(UTF-8)';
        $self->{$key} = IO::Handle->new();
        $self->{$key}->fdopen( fileno($fh), $mode );
    }

    return $self->{$key};
}

sub from_git {
    my ( $self, $fh ) = @_;

    return $self->_fh( $fh, 'from_git', 'r' );
}

sub to_user {
    my ( $self, $fh ) = @_;

    return $self->_fh( $fh, 'to_user', 'w' );
}

sub to_git {
    my ( $self, $fh ) = @_;

    return $self->_fh( $fh, 'to_git', 'w' );
}

sub _get_set {
	my ( $self, $val ) = @_;
	my $pkg = (caller 1)[$CALLING_PKG];
	my $pkg_offset = length $pkg;
	my $subr = (caller 1)[$CALLING_SUBR];
	my $key = substr $subr, $pkg_offset + 2;
	my $ret = $self->{$key};

	if ( $val ) {
		$ret = $self->{$key};
		$self->{$key} = $val;
	}

    return $ret;
}

sub repo { _get_set @_ }

sub remote_url { _get_set @_ }

sub wiki_name { _get_set @_ }

sub wiki_login { _get_set @_ }

sub wiki_password { _get_set @_ }

sub wiki_domain { _get_set @_ }

sub remote_name { _get_set @_ }

sub tracked_pages { _get_set @_ }

sub tracked_categories { _get_set @_ }

sub tracked_namespaces { _get_set @_ }

sub import_media { _get_set @_ }

sub export_media { _get_set @_ }

sub pages { _get_set @_ }

sub dumb_push { _get_set @_ }

sub fetch_strategy { _get_set @_ }

sub last_remote_revision { _get_set @_ }

sub basetimestamp {
    my ( $self, $index, $val ) = @_;

	$index ||= 0;
    my $ret = $self->{basetimestamp}->{$index};
    if ( defined $val ) {
        $self->{basetimestamp}->{$index} = $val;
    }
    return $ret;
}

sub send_to_git {
    my ($self) = shift;

    $self->to_git->print( @_ )
      or croak(q{Couldn't print!});
    return;
}

sub namespace_id {
    my ( $self, $index, $val ) = @_;

    my $ret = $self->{namespace_id}->{$index};
    if ( defined $val ) {
        $self->{namespace_id}->{$index} = $val;
    }
    return $ret;
}

sub cached_namespace {
    my ( $self, $index, $val ) = @_;

    my $ret = $self->{cached_namespace_id}->{$index};
    if ( defined $val ) {
        $self->{cached_namespace_id}->{$index} = $val;
    }
    return $ret;
}

# Return MediaWiki id for a canonical namespace name.
# Ex.: "File", "Project".
sub get_namespace_id {
    my ( $self, $name ) = @_;
    if ( !defined $self->namespace_id($name) ) {

        # Look at configuration file, if the record for that namespace is
        # already cached. Namespaces are stored in form:
        # "Name_of_namespace:Id_namespace", ex.: "File:6".
        my @temp = $self->parse_config_list('namespaceCache');
        foreach my $ns (@temp) {
            my ( $n, $id ) = split /:/smx, $ns, 2;
            if ( $id and $id eq 'notANameSpace' ) {
                $self->namespace_id( $n, undef );
            }
            else {
                $self->namespace_id( $n, $id );
            }
            $self->cached_namespace( $n, $id );
        }
    }

    if ( !defined $self->namespace_id($name) ) {
        $self->to_user->print(
            "Namespace $name not found in cache, querying the wiki ...\n");
        $self->query_namespace_id($name);
    }

    my $id = $self->namespace_id($name);

    # Store "notANameSpace" as special value for inexisting namespaces
    my $store_id = $id;

    # Store explicitly requested namespaces on disk
    if ( !$self->cached_namespace($name) ) {
        $self->add_config_list( 'namespaceCache', $name, $store_id );

        $self->cached_namespace( $name, $id );
    }
    return $id;
}

sub query_namespace_id {
    my $self = shift;
    my $name = shift;

    # NS not found => get namespace id from MW and store it in
    # configuration file.
    my $query = {
        action => 'query',
        meta   => 'siteinfo',
        siprop => 'namespaces'
    };
    my $result = $self->api($query);

    while ( my ( $id, $ns ) = each %{ $result->{query}->{namespaces} } ) {
        if ( defined( $ns->{id} ) && defined( $ns->{canonical} ) ) {
            $self->namespace_id( $ns->{canonical}, $ns->{$id} );
            if ( $ns->{q{*}} ) {

                # alias (e.g. french Fichier: as alias for canonical File:)
                $self->namespace_id( $ns->{q{*}}, $ns->{id} );
            }
        }
    }
    return;
}

sub get_namespace_id_for_page {
    my ( $self, $page ) = @_;
    if ( $page =~ /^([^:]+):/smx ) {
        my $namespace = $1;
        return $self->get_namespace_id($namespace);
    }
    else {
        return 0;    # NS_MAIN
    }
}

sub clean_filename {
    my $self     = shift;
    my $filename = shift;
    my $sr       = $self->SLASH_REPLACEMENT;
    $filename =~ s{$sr}{/}gsmx;

    # [, ], |, {, and } are forbidden by MediaWiki, even URL-encoded.
    # Do a variant of URL-encoding, i.e. looks like URL-encoding,
    # but with _ added to prevent MediaWiki from thinking this is
    # an actual special character.
    $filename =~ s/\[ [{] [}] [|] \]/sprintf("_%%_%x", ord($&))/gesmx;

    # If we use the uri escape before
    # we should unescape here, before anything

    return $filename;
}

# Filter applied on MediaWiki data before adding them to Git
sub smudge {
    my $self   = shift;
    my $string = shift;
    if ( $string eq $EMPTY_CONTENT ) {
        $string = $EMPTY;
    }

    # This \n is important. This is due to mediawiki's way to handle end
    # of files.
    return "${string}\n";
}

sub smudge_filename {
    my $self     = shift;
    my $filename = shift;
    my $sr       = $self->SLASH_REPLACEMENT;
    $filename =~ s{/}{$sr}gsmx;
    $filename =~ s/ /_/gsm;

    # Decode forbidden characters encoded in clean_filename
    $filename =~ s/_%_([[:xdigit:]]{2})/sprintf('%c', hex($1))/gesmx;
    return substr $filename, 0, NAME_MAX-length( $self->SUFFIX );
}

sub get_bool_conf {
    my ( $self, $bool ) = @_;
    return $self->repo->config_bool( 'remote.' . $self->remote_name . ".$bool" );
}

sub env_or_flag {
    my ( $self, $env, $flag, $type ) = @_;

    if ( !defined $type ) {
        $type = q{};
    }
    $type = lc $type;

    if ( defined $ENV{$env} ) {
        if ( $type eq 'bool' ) {
            if ( lc( $ENV{$env} ) eq 'true' or lc( $ENV{$env} ) eq 'yes' ) {
                return 1;
            }

            if ( lc( $ENV{$env} ) eq 'false' or lc( $ENV{$env} ) eq 'no' ) {
                return q{};
            }
        }
        return $ENV{$env};
    }
    if ( defined $flag ) {
        if ( $type eq 'bool' ) {
            return $self->repo->config_bool($flag);
        }
        elsif ( $type eq 'path' ) {
            return $self->repo->config_path($flag);
        }
        elsif ( $type eq 'int' ) {
            return $self->repo->config_int($flag);
        }
        return $self->repo->config($flag);
    }
    return;
}

sub parse_config_list {
    my ( $self, $key ) = @_;
    my @list = q{};
    for( $self->repo->config( 'remote.' . $self->remote_name . ".$key" ) ) {
        chomp ( @list = split m{\s} );
    }
    return @list;
}

sub add_config_list {
    my ( $self, $name, $key, $val ) = @_;
    $self->repo->command(
        [
            'config',                                 '--add',
            'remote.' . $self->remote_name . ".$name", qq{$key:$val}
        ]
    );
    return;
}

sub get_fetch_strategy {
    my $self = shift;

    $self->{fetch_strategy} =
      $self->repo->config( 'remote.' . $self->remote_name . '.fetchStrategy' );
    if ( !$self->{fetch_strategy} ) {
        $self->{fetch_strategy} =
          $self->repo->config('mediawiki.fetchStrategy');
    }

    if ( !$self->{fetch_strategy} ) {
        $self->{fetch_strategy} = 'by_page';
    }
    return $self->{fetch_strategy};
}

sub get_ssl_opts {
    my $self = shift;

    my %ssl_opts = ();
    if ( $self->env_or_flag( 'GIT_SSL_NO_VERIFY', 'http.sslVerify', 'bool' ) ) {
        $ssl_opts{SSL_verify_mode} = IO::Socket::SSL::SSL_VERIFY_NONE;
        $ssl_opts{verify_hostname} = 0;
    }
    my $ca_path =
      $self->env_or_flag( 'GIT_SSL_CAPATH', 'http.sslCAPath', 'path' );
    my $ca_file =
      $self->env_or_flag( 'GIT_SSL_CAINFO', 'http.sslCAInfo', 'path' );
    my $cert_file =
      $self->env_or_flag( 'GIT_SSL_CERT', 'http.sslCert', 'path' );
    my $key_file = $self->env_or_flag( 'GIT_SSL_KEY', 'http.sslKey', 'path' );

    if ($ca_path) {
        $ssl_opts{SSL_ca_path} = $ca_path;
    }
    if ($ca_file) {
        $ssl_opts{SSL_ca_file} = $ca_file;
    }
    if ($cert_file) {
        $ssl_opts{SSL_cert_file} = $cert_file;
    }
    if ($key_file) {
        $ssl_opts{SSL_key_file} = $key_file;
    }
    return %ssl_opts;
}

sub report_error {
    my ( $self, $msg, $exit_code ) = @_;

    $self->to_user->print(
        sprintf(
            '%s:  (error %s:%s)',
            $msg,
            $self->{error}->{code},
            $self->{error}->{details}
          )
          . "\n"
    );
    if ($exit_code) {
        exit $exit_code;
    }
}

sub check_credentials {
    my $self       = shift;
    my $credential = {
        'url'      => $self->{remote_url},
        'username' => $self->{wiki_login},
        'password' => $self->{wiki_password}
    };
    $self->repo->credential($credential);
    my $request = {
        lgname     => $credential->{username},
        lgpassword => $credential->{password},
        lgdomain   => $self->{wiki_domain}
    };
    if ( $self->login($request) ) {
        $self->repo->credential( $credential, 'approve' );
        $self->to_user->print(
            qq(Logged in mediawiki user "$credential->{username}".\n));
    }
    else {
        $self->repo->credential( $credential, 'reject' );
        $self->report_error(
            qq(Failed to log in mediawiki user "$credential->{username}")
              . " on $self->{remote_url}\n",
            1
        );
    }
    return 1;
}

sub new {
    my $self = shift;
    if ( ref $self ) {
        return $self;
    }
    $self = MediaWiki::API->new( {
		diagnostics => $ENV{GIT_MW_DIAGNOSTICS}
	} );
    bless $self, 'Git::MediaWiki';

    $self->from_git(*STDIN);
    $self->to_user(*STDERR);
    $self->to_git(*STDOUT);

	my $repo = Git->repository( Directory => getcwd() );
	$self->repo( $repo );
    $self->remote_name( shift );
    $self->remote_url( shift );

    $self->dumb_push(
		$self->repo->config_bool( 'remote.' . $self->remote_name . '.dumbPush' )
		|| $self->repo->config_bool( 'mediawiki.dumbPush' )
	  );

    my $wiki_name = $self->remote_url;

    # If URL is like http://user:password@example.com/, we clearly don't
    # want the password in $wiki_name. While we're there, also remove user
    # and '@' sign, to avoid author like MWUser@HTTPUser@host.com
	for ( $wiki_name ) {
		s{[^/]*://}{}smx;
		s/^.*@//smx;
	}
    $self->wiki_name( $wiki_name );

    $self->{ua}->ssl_opts( $self->get_ssl_opts );
    $self->{ua}->agent( "git-mediawiki/$VERSION " . $self->{ua}->agent() );
    $self->{ua}->conn_cache( { total_capacity => undef } );

    $self->{config}->{api_url} = $self->remote_url . '/api.php';
    $self->wiki_login(
		$self->repo->config( 'remote.' . $self->remote_name . '.mwLogin' )
	  );
    $self->wiki_password(
		$self->repo->config( 'remote.' . $self->remote_name . '.mwPassword' )
	  );
    $self->wiki_domain(
		$self->repo->config( 'remote.' . $self->remote_name . '.mwDomain' )
	  );
    if ( $self->wiki_login ) {
        $self->check_credentials;
    }

    # Accept both space-separated and multiple keys in config file.
    # Spaces should be written as _ anyway because we'll use chomp.
    $self->{tracked_pages}      = [ $self->parse_config_list('pages') ];
    $self->{tracked_categories} = [ $self->parse_config_list('categories') ];
    $self->{tracked_namespaces} = [ $self->parse_config_list('namespaces') ];

    # Import media files on pull
    $self->{importmedia} = $self->get_bool_conf('mediaimport');

    # Export media files on push
    $self->{exportmedia} = $self->get_bool_conf('mediaexport');

    # Import only last revisions (both for clone and fetch)
    $self->{shallow_import} = $self->get_bool_conf('shallow');

    # Fetch (clone and pull) by revisions instead of by pages. This behavior
    # is more efficient when we have a wiki with lots of pages and we fetch
    # the revisions quite often so that they concern only few pages.
    # Possible values:
    # - by_rev: perform one query per new revision on the remote wiki
    # - by_page: query each tracked page for new revision
    $self->{fetch_strategy} = $self->get_fetch_strategy;

    # Remember the timestamp corresponding to a revision id.
    $self->{basetimestamp} = {};

    return $self;
}

sub upload_file {
    my ( $self, $complete_file_name, $new_sha1, $extension, $file_deleted,
        $summary )
      = @_;
    my $newrevid;
    my $path       = "File:${complete_file_name}";
    my %hash_files = $self->get_allowed_file_extensions();

    if ( !exists $hash_files{$extension} ) {
        $self->to_user->print(
            "${complete_file_name} is not a permitted file on this wiki.\n");
        $self->to_user->print(
            "Check the configuration of file uploads in your mediawiki.\n");
        return $newrevid;
    }

    # Deleting and uploading a file requires a privileged user
    if ($file_deleted) {
        my $query = {
            action => 'delete',
            title  => $path,
            reason => $summary
        };
        if ( !$self->edit($query) ) {
            $self->report_error(
                "Failed to delete file on remote wiki\n"
                  . 'Check your permissions on the remote ' . 'site.',
                1
            );
        }
    }
    else {
        # Don't let perl try to interpret file content as UTF-8 => use "raw"
        my $handle =
          $self->repo->command_output_pipe( 'cat-file', 'blob', $new_sha1 );
        binmode $handle, ':raw';
        my $content = <$handle>;
        if ( $content ne $EMPTY ) {
            $self->{config}->{upload_url} =
              $self->{remote_url} . 'index.php/Special:Upload';
            $self->edit(
                {
                    action   => 'upload',
                    filename => $complete_file_name,
                    comment  => $summary,
                    file => [ undef, $complete_file_name, Content => $content ],
                    ignorewarnings => 1,
                },
                {
                    skip_encoding => 1
                }
              )
              || $self->report_error( "Couldn't push file: $complete_file_name",
                1 );
            my $last_file_page = $self->get_page( { title => $path } );
            $newrevid = $last_file_page->{revid};
            $self->to_user->print(
                "Pushed file: ${new_sha1} - ${complete_file_name}.\n");
        }
        else {
            $self->to_user->print(
                "Empty file ${complete_file_name} not pushed.\n");
        }
    }
    return $newrevid;
}

sub get_allowed_file_extensions {
    my $self = shift;

    my $query = {
        action => 'query',
        meta   => 'siteinfo',
        siprop => 'fileextensions'
    };
    my $result = $self->api($query);
    my @file_extensions =
      map { $_->{ext} } @{ $result->{query}->{fileextensions} };
    my %hash_file = map { $_ => 1 } @file_extensions;

    return %hash_file;
}

# Get the list of pages to be fetched according to configuration.
sub get_pages {
    my ($self) = shift;

    # Don't fetch twice
    if ( $self->pages ) {
        return $self->pages;
    }

    $self->to_user->print("Listing pages on remote wiki...\n");

    my $user_defined;
    if ( $self->tracked_pages ) {
        $user_defined = 1;

        # The user provided a list of pages titles, but we
        # still need to query the API to get the page IDs.
        $self->get_tracked_pages;
    }
    if ( $self->tracked_categories ) {
        $user_defined = 1;
        $self->get_tracked_categories;
    }
    if ( $self->tracked_namespaces ) {
        $user_defined = 1;
        $self->get_tracked_namespaces;
    }
    if ( !$user_defined ) {
        $self->get_all_pages;
    }
    if ( $self->import_media ) {
        $self->to_user->print("Getting media files for selected pages...\n");
        if ($user_defined) {
            $self->get_linked_mediafiles;
        }
        else {
            $self->get_all_mediafiles;
        }
    }
    if ( scalar $self->{pages} ) {
        $self->to_user->print(
            scalar( keys %{ $self->pages } ) . " pages found.\n" );
    }
    else {
        $self->to_user->print("no pages found.\n");
    }
    return $self->pages;
}

# Get the last remote revision concerning the tracked pages and the tracked
# categories.
sub get_last_remote_revision {
    my $self        = shift;
    my $max_rev_num = 0;

    $self->to_user->print("Getting last revision id on tracked pages...\n");

  PAGE:
    foreach my $page ( $self->get_pages ) {
        my $id = $page->{pageid};
        if ( !defined $id ) {
            next PAGE;
        }
        my $query = {
            action  => 'query',
            prop    => 'revisions',
            rvprop  => 'ids|timestamp',
            pageids => $id,
        };

        my $result = $self->api($query);

        my $lastrev = pop @{ $result->{query}->{pages}->{$id}->{revisions} };

        $self->basetimestamp( $lastrev->{revid}, $lastrev->{timestamp} || 0 );

        $max_rev_num = (
              $lastrev->{revid} > $max_rev_num
            ? $lastrev->{revid}
            : $max_rev_num
        );
    }

    $self->to_user->print( "Last remote revision found is $max_rev_num.\n" );
    return $max_rev_num;
}

sub import_ref_by_revs {
    my $self       = shift;
    my $fetch_from = shift;
    my $pages      = $self->get_pages();

    my $last_remote  = $self->get_last_global_remote_rev();
    my $revision_ids = [ $fetch_from .. $last_remote ];
    return $self->import_revids( $fetch_from, $revision_ids, $pages );
}

# Import revisions given in second argument (array of integers).
# Only pages appearing in the third argument (hash indexed by page titles)
# will be imported.
sub import_revids {
    my $self         = shift;
    my $fetch_from   = shift;
    my $revision_ids = shift;
    my $pages        = shift;

    my $n              = 0;
    my $n_actual       = 0;
    my $last_timestamp = 0;    # Placeholder in case $rev->timestamp is
                               # undefined

    foreach my $pagerevid ( @{$revision_ids} ) {

        # Count page even if we skip it, since we display
        # $n/$total and $total includes skipped pages.
        $n++;

        # fetch the content of the pages
        my $query = {
            action => 'query',
            prop   => 'revisions',
            rvprop => 'content|timestamp|comment|user|ids',
            revids => $pagerevid,
        };

        my $result = $self->api($query);

        if ( !$result ) {
            die "Failed to retrieve modified page for revision $pagerevid\n";
        }

        if ( defined( $result->{query}->{badrevids}->{$pagerevid} ) ) {

            # The revision id does not exist on the remote wiki.
            next;
        }

        if ( !defined( $result->{query}->{pages} ) ) {
            die "Invalid revision ${pagerevid}.\n";
        }

        my @result_pages = values %{ $result->{query}->{pages} };
        my $result_page  = $result_pages[0];
        my $rev          = $result_pages[0]->{revisions}->[0];

        my $page_title = $result_page->{title};

        if ( !exists( $pages->{$page_title} ) ) {
            $self->to_user->print(
                "${n}/",
                scalar( @{$revision_ids} ),
                ": Skipping revision #$rev->{revid} of ${page_title}\n"
            );
            next;
        }

        $n_actual++;

        my %commit;
        $commit{mw_revision} = $rev->{revid};
        $commit{author}      = $rev->{user} || 'Anonymous';
        $commit{comment}     = $rev->{comment} || $EMPTY_MESSAGE;
        $commit{title}       = $self->smudge_filename($page_title);
        $commit{content}     = $self->smudge( $rev->{q{*}} );

        if ( !defined( $rev->{timestamp} ) ) {
            $last_timestamp++;
        }
        else {
            $last_timestamp = $rev->{timestamp};
        }
        $commit{date} =
          DateTime::Format::ISO8601->parse_datetime($last_timestamp);

        # Differentiates classic pages and media files.
        my ( $namespace, $filename ) = $page_title =~ /^([^:]*):(.*)$/smx;
        my %mediafile;
        if ($namespace) {
            my $id = $self->get_namespace_id($namespace);
            if ( $id && $id == $self->get_namespace_id('File') ) {
                %mediafile =
                  $self->get_mediafile_for_page_revision( $filename,
                    $rev->{timestamp} );
            }
        }

        # If this is a revision of the media page for new version
        # of a file do one common commit for both file and media page.
        # Else do commit only for that page.
        $self->to_user->print( "${n}/"
              . scalar( @{$revision_ids} )
              . ": Revision #$rev->{revid} of $commit{title}\n" );
        $self->import_file_revision( \%commit, ( $fetch_from == 1 ),
            $n_actual, \%mediafile );
    }

    return $n_actual;
}

# Get the last remote revision without taking in account which pages are
# tracked or not. This function makes a single request to the wiki thus
# avoid a loop onto all tracked pages. This is useful for the fetch-by-rev
# option.
sub get_last_global_remote_rev {
    my $self = shift;

    my $query = {
        action  => 'query',
        list    => 'recentchanges',
        prop    => 'revisions',
        rclimit => '1',
        rcdir   => 'older',
    };
    my $result = $self->api($query);
    return $result->{query}->{recentchanges}[0]->{revid};
}

# Clean content before sending it to MediaWiki
sub clean {
    my $self         = shift;
    my $string       = shift;
    my $page_created = shift;

    # MediaWiki does not allow blank space at the end of a page and ends
    # with a single \n.  This function right trims a string and adds a
    # \n at the end to follow this rule
    $string =~ s/\s+$//smx;
    if ( $string eq $EMPTY && $page_created ) {

        # Creating empty pages is forbidden.
        $string = $EMPTY_CONTENT;
    }
    return $string . "\n";
}

sub push_file {
    my $self      = shift;
    my $diff_info = shift;

    # Filename, including the extension
    my $complete_file_name = shift;

    # Commit message
    my $summary = shift;

    # MediaWiki revision number. Keep the previous one by default,
    # in case there's no edit to perform.
    my $oldrevid = shift;
    my $newrevid;

    # $diff_info contains a string in this format:
    # 100644 100644 <sha1_of_blob_before_commit> <sha1_of_blob_now> <status>
    my @diff_info_split = split /[ \t]/smx, $diff_info;
    if ( $summary eq $EMPTY_MESSAGE ) {
        $summary = $EMPTY;
    }

    my $new_sha1     = $diff_info_split[3];
    my $old_sha1     = $diff_info_split[2];
    my $page_created = ( $old_sha1 eq $NULL_SHA1 );
    my $page_deleted = ( $new_sha1 eq $NULL_SHA1 );
    $complete_file_name = $self->clean_filename($complete_file_name);

    my ( $title, $extension ) = $complete_file_name =~ /^(.*?).?([^.]*)$/smx;
    if ( !defined $extension ) {
        $extension = $EMPTY;
    }
    if ( $extension eq $self->SUFFIX ) {
        my $ns = $self->get_namespace_id_for_page($complete_file_name);
        if (   $ns
            && $ns == $self->get_namespace_id('File')
            && !$self->export_media )
        {
            $self->to_user->print(
                "Ignoring media file related page: ${complete_file_name}\n");
            return ( $oldrevid, 'ok' );
        }
        my $file_content;
        if ($page_deleted) {

            # Deleting a page usually requires
            # special privileges. A common
            # convention is to replace the page
            # with this content instead:
            $file_content = $DELETED_CONTENT;
        }
        else {
            $file_content =
              $self->repo->command( [ 'cat-file', 'blob', ${new_sha1} ] );
        }

        my $result = $self->edit(
            {
                action        => 'edit',
                summary       => $summary,
                title         => $title,
                basetimestamp => $self->basetimestamp($oldrevid, 0),
                text          => $self->clean( $file_content, $page_created ),
            },
            {
                skip_encoding =>
                  1    # Helps with names with accentuated characters
            }
        );
        if ( !$result ) {
            if ( $self->{error}->{code} == MediaWiki::API::ERR_API ) {

                # edit conflicts, considered as non-fast-forward
                $self->report_error('Edit conflict');
                return ( $oldrevid, 'non-fast-forward' );
            }
            else {
                # Other errors. Shouldn't happen => just die()
                $self->report_error( 'Fatal', 1 );
            }
        }
        $newrevid = $result->{edit}->{newrevid};
        $self->to_user->print("Pushed file: ${new_sha1} - ${title}\n");
    }
    elsif ( $self->export_media ) {
        $newrevid =
          $self->upload_file( $complete_file_name, $new_sha1,
            $extension, $page_deleted, $summary );
    }
    else {
        $self->to_user->print("Ignoring media file ${title}\n");
    }
    $newrevid = ( $newrevid or $oldrevid );
    return ( $newrevid, 'ok' );
}

sub cmd_push {
    my $self = shift;

    # multiple push statements can follow each other
    my @refsspecs = ( shift, $self->get_more_refs('push') );
    my $pushed;
    for my $refspec (@refsspecs) {
        my ( $force, $local, $remote ) =
          $refspec =~ /^([+])?([^:]*):([^:]*)$/smx
          or die
          "Invalid refspec for push. Expected <src>:<dst> or +<src>:<dst>\n";
        if ($force) {
            $self->to_user->print(
                "Warning: forced push not allowed on a MediaWiki.\n");
        }
        if ( $local eq $EMPTY ) {
            $self->to_user->print(
                "Cannot delete remote branch on a MediaWiki\n");
            $self->send_to_git("error $remote cannot delete\n");
            next;
        }
        if ( $remote ne 'refs/heads/master' ) {
            $self->to_user->print(
                    q{Only push to the branch 'master' is supported }
                  . "on a MediaWiki\n" );
            $self->send_to_git("error ${remote} only master allowed\n");
            next;
        }
        if ( $self->push_revision( $local, $remote ) ) {
            $pushed = 1;
        }
    }

    # Notify Git that the push is done
    $self->send_to_git("\n");

    if ( $pushed && $self->dumb_push ) {
        $self->to_user->print(<<"EOF");
Just pushed some revisions to MediaWiki.
The pushed revisions now have to be re-imported, and your current branch
needs to be updated with these re-imported commits. You can do this with

  git pull --rebase

EOF
    }
    return;
}

sub find_path_to_commit {
    my $self        = shift;
    my $local       = shift;
    my $remote      = shift;
    my $head_sha1   = shift;
    my $parsed_sha1 = shift;

    # Find a path from last MediaWiki commit to pushed commit
    $self->to_user->print("Computing path from local to remote ...\n");
    my @local_ancestry = split /\n/smx,
      $self->repo->command(
        [ 'rev-list', '--boundary', '--parents', $local, "^${parsed_sha1}" ],
        STDERR => 0 );
    my %local_ancestry;
    foreach my $line (@local_ancestry) {
        my ( $child, $parents ) =
          $line =~ /^-?([[:xdigit:]]+) ([[:xdigit:] ]+)/smx;
        if ( $child or $parents ) {
            foreach my $parent ( split / /sm, $parents ) {
                $local_ancestry{$parent} = $child;
            }
        }
        elsif ( !$line =~ /^([[:xdigit:]]+)/smx ) {
            die "Unexpected output from git rev-list: ${line}\n";
        }
    }
    while ( $parsed_sha1 ne $head_sha1 ) {
        my $child = $local_ancestry{$parsed_sha1};
        if ( !$child ) {
            $self->to_user->print(<<"EOF");
Cannot find a path in history from remote commit to last commit

EOF
            return $self->error_non_fast_forward($remote);
        }
        return [ $parsed_sha1, $child ];
    }
    return;
}

sub get_entire_history {
    my $self  = shift;
    my $local = shift;

    # No remote mediawiki revision. Export the whole
    # history (linearized with --first-parent)
    $self->to_user->print(
        "Warning: no common ancestor, pushing complete history\n");
    my $history =
      $self->repo->command(
        [ 'rev-list', '--first-parent', '--children', $local ] );
    my @history = split /\n/smx, $history;
    @history = @history[ 1 .. $#history ];
    my @ret;
    foreach my $line ( reverse @history ) {
        my @commit_info_split = split /[ \n]/smx, $line;
        push @ret, \@commit_info_split;
    }
    return @ret;
}

sub push_revision {
    my $self  = shift;
    my $local = shift;

    # actually, this has to be "refs/heads/master" at this point.
    my $remote            = shift;
    my $last_local_revid  = $self->get_last_local_revision();
    my $last_remote_revid = $self->get_last_remote_revision();
    my $mw_revision       = $last_remote_revid;

    # Get sha1 of commit pointed by local HEAD
    my $head_sha1 =
      $self->repo->command( [ 'rev-parse', $local ], STDERR => 0 );

    # Get sha1 of commit pointed by remotes/$remotename/master
    chomp(
        my $remoteorigin_sha1 = $self->repo->command(
            [ 'rev-parse', 'refs/remotes/' . $self->remote_name . '/master' ],
            STDERR => 0
        )
    );

    if ( $last_local_revid > 0 && $last_local_revid < $last_remote_revid ) {
        return $self->error_non_fast_forward($remote);
    }

    if ( $head_sha1 eq $remoteorigin_sha1 ) {

        # nothing to push
        return 0;
    }

    # Get every commit in between HEAD and refs/remotes/origin/master,
    # including HEAD and refs/remotes/origin/master
    my @commit_pairs = ();
    if ( $last_local_revid > 0 ) {
        push @commit_pairs,
          $self->find_path_to_commit( $local, $remote, $head_sha1,
            $remoteorigin_sha1 );
    }
    else {
        push @commit_pairs, $self->get_entire_history($local);
    }

    $self->push_commits( $remote, \@commit_pairs );
    $self->send_to_git("ok $remote\n");
    return 1;
}

sub push_commits {
    my ($self, $remote, $commits) = @_;

    foreach my $commit_info_split (@{$commits}) {
		if ( ref $commit_info_split eq 'ARRAY' ) {
			my $sha1_child = @{$commit_info_split}[0];
			my $sha1       = @{$commit_info_split}[1];
			my $diff_infos =
			  $self->repo->command(
				  [ 'diff-tree', '-r', '--raw', '-z', ${sha1_child}, ${sha1} ] );

			# TODO: we could detect rename, and encode them with a #redirect
			# TODO: on the wiki. For now, it's just a delete+add
			my @diff_info_list = split /\0/smx, $diff_infos;

			# Keep the subject line of the commit message as mediawiki comment
			# for the revision
			my $commit_msg =
			  $self->repo->command(
				  [ 'log', '--no-walk', '--format="%s"', ${sha1} ] );
			chomp $commit_msg;

			# Push every blob
			$self->push_every_blob( $remote, $sha1, $commit_msg, @diff_info_list );
		}
	}
    return;
}

sub push_every_blob {
    my $self           = shift;
    my $remote         = shift;
    my $sha1           = shift;
    my $commit_msg     = shift;
    my @diff_info_list = @_;

    while (@diff_info_list) {
        my ( $mw_revision, $status );

        # git diff-tree -z gives an output like
        # <metadata>\0<filename1>\0
        # <metadata>\0<filename2>\0
        # and we've split on \0.
        my $info = shift @diff_info_list;
        my $file = shift @diff_info_list;
        ( $mw_revision, $status ) =
          $self->push_file( $info, $file, $commit_msg, $mw_revision );
        if ( $status eq 'non-fast-forward' ) {

            # we may already have sent part of the
            # commit to MediaWiki, but it's too
            # late to cancel it. Stop the push in
            # the middle, but still give an
            # accurate error message.
            return $self->error_non_fast_forward($remote);
        }
        if ( $status ne 'ok' ) {
            die "Unknown error from mw_push_file()\n";
        }
        if ( !$self->dumb_push ) {
			$self->add_note( $sha1, qq(mediawiki_revision: $mw_revision) );
        }
    }
    return;
}

sub get_note {
	my ( $self ) = @_;
	my $note;

    try {
        $note = $self->repo->command(
            [
                'notes', '--ref=' . $self->remote_name . '/mediawiki',
                'show',  'refs/mediawiki/' . $self->remote_name . '/master'
            ],
            STDERR => 0
        );
    };

	return $note;
}

sub add_note {
	my ( $self, $sha1, $note ) = @_;

	return $self->repo->command( [
		'notes', '--ref=' . $self->remote_name . '/mediawiki',
		'add',   '-f', '-m', $note, $sha1
	  ] );
}

sub get_tracked_categories {
    my ( $self, $pages ) = @_;
    foreach my $category ( $self->tracked_categories ) {
        if ( index( $category, q{:} ) < 0 ) {

            # MediaWiki requires the Category
            # prefix, but let's not force the user
            # to specify it.
            $category = "Category:${category}";
        }
        my $mw_pages = $self->list(
            {
                action  => 'query',
                list    => 'categorymembers',
                cmtitle => $category,
                cmlimit => 'max'
            }
          )
          or $self->report_error(
            "Could not query category members for '$category'", 1 );
        foreach my $page ( @{$mw_pages} ) {
            $pages->{ $page->{title} } = $page;
        }
    }
    return;
}

sub get_tracked_namespaces {
    my ( $self, $pages ) = @_;
    foreach my $local_namespace ( $self->tracked_namespaces ) {
        my $namespace_id;
        if ( $local_namespace eq '(Main)'
            or scalar $local_namespace == 0 )
        {
            $namespace_id = 0;
        }
        else {
            $namespace_id = $self->get_namespace_id($local_namespace);
        }

        # virtual namespaces don't support allpages
        next if !defined($namespace_id) || $namespace_id < 0;
        my $mw_pages = $self->list(
            {
                action      => 'query',
                list        => 'allpages',
                apnamespace => $namespace_id,
                aplimit     => 'max'
            }
          )
          || $self->report_error(
            "Could not list all pages in namespace '$local_namespace", 1 );
        $self->to_user->print(
                "$#{$mw_pages} found in namespace $local_namespace "
              . "($namespace_id)\n" );
        foreach my $page ( @{$mw_pages} ) {
            $pages->{ $page->{title} } = $page;
        }
    }
    return;
}

sub get_all_pages {
    my ($self) = @_;

    # No user-provided list, get the list of pages from the API.
    $self->debug( 'Getting all pages...' );
    my $mw_pages = $self->list(
        {
            action  => 'query',
            list    => 'allpages',
            aplimit => 'max'
        }
    );
    if ( !defined $mw_pages ) {
        $self->fatal_error('get the list of wiki pages');
    }
    $self->debug( 'Found ' . scalar @{$mw_pages} . ' pages...', $DEBUG );
    foreach my $page ( @{$mw_pages} ) {
        $self->debug( 'Adding "' . $page->{title} . '" to the queue...',
            $DEBUG );
        $self->{pages}->{ $page->{title} } = $page;
    }

    return $self->pages;
}

# queries the wiki for a set of pages. Meant to be used within a loop
# querying the wiki for slices of page list.
sub get_first_pages {
    my $self       = shift;
    my $some_pages = shift;
    my @some_pages = @{$some_pages};

    my $pages = shift;

    # pattern 'page1|page2|...' required by the API
    my $titles = join q{|}, @some_pages;

    my $mw_pages = $self->api(
        {
            action => 'query',
            titles => $titles,
        }
    );
    if ( !defined $mw_pages ) {
        $self->fatal_error('query the list of wiki pages');
    }
    while ( my ( $id, $page ) = each %{ $mw_pages->{query}->{pages} } ) {
        if ( $id < 0 ) {
            $self->to_user->print(
                "Warning: page $page->{title} not found on wiki\n");
        }
        else {
            $pages->{ $page->{title} } = $page;
        }
    }
    return;
}

sub parse_command {
    my ( $self, $line ) = @_;

    my @arg = split / /sm, $line;
    if ( !defined $arg[0] ) {
        return 0;
    }
    my $cmd    = shift @arg;
    my $lookup = {
        'capabilities' => 0,
        'list'         => 1,
        'import'       => 1,
        'option'       => 2,
        'push'         => 1,
    };

    if ( exists $lookup->{$cmd} ) {
        my $count = $lookup->{$cmd};
        if ( scalar @arg > $lookup->{$cmd} ) {
            die "Too many arguments for $cmd\n";
        }
        my $cmd_method = "cmd_$cmd";
        $self->$cmd_method(@arg);
    }
    else {
        $self->to_user->print("Unknown command ($cmd). Aborting...\n");
        return 0;
    }
    return 1;
}

sub fatal_error {
    my ( $self, $action ) = @_;
    my $url = $self->remote_url;

    $self->to_user->print("fatal: could not $action.\n");
    $self->to_user->print("fatal: '$url' does not appear to be a mediawiki\n");
    if ( $url =~ /^https/smx ) {
        $self->to_user->print(
            "fatal: make sure '$url/api.php' is a valid page\n");
        $self->to_user->print(
            "fatal: and the SSL certificate is correct or set\n");
        $self->to_user->print(
            "fatal: the appropriate environment variables or flags.\n");
    }
    else {
        $self->to_user->print(
            "fatal: make sure '$url/api.php' is a valid page.\n");
    }
    $self->report_error( 'fatal', 1 );
    exit;
}

## Functions for listing pages on the remote wiki
sub get_tracked_pages {
    my ( $self, $pages ) = @_;

    return $self->get_page_list($pages);
}

sub get_page_list {
    my ( $self, $page_list, $pages );

    my @some_pages = @{$page_list};
    while (@some_pages) {
        my $last_page = $SLICE_SIZE;
        if ( $#some_pages < $last_page ) {
            $last_page = $#some_pages;
        }
        my @slice = @some_pages[ 0 .. $last_page ];
        $self->get_first_pages( \@slice, $pages );
        @some_pages = @some_pages[ ( $SLICE_SIZE + 1 ) .. $#some_pages ];
    }
    return @some_pages;
}

sub get_all_mediafiles {
    my ( $self, $pages ) = @_;

    # Attach list of all pages for media files from the API,
    # they are in a different namespace, only one namespace
    # can be queried at the same moment
    my $mw_pages = $self->list(
        {
            action      => 'query',
            list        => 'allpages',
            apnamespace => $self->get_namespace_id('File'),
            aplimit     => 'max'
        }
    );
    if ( !defined $mw_pages ) {
        my $url = $self->remote_url;
        $self->to_user->print(<<"EOF");
fatal: could not get the list of pages for media files.
fatal: '$url' does not appear to be a mediawiki
fatal: make sure '$url/api.php' is a valid page.
EOF
        exit 1;
    }
    foreach my $page ( @{$mw_pages} ) {
        $pages->{ $page->{title} } = $page;
    }
    return;
}

sub get_linked_mediafiles {
    my ( $self, $pages ) = @_;
    my @titles = map { $_->{title} } values %{$pages};

    my $batch = $BATCH_SIZE;
    while (@titles) {
        if ( $#titles < $batch ) {
            $batch = $#titles;
        }
        my @slice = @titles[ 0 .. $batch ];

        # pattern 'page1|page2|...' required by the API
        my $mw_titles = join q{|}, @slice;

        # Media files could be included or linked from
        # a page, get all related
        my $query = {
            action      => 'query',
            prop        => 'links|images',
            titles      => $mw_titles,
            plnamespace => $self->get_namespace_id('File'),
            pllimit     => 'max'
        };
        my $result = $self->api($query);

        while ( my ( $id, $page ) = each %{ $result->{query}->{pages} } ) {
            my @media_titles;
            if ( defined( $page->{links} ) ) {
                my @link_titles =
                  map { $_->{title} } @{ $page->{links} };
                push @media_titles, @link_titles;
            }
            if ( defined( $page->{images} ) ) {
                my @image_titles =
                  map { $_->{title} } @{ $page->{images} };
                push @media_titles, @image_titles;
            }
            if (@media_titles) {
                $self->page_list( \@media_titles, $pages );
            }
        }

        @titles = @titles[ ( $batch + 1 ) .. $#titles ];
    }
    return;
}

sub get_mediafile_for_page_revision {
    my $self = shift;

    # Name of the file on Wiki, with the prefix.
    my $filename  = shift;
    my $timestamp = shift;
    my %mediafile;

    # Search if on a media file with given timestamp exists on
    # MediaWiki. In that case download the file.
    my $query = {
        action  => 'query',
        prop    => 'imageinfo',
        titles  => "File:${filename}",
        iistart => $timestamp,
        iiend   => $timestamp,
        iiprop  => 'timestamp|archivename|url',
        iilimit => 1
    };
    my $result = $self->api($query);

    my ( $fileid, $file ) = each %{ $result->{query}->{pages} };

    # If not defined it means there is no revision of the file for
    # given timestamp.
    if ( defined( $file->{imageinfo} ) ) {
        my $fileinfo = pop @{ $file->{imageinfo} };

        # MediaWiki::API's download function doesn't support https URLs
        # and can't download old versions of files.
        $self->to_user->print( "\tDownloading file $filename, "
              . "version $fileinfo->{timestamp}\n" );
        my $content = $self->download_mediafile( $fileinfo->{url} );
        if ( defined $content ) {
            $mediafile{content}   = $content;
            $mediafile{title}     = $filename;
            $mediafile{timestamp} = $fileinfo->{timestamp};
        }
        else {
            $self->to_user->print(
                "\tFAILED downloading $fileinfo->{url}! Skipping!\n");
        }
    }
    return %mediafile;
}

sub download_mediafile {
    my $self         = shift;
    my $download_url = shift;
    my $url          = $self->remote_url;
    my $wiki_name    = $self->wiki_name;

    my $response = $self->{ua}->get($download_url);
    if ( $response->code == $HTTP_CODE_OK ) {

        # It is tempting to return
        # $response->decoded_content({charset => "none"}), but
        # when doing so, utf8::downgrade($content) fails with
        # "Wide character in subroutine entry".
        $response->decode();
        return $response->content();
    }
    elsif ( ( $download_url !~ /^\Q$url\E/smx )
        and ( $download_url =~ m{\Q$wiki_name\E/}smx ) )
    {
        # We may have failed because the URL returned from the API
        # is missing something (e.g. "user:password@"). Retry with a
        # corresponding URL constructed from our original $url.
        $download_url =~ s{.*?\Q$wiki_name\E/}{$url/}smx;
        return $self->download_mediafile($download_url);
    }
    else {
        $self->to_user->print("Error downloading mediafile from :\n");
        $self->to_user->print("URL: ${download_url}\n");
        $self->to_user->print(
            sprintf(
                'Server response: %s %s' . $response->code,
                $response->message
              )
              . "\n"
        );
        return;
    }
}

sub get_last_local_revision {
    my $self = shift;

    # Get note regarding last mediawiki revision
    my $note = $self->get_note();

    my $lastrevision_number;
    if ( !defined $note ) {
        $self->to_user->print("No previous mediawiki revision found.\n");
        $lastrevision_number = 0;
    }
    else {
        my @note_info = split / /sm, $note;

        # Notes are formatted : mediawiki_revision: #number
        $lastrevision_number = $note_info[1];
        chomp $lastrevision_number;
        $self->to_user->print( 'Last local mediawiki revision found is '
              . $lastrevision_number
              . ".\n" );
    }
    return $lastrevision_number;
}

sub literal_data {
    my ( $self, $content ) = @_;
    $self->send_to_git( 'data ', bytes::length($content), "\n", $content );
    return;
}

sub literal_data_raw {

    # Output possibly binary content.
    my ( $self, $content ) = @_;

    # Avoid confusion between size in bytes and in characters
    utf8::downgrade($content);
    binmode STDOUT, ':raw';
    $self->send_to_git( 'data ', bytes::length($content), "\n", $content );
    binmode STDOUT, ':encoding(UTF-8)';
    return;
}

sub cmd_capabilities {
    my ($self) = @_;

    # Revisions are imported to the private namespace
    # refs/mediawiki/$remotename/ by the helper and fetched into
    # refs/remotes/$remotename later by fetch.
    $self->send_to_git(
        'refspec refs/heads/*:refs/mediawiki/' . $self->remote_name . "/*\n" );
    $self->send_to_git("import\n");
    $self->send_to_git("list\n");
    $self->send_to_git("push\n");
    if ( $self->dumb_push ) {
        $self->send_to_git("no-private-update\n");
    }
    $self->send_to_git("\n");
    return;
}

sub cmd_list {
    my ($self) = @_;

    # MediaWiki does not have branches, we consider one branch arbitrarily
    # called master, and HEAD pointing to it.
    $self->send_to_git("? refs/heads/master\n");
    $self->send_to_git("\@refs/heads/master HEAD\n");
    $self->send_to_git("\n");
    return;
}

sub cmd_option {
    my ( $self, $arg1, $arg2 ) = @_;
    if ( $arg1 eq $EMPTY || $arg2 eq $EMPTY ) {
        die "Invalid arguments for option\n";
    }

    $self->to_user->print(
        "remote-helper command 'option $arg1' not yet implemented\n");
    $self->send_to_git("unsupported\n");
    return;
}

sub fetch_revisions_for_page {
    my $self       = shift;
    my $page       = shift;
    my $id         = shift;
    my $fetch_from = shift;
    my @page_revs  = ();
    my $query      = {
        action    => 'query',
        prop      => 'revisions',
        rvprop    => 'ids',
        rvdir     => 'newer',
        rvstartid => $fetch_from,
        rvlimit   => 500,
        pageids   => $id,

        # Let MediaWiki know that we support the latest API.
        continue => q{},
    };

    my $revnum = 0;

    # Get 500 revisions at a time due to the mediawiki api limit
    while (1) {
        my $result = $self->api($query);

        # Parse each of those 500 revisions
        foreach
          my $revision ( @{ $result->{query}->{pages}->{$id}->{revisions} } )
        {
            my $page_rev_ids;
            $page_rev_ids->{pageid} = $page->{pageid};
            $page_rev_ids->{revid}  = $revision->{revid};
            push @page_revs, $page_rev_ids;
            $revnum++;
        }

        if ( $result->{'query-continue'} ) {    # For legacy APIs
            $query->{rvstartid} =
              $result->{'query-continue'}->{revisions}->{rvstartid};
        }
        elsif ( $result->{continue} ) {         # For newer APIs
            $query->{rvstartid} = $result->{continue}->{rvcontinue};
            $query->{continue}  = $result->{continue}->{continue};
        }
        else {
            last;
        }
    }
    if ( $self->shallow_import && @page_revs ) {
        $self->to_user->print("  returning 1 revision (shallow import).\n");
        my @sorted = sort { $a->{revid} <=> $b->{revid} } @page_revs;

        @page_revs = reverse @sorted;
        return $page_revs[0];
    }
    $self->to_user->print("  Found ${revnum} revision(s).\n");
    return @page_revs;
}

sub fetch_revisions {
    my ( $self, $pages, $fetch_from ) = shift;

    my @revisions = ();
    my $n         = 1;
    my $total     = scalar keys %{$pages};
    foreach my $title ( keys %{$pages} ) {
        my $id = $pages->{$title}->{pageid};
        $self->to_user->print("page ${n}/$total: $title\n");
        $n++;
        my @page_revs =
          $self->fetch_revisions_for_page( $pages->{$title}, $id, $fetch_from );
        @revisions = ( @page_revs, @revisions );
    }

    return ( $n, @revisions );
}

sub fe_escape_path {
    my $self = shift;
    my $path = shift;
    $path =~ s/\\/\\\\/gsmx;
    $path =~ s/"/\\"/gsmx;
    $path =~ s/\n/\\n/gsmx;
    return qq("${path}");
}

sub format_committer_name {
    my ( $self, $author, $wiki, $date ) = @_;
    return sprintf( 'committer %s <%s@%s> %s +0000',
        $author, $author, $wiki, $date->epoch )
      . "\n";
}

sub import_file_revision {
    my ( $self, $commit, $full_import, $n, $mediafile ) = @_;
    my %commit = %{$commit};
    my %mediafile;
    if ($mediafile) {
        %mediafile = %{$mediafile};
    }

    my $title   = $commit{title};
    my $comment = $commit{comment};
    my $content = $commit{content};
    my $author  = $commit{author};
    my $date    = $commit{date};

    $self->send_to_git(
        'commit refs/mediawiki/' . $self->remote_name . "/master\n" );
    $self->send_to_git("mark :${n}\n");
    $self->send_to_git(
        $self->format_committer_name( $author, $self->wiki_name, $date ) );
    $self->literal_data($comment);

    # If it's not a clone, we need to know where to start from
    if ( !$full_import && $n == 1 ) {
        $self->send_to_git(
            'from refs/mediawiki/' . $self->remote_name . "/master^0\n" );
    }
    if ( $content ne $DELETED_CONTENT ) {
        $self->send_to_git( 'M 644 inline '
              . $self->fe_escape_path( "${title}." . $self->SUFFIX )
              . "\n" );
        $self->literal_data($content);
        if (%mediafile) {
            $self->send_to_git( 'M 644 inline '
                  . $self->fe_escape_path( $mediafile{title} )
                  . "\n" );
            $self->literal_data_raw( $mediafile{content} );
        }
        $self->send_to_git("\n\n");
    }
    else {
        $self->send_to_git( 'D '
              . $self->fe_escape_path( "${title}." . $self->SUFFIX )
              . "\n" );
    }

    # mediawiki revision number in the git note
    if ( $full_import && $n == 1 ) {
        $self->send_to_git(
            'reset refs/notes/' . $self->remote_name . "/mediawiki\n" );
    }
    $self->send_to_git(
        'commit refs/notes/' . $self->remote_name . "/mediawiki\n" );
    $self->send_to_git(
        $self->format_committer_name( $author, $self->wiki_name, $date ) );

    $self->literal_data('Note added by git-mediawiki during import');
    if ( !$full_import && $n == 1 ) {
        $self->send_to_git(
            'from refs/notes/' . $self->remote_name . "/mediawiki^0\n" );
    }
    $self->send_to_git("N inline :${n}\n");
    $self->literal_data("mediawiki_revision: $commit{mw_revision}");
    $self->send_to_git("\n\n");
    return;
}

# parse a sequence of
# <cmd> <arg1>
# <cmd> <arg2>
# \n
# (like batch sequence of import and sequence of push statements)
sub get_more_refs {
    my ( $self, $cmd ) = @_;
    my @refs;
    while (1) {
        my $line = $self->from_git->getline;
        if ( $line =~ /^$cmd (.*)$/smx ) {
            push @refs, $1;
        }
        elsif ( $line eq "\n" or $line eq q{} ) {
            return @refs;
        }
        else {
            die "Invalid command in a '$cmd' batch: $_\n";
        }
    }
    return;
}

sub cmd_import {
    my ( $self, $ref ) = @_;
    if ( $ref eq $EMPTY ) {
        die "Invalid argument for import\n";
    }

    # multiple import commands can follow each other.
    my @refs = ( $ref, $self->get_more_refs('import') );
    my $processed_refs;
    foreach my $ref (@refs) {
        next if $processed_refs->{$ref};

        # skip duplicates: "import refs/heads/master" being issued
        # twice; TODO: why?
        $processed_refs->{$ref} = 1;
        $self->import_ref($ref);
    }
    $self->send_to_git("done\n");
    return;
}

sub import_ref {
    my ( $self, $ref ) = @_;

    # The remote helper will call "import HEAD" and
    # "import refs/heads/master".
    # Since HEAD is a symbolic ref to master (by convention,
    # followed by the output of the command "list" that we gave),
    # we don't need to do anything in this case.
    if ( $ref eq 'HEAD' ) {
        return;
    }

    $self->to_user->print("Searching revisions...\n");
    my $last_local = $self->get_last_local_revision();
    my $fetch_from = $last_local + 1;
    if ( $fetch_from == 1 ) {
        $self->to_user->print("... fetching from beginning.\n");
    }
    else {
        $self->to_user->print("... fetching from here.\n");
    }

    my $n = 0;
    if ( $self->fetch_strategy eq 'by_rev' ) {
        $self->to_user->print("Fetching & writing export data by revs...\n");
        $n = $self->import_ref_by_revs($fetch_from);
    }
    elsif ( $self->fetch_strategy eq 'by_page' ) {
        $self->to_user->print("Fetching & writing export data by pages...\n");
        $n = $self->import_ref_by_pages($fetch_from);
    }
    else {
        my ( $strategy, $remote_name ) =
          ( $self->fetch_strategy, $self->remote_name );
        $self->to_user->print(
            'fatal: invalid fetch strategy ' . qq{$strategy".\n} );
        $self->to_user->print( 'Check your configuration variables '
              . "remote.${remote_name}.fetchStrategy and "
              . "mediawiki.fetchStrategy\n" );
        exit 1;
    }

    if ( $fetch_from == 1 && $n == 0 ) {
        $self->to_user->print(
            "You appear to have cloned an empty MediaWiki.\n");

        # Something has to be done remote-helper side. If nothing is done,
        # an error is thrown saying that HEAD is referring to unknown
        # object 0000000000000000000 and the clone fails.
    }
    return;
}

sub import_ref_by_pages {
    my $self       = shift;
    my $fetch_from = shift;
    my $pages      = $self->get_pages();

    my ( $n, @revisions ) = $self->fetch_revisions( $pages, $fetch_from );
    @revisions = sort { $a->{revid} <=> $b->{revid} } @revisions;
    my @revision_ids = map { $_->{revid} } @revisions;

    return $self->import_revids( $fetch_from, \@revision_ids, $pages );
}

sub error_non_fast_forward {
    my $self   = shift;
    my $advice = $self->repo->config_bool('advice.pushNonFastForward');

    if ($advice) {

        # Native git-push would show this after the summary.
        # We can't ask it to display it cleanly, so $self->send_to_git(it
        # ourselves before.
        $self->to_user->print(<<"EOF");
To prevent you from losing history, non-fast-forward updates were
rejected Merge the remote changes (e.g. 'git pull') before pushing
again. See the 'Note about fast-forwards' section of 'git push --help'
for details.
EOF
    }
    $self->send_to_git(qq(error $_[0] "non-fast-forward"\n));
    return 0;
}

# Dumb push: don't update notes and mediawiki ref to reflect the last push.
#
# Configurable with mediawiki.dumbPush, or per-remote with
# remote.<remote_name>.dumbPush.
#
# This means the user will have to re-import the just-pushed
# revisions. On the other hand, this means that the Git revisions
# corresponding to MediaWiki revisions are all imported from the wiki,
# regardless of whether they were initially created in Git or from the
# web interface, hence all users will get the same history (i.e. if
# the push from Git to MediaWiki loses some information, everybody
# will get the history with information lost). If the import is
# deterministic, this means everybody gets the same sha1 for each
# MediaWiki revision.

sub git_remote_mediawiki {
    my @arg = @_;

    if ( @arg != 2 ) {
        die <<"EOF";
ERROR: git-remote-mediawiki module was not called with a correct
number of parameters

You may obtain this error because you attempted to run the
git-remote-mediawiki module directly.

This module can be used the following way:

		git clone mediawiki://<address of a mediawiki>

Then, use git commit, push and pull as with every normal git
repository.
EOF
    }

    my $mw = Git::MediaWiki->new(@arg);

    # Commands parser
    while ( my $line = $mw->from_git->getline ) {
        chomp $line;

        if ( !$mw->parse_command($line) ) {
            last;
        }

        # flush STDOUT, to make sure the previous
        # command is fully processed.
        $mw->to_git->autoflush;
    }
    return;
}
1;    # Famous last words
