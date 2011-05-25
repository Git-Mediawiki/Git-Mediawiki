#!/usr/bin/perl

use strict;
use MediaWiki::API;
use DB_File;
use Storable qw(freeze thaw);
use DateTime::Format::ISO8601;
use Encode qw(encode_utf8);

my $url = shift;

my $mw = MediaWiki::API->new;
$mw->{config}->{api_url} = "$url/api.php";

my $pages = $mw->list({
    action => 'query',
    list => 'allpages',
    aplimit => 2,
});

# Keep everything in a db so we are restartable.
my $revdb = tie my %revisions, 'DB_File', 'revisions.db';
print STDERR "Fetching revisions...\n";
my $n = 1;
foreach my $page (@$pages) {
  my $id = $page->{pageid};

  print STDERR "$n/", scalar(@$pages), ": $page->{title}\n";
  $n++;

  next if exists $revisions{$id};

  my $q = {
    action => 'query',
    prop => 'revisions',
    rvprop => 'content|timestamp|comment|user|ids',
    rvlimit => 10,
    pageids => $page->{pageid},
  };
  my $p;
  while (1) {
    my $r = $mw->api($q);

    # Write out all content to files.
    foreach my $rev (@{$r->{query}->{pages}->{$id}->{revisions}}) {
      my $fn = "$rev->{revid}.rev";
      open(my $fh, '>', $fn)
        or die "unable to open $fn: $!";
      binmode $fh, ':utf8';
      print $fh $rev->{'*'};
      close($fh);
      delete $rev->{'*'};
    }

    # And then save the rest, appending if necessary.
    if (defined $p) {
      push @{$p->{revisions}}, @{$r->{query}->{pages}->{$id}->{revisions}};
    }
    else {
      $p = $r->{query}->{pages}->{$id};
    }

    # And continue or quit, depending on the output.
    last unless $r->{'query-continue'};
    $q->{rvstartid} = $r->{'query-continue'}->{revisions}->{rvstartid};
  }

  print STDERR "  Fetched ", scalar(@{$p->{revisions}}), " revisions.\n";
  $revisions{$id} = freeze($p);
  $revdb->sync;
}

# Make a flat list of all page revisions, so we can
# interleave them in date order.
my @revisions = map {
  my $page = thaw($revisions{$_});
  my @revisions = @{$page->{revisions}};
  delete $page->{revisions};
  $_->{page} = $page foreach @revisions;
  @revisions
} keys(%revisions);

print STDERR "Writing export data...\n";
binmode STDOUT, ':binary';
$n = 1;
foreach my $rev (sort { $a->{timestamp} cmp $b->{timestamp} } @revisions) {
  my $user = $rev->{user} || 'Anonymous';
  my $dt = DateTime::Format::ISO8601->parse_datetime($rev->{timestamp});
  my $fn = "$rev->{revid}.rev";
  my $size = -s $fn;
  my $comment = defined $rev->{comment} ? $rev->{comment} : '';
  my $title = $rev->{page}->{title};
  $title =~ y/ /_/;

  print STDERR "$n/", scalar(@revisions), ": $rev->{page}->{title}\n";

  print "commit refs/remotes/origin/master\n";
  print "mark :$n\n";
  print "committer $user <none\@example.com> ", $dt->epoch, " +0000\n";
  print "data ", bytes::length(encode_utf8($comment)), "\n", encode_utf8($comment);
  print "M 644 inline $title.wiki\n";
  print "data $size\n";
  open(my $fh, '<', $fn)
    or die "unable to open $fn: $!";
  binmode $fh, ':binary';
  while (read($fh, my $buf, 4096)) {
    print $buf;
  }
  $n++;
  print "\n\n";
}

$n--;
print "reset refs/heads/master\n";
print "from :$n \n\n";

print "reset refs/remotes/origin/master\n";
print "from :$n";

