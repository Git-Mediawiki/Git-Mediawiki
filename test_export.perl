#!/usr/bin/perl

use strict;
use MediaWiki::API;


my $url = 'http://192.168.1.32/mediawiki';
my $page_name = "Test";

my $mw = MediaWiki::API->new();
$mw->{config}->{api_url} = "$url/api.php";

# log in to the wiki
$mw->login( { lgname => 'ilapa', lgpassword => 'kiplaki' } ) || die $mw->{error}->{code} . ': ' . $mw->{error}->{details};

# get a list of articles in category
my $page = $mw->get_page ( {
	title => $page_name,
} 
) || die $mw->{error}->{code} . ': ' . $mw->{error}->{details};


#edit de la page

#ouverture du fichier modfié en lecture et concaténation dans une chaine

open(FH, "test.wiki")
    or die "unable to open test.wiki : $!";
binmode FH, ':utf8';

my $text ='';
my $line;
while (<FH>){
    $text.=$_;
}

$mw->edit( {
        action => 'edit',
        summary => "because we can.",
        title => $page_name,
        text => $text,
    } ) ;
        
close (FH);

# get user info
#my $userinfo = $mw->api( {
#	action => 'query',
#	meta => 'userinfo',
#	uiprop => 'blockinfo|hasmsg|groups|rights|options|editcount|ratelimits' 
#} );

