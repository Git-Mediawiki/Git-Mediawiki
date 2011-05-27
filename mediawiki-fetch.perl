#!/usr/bin/perl

use strict;
use MediaWiki::API;
use Storable qw(freeze thaw);
use DateTime::Format::ISO8601;
use Encode qw(encode_utf8);
use Data::Dumper;

my $url = shift;

my $mediawiki = MediaWiki::API->new;
$mediawiki->{config}->{api_url} = "$url/api.php";

my $pages = $mediawiki->list({
		action => 'query',
		list => 'allpages',
		aplimit => 500,
	});

my @revisions;

print STDERR "Fetching revisions...\n";
my $n = 1;

foreach my $page (@$pages) {
	my $id = $page->{pageid};

	print STDERR "$n/", scalar(@$pages), ": $page->{title}\n";
	$n++;

	my $query = {
		action => 'query',
		prop => 'revisions',
		rvprop => 'ids',
		rvlimit => 500,
		pageids => $page->{pageid},
	};

	my $revnum = 1;
	# Get 500 revisions at a time
	while (1) {
		my $result = $mediawiki->api($query);
	
		# Parse each of those 500 revisions
		foreach my $revision (@{$result->{query}->{pages}->{$id}->{revisions}}) {
			my $page_rev_ids;
			$page_rev_ids->{pageid} = $page->{pageid};
			$page_rev_ids->{revid} = $revision->{revid};
			push (@revisions, $page_rev_ids);
			$revnum++;
		}

		last unless $result->{'query-continue'};
		$query->{rvstartid} = $result->{'query-continue'}->{revisions}->{rvstartid};
		print "\n";
	}

	print STDERR "  Fetched ", $revnum, " revisions.\n";

}


# Creation of the fast-import stream
print STDERR "Writing export data...\n";
binmode STDOUT, ':binary';
$n = 0;

foreach my $pagerevids (sort {$a->{revid} >= $b->{revid}} @revisions) {

	my $query = {
		action => 'query',
		prop => 'revisions',
		rvprop => 'content|timestamp|comment|user|ids',
		revids => $pagerevids->{revid},
	};

	my $result = $mediawiki->api($query);

	my $rev = pop(@{$result->{query}->{pages}->{$pagerevids->{pageid}}->{revisions}});
	
	$n++;
	my $user = $rev->{user} || 'Anonymous';
	my $dt = DateTime::Format::ISO8601->parse_datetime($rev->{timestamp});
	
	my $comment = defined $rev->{comment} ? $rev->{comment} : '*Empty MediaWiki Message*';
	my $title = $result->{query}->{pages}->{$pagerevids->{pageid}}->{title};
	my $content = $rev->{'*'};
	$title =~ y/ /_/;

	print STDERR "$n/", scalar(@revisions), ": $title\n";

	print "commit refs/heads/master\n";
	print "mark :$n\n";
	print "committer $user <none\@example.com> ", $dt->epoch, " +0000\n";
	print "data ", bytes::length(encode_utf8($comment)), "\n", encode_utf8($comment);
	print "M 644 inline $title.wiki\n";
	print "data ", bytes::length(encode_utf8($content)), "\n", encode_utf8($content);
	print "\n\n";
}

print "reset refs/heads/master\n";
print "from :$n";

