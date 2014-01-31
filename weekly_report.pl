#!/bin/perl
use strict;
use WWW::Mechanize;
use Date::Calc qw(:all);

my $username = "";
my $password =  "";
my $domain = "";
my $team = "";
my $dry_run = 1;
my $debug = 1;
my $url;

my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = localtime();

$year += 1900;
$month += 1;

print "$year-$month-$day\n";

my $week;

($week, $year) = Week_of_Year($year, $month, $day);

$url = sprintf "%s/bin/edit/%s/%sWeek%02dStatus%d", $domain, $team, $username, $week, $year;

printf "URL = $url\n" if ($debug);

my $mech = WWW::Mechanize->new();
$mech->credentials($username, $password);

my $res = $mech->get($url);
if (!$res->is_success) {
	print STDERR $res->status_line, "\n";
	exit;
}

my $form = $mech->form_number(0);
print $form->dump if ($debug > 1);

printf "Form length = %d\n", length($form->dump);

if (length($form->dump) > 1258) {
	printf "Week report already submitted.\n");
	exit;
}



exit;

$mech->follow_link( n => 3 );
$mech->follow_link( text_regex => qr/download this/i );
$mech->follow_link( url => 'http://host.com/index.html' );

$mech->submit_form(
form_number => 3,
fields      => {
username    => 'mungo',
password    => 'lost-and-alone',
}
);
$mech->submit_form(
form_name => 'search',
fields    => { query  => 'pot of gold', },
button    => 'Search Now'
);
