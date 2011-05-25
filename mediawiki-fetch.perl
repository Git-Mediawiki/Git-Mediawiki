#!/usr/bin/perl

use strict;
use MediaWiki::API;
use Storable qw(freeze thaw);
use DateTime::Format::ISO8601;
use Encode qw(encode_utf8);

my $url = shift;

my $mediawiki = MediaWiki::API->new;
$mediawiki->{config}->{api_url} = "$url/api.php";

my $pages = $mediawiki->list({
		action => 'query',
		list => 'allpages',
		aplimit => 500,
	});

my %revisions;

print STDERR "Fetching revisions...\n";
my $n = 1;

foreach my $page (@$pages) {
	my $id = $page->{pageid};

	print STDERR "$n/", scalar(@$pages), ": $page->{title}\n";
	$n++;

	next if exists $revisions{$id};

	my $query = {
		action => 'query',
		prop => 'revisions',
		rvprop => 'content|timestamp|comment|user|ids',
		rvlimit => 10,
		pageids => $page->{pageid},
	};

	my $page_revisions;
	while (1) {
		my $result = $mediawiki->api($query);

		# Save the result, appending if necessary.
		if (defined $page_revisions) {
			push @{$page_revisions->{revisions}}, @{$result->{query}->{pages}->{$id}->{revisions}};
		} else {
			$page_revisions = $result->{query}->{pages}->{$id};
		}

		# And continue or quit, depending on the output.
		last unless $result->{'query-continue'};
		$query->{rvstartid} = $result->{'query-continue'}->{revisions}->{rvstartid};
	}

	print STDERR "  Fetched ", scalar(@{$page_revisions->{revisions}}), " revisions.\n";
	$revisions{$id} = freeze($page_revisions);

}

# Make a flat list of all page revisions, so we can
# interleave them in date order.
my @revisions = map {
	my $page = thaw($revisions{$_});
	my @revisions = @{$page->{revisions}};
	delete $page->{revisions};
	$_->{page} = $page foreach @revisions;
	@revisions } keys(%revisions);

# Creation of the fast-import stream
print STDERR "Writing export data...\n";
binmode STDOUT, ':binary';
$n = 0;
foreach my $rev (sort { $a->{timestamp} cmp $b->{timestamp} } @revisions) {
	$n++;
	my $user = $rev->{user} || 'Anonymous';
	my $dt = DateTime::Format::ISO8601->parse_datetime($rev->{timestamp});
	#TODO: Write empty message ?
	my $comment = defined $rev->{comment} ? $rev->{comment} : '';
	my $title = $rev->{page}->{title};
	my $content = $rev->{'*'};
	$title =~ y/ /_/;

	print STDERR "$n/", scalar(@revisions), ": $rev->{page}->{title}\n";

	print "commit refs/remotes/origin/master\n";
	print "mark :$n\n";
	print "committer $user <none\@example.com> ", $dt->epoch, " +0000\n";
	print "data ", bytes::length(encode_utf8($comment)), "\n", encode_utf8($comment);
	print "M 644 inline $title.wiki\n";
	print "data ", bytes::length(encode_utf8($content)), "\n", encode_utf8($content);
	print "\n\n";
}

print "reset refs/heads/master\n";
print "from :$n \n\n";

print "reset refs/remotes/origin/master\n";
print "from :$n";

