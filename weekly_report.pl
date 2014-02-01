#!/bin/perl
use strict;
use WWW::Mechanize;
use Date::Calc qw(:all);
use Getopt::Long;

my $name = "";
my $username = "";
my $password =  "";
my $domain = "";
my $team = "";
my $dry_run = 0;
my $debug = 0;
my $commits_by_date = "~/bin/commits_by_date.sh";
my $author = "";
my $help;
my $force_week;

GetOptions(
	"--force-week=s" => \$force_week,
	"--help" => \$help,
);

if ($help) {
	printf "%s [--force-week=week]\n", $0;
	exit 1;
}

my @sessions = (
	'Summary',
	'Meetings/Trips',
	'Issues',
	'Development'
);

my @session_body = (
	"summary.twiki",
	"meetings.twiki",
	"issues.twiki",
	"development.twiki",
);

my %projects = (
	'Kernel media subsystem' => '/devel/v4l/patchwork',
	'Kernel media subsystem under work' => '/devel/v4l/temp',
	'Kernel EDAC subsystem' => '/devel/edac/edac',
	'v4l-utils' => '/devel/v4l/v4l-utils',
	'media build tree' => '/devel/v4l/patchwork',
	'xawtv version 3' => '/devel/v4l/xawtv3',
	'Rasdaemon' => '/devel/edac/rasdaemon',
	'perl Twiki status' => '/devel/perltwiki',
);

my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = localtime();

$year += 1900;
$month += 1;

my ($week, $y) = Week_of_Year($year, $month, $day);

$week = $force_week if ($force_week);

my @saturday = Add_Delta_Days(Monday_of_Week($week, $year), -1);
my @sunday = Add_Delta_Days(Monday_of_Week($week, $year), 5);

printf "From %04d-%02d-%02d to %04d-%02d-%02d\n", @saturday, @sunday if ($debug);

my $date1 = sprintf "%04d-%02d-%02d", @saturday;
my $date2 = sprintf "%04d-%02d-%02d", @sunday;

my $month1 = Month_to_Text($saturday[1]);

my $period;

if ($saturday[0] != $sunday[0]) {
	my $month2 = Month_to_Text($sunday[1]);
	$period = sprintf "$name - Week %02d: %s %02d %04d - %s %02d %04d\n", $week, $month1, $saturday[2], $saturday[0], $month2, $sunday[2], $sunday[0];
} elsif ($saturday[1] != $sunday[1]) {
	my $month2 = Month_to_Text($sunday[1]);
	$period = sprintf "$name - Week %02d: %s %02d - %s %02d\n", $week, $month1, $saturday[2], $month2, $sunday[2];
} else {
	$period = sprintf "$name - Week %02d: %s %02d-%02d\n", $week, $month1, $saturday[2], $sunday[2];
}

my $url = sprintf "%s/bin/edit/%s/%sWeek%02dStatus%d", $domain, $team, $username, $week, $year;

printf "URL = $url\n" if ($debug);
printf "period = $period\n" if ($debug);

my $mech = WWW::Mechanize->new();
$mech->credentials($username, $password);

my $res = $mech->get($url);
if (!$res->is_success) {
	print STDERR $res->status_line, "\n";
	exit;
}

my $form = $mech->form_number(0);
my $data = $form->param("text");

my $empty = 0;

$empty = 1 if (!($data =~ m/STARTSECTION/));

if ($empty) {
	my $data = sprintf "%TOC%\n\n---+ $period";

	for (my $i = 0; $i < scalar @sessions; $i++) {
		my $s = $sessions[$i];

		printf "session $i: %s\n", $session_body[$i] if ($debug);

		$data .= sprintf "\n---++ $s\n\n%%STARTSECTION{\"$s\"}%%\n";
		$data .= qx(cat $session_body[$i]);
		$data .= "===SUMMARYTABLE===" if (!$i);
		$data .= sprintf "%%ENDSECTION{\"$s\"}%%\n";
	}

	$data .= sprintf "\n\n-- Main.$username - %04d-%02d-%02d\n", $year, $month, $day;
} else {
	$data =~ s/(STARTSECTION\{\"Summary\"\}.*?)\-\-\-\+\+\+\s+.*?(\%ENDSECTION)/\1===SUMMARYTABLE===\2/s;

	if (!($data =~ m/===SUMMARYTABLE===/)) {
		$data =~ s/(\%ENDSECTION\{\"Summary\"\}.)/===SUMMARYTABLE===\1/s;
	}
}

my $summary_table = "";

foreach my $proj (keys %projects) {
	my $dir = $projects{$proj};

	my $per_author = qx(cd $dir && $commits_by_date --author --since $date1 --to $date2 --author chehab --silent);
	my $per_committer = qx(cd $dir && $commits_by_date --committer --since $date1 --to $date2 --author chehab --silent);

	$per_author =~ s/\s+$//;
	$per_committer =~ s/\s+$//;
	my $reviewed = $per_committer;

	$reviewed -= $per_author if ($reviewed >= $per_author);

	next if ($reviewed == 0 && $per_author == 0 && $per_committer == 0);

	printf "\tproject $proj, directory $dir: %d authored, %d committed, %d reviewed\n", $per_author, $per_committer, $reviewed if ($debug);

	$summary_table .= sprintf "---+++ $proj Patch Summary\n%%TABLE{headerrows=\"1\"}%%\n";
	$summary_table .= sprintf '| *Submitted* | *Committed* | *Reviewed* | *GBM Requested* | *Notes/Collection Mechanism* |';
	$summary_table .= "\n| " . $per_author . " | " . $per_committer.	" | " .	$reviewed;
	$summary_table .= " | 0 | [[MauroChehabPerlTwiki][Mauro Chehab report's own mechanism]] |\n\n";
}

$data =~ s/===SUMMARYTABLE===/$summary_table/;

print $data if ($debug);
exit if ($dry_run);

