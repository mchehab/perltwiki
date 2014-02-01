#!/bin/perl
use strict;
use WWW::Mechanize;
use Date::Calc qw(:all);
use Getopt::Long;
use Cwd;
use HTML::Entities;

my $name = "";
my $username = "";
my $password =  "";
my $domain = "";
my $team = "";
my $dry_run = 0;
my $debug = 0;
my $author = "";
my $help;
my $force_week;

GetOptions(
	"--week=s" => \$force_week,
	"--help" => \$help,
);

if ($help) {
	printf "%s [--week=week]\n", $0;
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
#	'Kernel media subsystem under work' => '/devel/v4l/temp',
	'Kernel EDAC subsystem' => '/devel/edac/edac',
	'v4l-utils' => '/devel/v4l/v4l-utils',
	'media build tree' => '/devel/v4l/media_build',
	'xawtv version 3' => '/devel/v4l/xawtv3',
	'Rasdaemon' => '/devel/edac/rasdaemon',
	'perl Twiki status' => '/devel/perltwiki',
);

sub get_patch_table($$$)
{
	my @saturday = @{$_[0]};
	my @sunday = @{$_[1]};
	my $summary = $_[2];

	my $table = "";

	# This is to avoid digging too deeper at the tree
	my $date1 = sprintf "%04d-%02d-%02d", 2013, 1, 1;

	foreach my $proj (keys %projects) {
		my $dir = $projects{$proj};
		my $per_author = 0;
		my $per_committer = 0;

		my $since = (Date_to_Days(@saturday) - Date_to_Days(1970, 01, 01)) * 60 * 60 * 24;
		my $to = (Date_to_Days(@sunday) - Date_to_Days(1970, 01, 01) + 1) * 60 * 60 * 24 - 1;

		if ($summary) {
			open IN, "cd $dir && git log --date=raw --format='%h|%ad|%an|%cd|%cn' --date-order --since '$date1' |grep '$name'|";
			while (<IN>) {
				if (m/([^\|]+)\|([^\|\s]+)\s+[^\|]+\|([^\|]+)\|([^\|]+)\s+[^\|]+\|([^\|]+?)\s*$/) {
					my $cs = $1;
					my $ad = $2;
					my $an = $3;
					my $cd = $4;
					my $cn = $5;

					$per_author++ if ($ad >= $since && $ad <= $to && $an =~ m/($name)/);
					$per_committer++ if ($cd >= $since && $cd <= $to && $cn =~ m/($name)/);
				}
			}

			my $reviewed = $per_committer;

			$reviewed -= $per_author if ($reviewed >= $per_author);

			next if ($reviewed == 0 && $per_author == 0 && $per_committer == 0);

			printf "\tproject $proj, directory $dir: %d authored, %d committed, %d reviewed\n", $per_author, $per_committer, $reviewed if ($debug);

			$table .= sprintf "---+++ $proj Patch Summary\n%%TABLE{headerrows=\"1\"}%%\n";
			$table .= sprintf '| *Submitted* | *Committed* | *Reviewed* | *GBM Requested* | *Notes/Collection Mechanism* |';
			$table .= "\n| " . $per_author . " | " . $per_committer.	" | " .	$reviewed;
			$table .= " | 0 | [[MauroChehabPerlTwiki][Mauro Chehab report's own mechanism]] |\n\n";

			close IN;
		} else {
			my $patch = "";
			open IN, "cd $dir && git log --date=raw --format='%h|%ad|%an|%cd|%cn|%s' --date-order --since '$date1' |grep '$name'|";
			while (<IN>) {
				if (m/([^\|]+)\|([^\|\s]+)\s+[^\|]+\|([^\|]+)\|([^\|]+)\s+[^\|]+\|([^\|]+)\|([^\|]+?)\s*$/) {
					my $cs = $1;
					my $ad = $2;
					my $an = $3;
					my $cd = $4;
					my $cn = $5;
					my $s = $6;

					next if (($ad < $since || $ad > $to) && ($cd < $since || $cd > $to));

					$ad = sprintf "%04d-%02d-%02d", Add_Delta_Days(1970, 01, 01, ($ad / (60 * 60 * 24)));
					$cd = sprintf "%04d-%02d-%02d", Add_Delta_Days(1970, 01, 01, ($cd / (60 * 60 * 24)));

					$patch .= sprintf "| $cs | %s | %s | %s | %s | %s |\n", $ad, encode_entities($an), $cd, encode_entities($cn), $s;
				}
			}
			close IN;
			if ($patch ne "") {
				$table .= sprintf "---+++ $proj Patch Summary\n%%TABLE{headerrows=\"1\"}%%\n";
				$table .= sprintf '| *Changeset* | *Date* | *Author* | *Commit Date* | *Comitter* | *Subject* |';
				$table .= "\n$patch\n";
			}
		}
	}
	return $table;
}

sub replace_table($$$$$$)
{
	my $table_tag = shift;
	my $data = shift;
	my $session = shift;
	my $date1 = shift;
	my $date2 = shift;
	my $summary = shift;

	# If the session has tables remove
	$data =~ s/(STARTSECTION\{\")($session)(\"\}.*?)\-\-\-\+\+\+\s+.*?(\%ENDSECTION)/\1\2\3$table_tag\4/s;

	# If the session doesn't have a session tag, add it
	if (!($data =~ m/$table_tag/)) {
		$data =~ s/(\%ENDSECTION\{\")($session)(\"\}.)/$table_tag\1\2\3/s;
	}

	my $summary_table = get_patch_table($date1, $date2, $summary);

	$data =~ s/($table_tag)/$summary_table/;

	return $data;
}

my ($sec,$min,$hour,$day,$month,$year,$wday,$yday,$isdst) = localtime();

$year += 1900;
$month += 1;

my ($week, $y) = Week_of_Year($year, $month, $day);

$week = $force_week if ($force_week);

my @saturday = Add_Delta_Days(Monday_of_Week($week, $year), -1);
my @sunday = Add_Delta_Days(Monday_of_Week($week, $year), 5);

printf "From %04d-%02d-%02d to %04d-%02d-%02d\n", @saturday, @sunday if ($debug);

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

my $sum_table_tag = '===SUMMARYTABLE===';
my $patch_table_tag = '===PATCHTABLE===';

if ($empty) {
	$data = sprintf "%TOC%\n\n---+ $period";

	for (my $i = 0; $i < scalar @sessions; $i++) {
		my $s = $sessions[$i];
		printf "session $s ($i): %s\n", $session_body[$i] if ($debug);

		$data .= sprintf "\n---++ $s\n\n%%STARTSECTION{\"$s\"}%%\n";
		$data .= qx(cat $session_body[$i]);
		$data .= $sum_table_tag if ($s eq 'Summary');
		$data .= $patch_table_tag if ($s eq 'Development');
		$data .= sprintf "%%ENDSECTION{\"$s\"}%%\n";
	}
	$data .= sprintf "\n\n-- Main.$username - %04d-%02d-%02d\n", $year, $month, $day;
}

$data = replace_table($sum_table_tag, $data, 'Summary', \@saturday, \@sunday, 1);
$data = replace_table($patch_table_tag, $data, 'Development', \@saturday, \@sunday, 0);

print $data if ($debug);
exit if ($dry_run);

$form->param("text", $data);
$mech->submit();
