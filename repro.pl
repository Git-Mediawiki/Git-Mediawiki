#!/usr/bin/perl -w

use MediaWiki::API;
use Data::Dumper;
use URI::Escape;
use MediaWiki::Bot qw(:constants);

my $wiki = MediaWiki::API->new;
my $remote_url = 'http://localhost:1234/wiki';
#my $username = 'WikiAdmin@test';
#my $password = 'g7gvdba4b9qlcgjfiflnpvkq9r00ml9n';
my $username = 'WikiAdmin';
my $password = 'AdminPass';
my $wiki_domain = '';

$wiki->{config}->{api_url} = "${remote_url}/api.php";
$wiki->{ua}->add_handler("request_send",  sub { shift->dump; return });
$wiki->{ua}->add_handler("response_done", sub { shift->dump; return });

print "getting a CSRF token\n";
my $query = {action => 'login', lgname => $username};
my $ref = $wiki->api( $query );
my $token;
if ($ref) {
    $token = $ref->{query}->{tokens}->{logintoken};
    if (!$token) {
        $token = $ref->{login}->{token};
    }
    print Dumper($token);
    print Dumper($ref);
} else {
    print 'failed: (error ' . $wiki->{error}->{code} . ': ' .
                    $wiki->{error}->{details} . ")\n";
}

print "got token $token\n";
$query = {action => 'login',
          lgtoken => $token,
          lgname => $username,
          lgpassword => $password,
};
$ref = $wiki->api( $query );
print Dumper($ref);
if ($ref && $ref->{login}->{result} eq "Success") {
    print "login worked\n";
} else {
    print 'login failed: (error ' . $wiki->{error}->{code} . ': ' .
                    $wiki->{error}->{details} . ")\n";
}


my $bot = MediaWiki::Bot->new({
    assert      => 'bot',
    host        => 'localhost',
    operator    => 'WikiAdmin'});
$bot->{api}->{config}->{api_url} = 'http://localhost:1234/wiki/api.php';
$bot->{api}->{ua}->add_handler("request_send",  sub { shift->dump; return });
$bot->{api}->{ua}->add_handler("response_done", sub { shift->dump; return });
$bot->{api}->{ua}->default_header('Accept-Encoding', '');
$bot->login({ username => $username, password => $password }) or die "login failed";

my $text = $bot->get_text("Main_Page");
print "text: $text\n";
