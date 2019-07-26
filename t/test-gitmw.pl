#!/usr/bin/perl -w -s
# Copyright (C) 2012
#     Charles Roussel <charles.roussel@ensimag.imag.fr>
#     Simon Cathebras <simon.cathebras@ensimag.imag.fr>
#     Julien Khayat <julien.khayat@ensimag.imag.fr>
#     Guillaume Sasdy <guillaume.sasdy@ensimag.imag.fr>
#     Simon Perrat <simon.perrat@ensimag.imag.fr>
# License: GPL v2 or later

# Usage:
#       ./test-gitmw.pl <command> [argument]*
# Execute in terminal using the name of the function to call as first
# parameter, and the function's arguments as following parameters
#
# Example:
#     ./test-gitmw.pl "get_page" foo .
# will call <wiki_getpage> with arguments <foo> and <.>
#
# Available functions are:
#     "get_page"
#     "delete_page"
#     "edit_page"
#     "getallpagename"

package MABSTestHarness;

use MediaWiki::API;
use Getopt::Long;
use DateTime::Format::ISO8601;
use IO::File;

use open ':encoding(utf8)';
use strict;
use warnings;

use base qw(MediaWiki::API);
use version; our $VERSION = qv(0.02);

sub report_error {
    my ( $self, $msg ) = @_;
    my $err = q[];
    if ( defined $msg ) {
        $err = "$msg: ";
    }
    die $err . $self->{error}->{code} . q{:} . $self->{error}->{details} . "\n";
}

# wiki_login <name> <password>
#
# Logs the user with <name> and <password>
sub wiki_login {
    my ( $self, $user, $pass ) = @_;

    return $self->login( { lgname => "$user", lgpassword => "$pass" } )
      || report_error( $self, 'login failed' );
}

# wiki_getpage <wiki_page> <dest_path>
#
# fetch a page <wiki_page> and copies its content into directory dest_path
sub wiki_getpage {
    my ( $self, $pagename, $destdir ) = @_;

    my $page = $self->get_page( { title => $pagename } );
    if ( !defined $page ) {
        $self->report_error("wiki does not exist\n");
    }

    my $content = $page->{q(*)};
    if ( !defined $content ) {
        $self->("pages do not exist\n");
    }

    $pagename = $page->{'title'};

    # Replace spaces by underscore in the page name
    $pagename =~ s/ /_/smg;
    $pagename =~ s/\//%2F/smxg;
    my $file = IO::File->new( "$destdir/$pagename.mw", q{>} );
    $file->print($content);
    $file->close();
    return $content;
}

# wiki_delete_page <page_name>
#
# delete the page with name <page_name> from the wiki
sub wiki_delete_page {
    my ( $self, $pagename ) = @_;

    my $exist = $self->get_page( { title => $pagename } );

    if ( !defined( $exist->{q(*)} ) ) {
        die "no page with such name found: $pagename\n";
    }
    return $self->edit(
        {
            action => 'delete',
            title  => $pagename
        }
    ) || $self->report_error;
}

# wiki_editpage <wiki_page> <wiki_content> <wiki_append> [-c=<category>] [-s=<summary>]
#
# Edit a page named <wiki_page> with content <wiki_content>
# If <wiki_append> == true : append <wiki_content> at the end of the actual
# content of the page <wiki_page>
# If <wik_page> doesn't exist, that page is created with the <wiki_content>
sub wiki_editpage {
    my ( $self, $wiki_page, $wiki_content, $wiki_append ) = @_;
    my $summary = q();
    my ( $summ, $cat ) = ();
    GetOptions( 's=s' => \$summ, 'c=s' => \$cat );

    my $append = 0;
    if ( defined($wiki_append) && $wiki_append eq 'true' ) {
        $append = 1;
    }

    my $previous_text = q();

    if ($append) {
        my $ref = $self->get_page( { title => $wiki_page } );
        $previous_text = $ref->{q(*)};
    }

    my $text = $wiki_content;
    if ( defined $previous_text ) {
        $text = "$previous_text$text";
    }

    # Eventually, add this page to a category.
    if ( defined $cat ) {
        my $category_name = "[[Category:$cat]]";
        $text = "$text\n $category_name";
    }
    if ( defined $summ ) {
        $summary = $summ;
    }

    return $self->edit(
        {
            action  => 'edit',
            title   => $wiki_page,
            summary => $summary,
            text    => "$text"
        }
    );
}

# wiki_getallpagename [<category>]
#
# Fetch all pages of the wiki and print the names of each one in the
# file all.txt with a new line ("\n") between these.  If the argument
# <category> is defined, then this function get only the pages
# belonging to <category>.
sub wiki_getallpagename {
    my ( $self, $category ) = @_;

    my $mw_pages;

    # fetch the pages of the wiki
    if ( defined $category ) {
        $mw_pages = $self->list(
            {
                action      => 'query',
                list        => 'categorymembers',
                cmtitle     => "Category:$category",
                cmnamespace => 0,
                cmlimit     => 500
            }
        ) || $self->report_error;
        my $file = IO::File->new( 'all.txt', q{>} );
        foreach my $page ( @{$mw_pages} ) {
            $file->print("$page->{title}\n");
        }
        $file->close();

    }
    else {
        $mw_pages = $self->list(
            {
                action  => 'query',
                list    => 'allpages',
                aplimit => 500,
            }
        ) || $self->report_error;
        my $file = IO::File->new( 'all.txt', q{>} );
        foreach my $page ( @{$mw_pages} ) {
            $file->print("$page->{title}\n");
        }
        $file->close();
    }
    return $mw_pages;
}

sub wiki_upload_file {
    my ( $self, $file_name ) = @_;
    my $result = $self->edit(
        {
            action         => 'upload',
            filename       => $file_name,
            comment        => 'upload a file',
            file           => [$file_name],
            ignorewarnings => 1,
        },
        {
            skip_encoding => 1
        }
    ) || $self->report_error;
    return $result;
}

sub new() {
    my $wiki_address = "http://$ENV{'SERVER_ADDR'}:$ENV{'PORT'}";
    my $wiki_url     = "$wiki_address$ENV{'WIKI_DIR_NAME'}/api.php";
    my $self         = MediaWiki::API->new( { api_url => $wiki_url } );
    bless $self, 'MABSTestHarness';

    return $self;
}

sub main {
    my $call = shift @_;
	my @arg = @_;
    my $self = MABSTestHarness->new();

    # Main part of this script: parse the command line arguments
    # and select which function to execute

    # These should be exported in test-gitmw.pl
    my $wiki_admin      = "$ENV{'WIKI_ADMIN'}";
    my $wiki_admin_pass = "$ENV{'WIKI_PASSW'}";

    $self->wiki_login( $wiki_admin, $wiki_admin_pass );

    my %function = (
        upload_file    => 'wiki_upload_file',
        get_page       => 'wiki_getpage',
        delete_page    => 'wiki_delete_page',
        edit_page      => 'wiki_editpage',
        getallpagename => 'wiki_getallpagename',
    );
    if ( !$call or !exists $function{$call} ) {
        die "$call ERROR: wrong argument\n";
    }
	my $f = $function{$call};
    $self->$f(@arg);
    exit 0;

}

main(@ARGV);
