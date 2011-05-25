#! /usr/bin/perl
use strict;
use MediaWiki::API;

sub mw_capabilities {
	print STDOUT "fetch\n";
	print STDOUT "list\n";
	print STDOUT "option\n";
	print STDOUT "push\n";
	print STDOUT "\n";
}

sub mw_list {
	print STDOUT "? refs/heads/master\n";
	#print STDOUT '@'."refs/heads/master HEAD\n";
	print STDOUT "\n";

}

sub mw_option {
	print STDERR "not yet implemented \n";
	print STDOUT "\n";
}

sub mw_fetch {
	my $url = $_[0];
	my $mw = MediaWiki::API->new;
	$mw->{config}->{api_url} = "$url/api.php"

	my $pages = $mw->list ({
			action =>'query',
			list => 'allpages',
			aplimit => 500,
		});

}

sub mw_import {
	print STDERR "not yet implemented \n";
}
sub mw_push {
	print STDERR "not yet implemented \n";
}


1;
