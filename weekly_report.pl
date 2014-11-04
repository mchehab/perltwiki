#!/bin/perl
use strict;
use WWW::Mechanize;
use Date::Calc qw(:all);
use Getopt::Long;
use HTML::Entities;
use Pod::Usage;
use Config::IniFiles;
use POSIX;
use utf8;
use Data::Dumper;

#
# Don't need to touch on anything below that to customize the script.
# All customization can be done via a config file
#

#
# User's option handling
#

my $name = "";
my $username = "";
my $password =  "";
my $domain = "";
my $team = "";
my $advanced_auth = 1;
my $dry_run = 0;
my $debug = 0;
my $force_week;
my $force_year;
my $help;
my $man;
my $config_file;
my @project_name;
my %projects;
my %show_prj_empty;
my %prj_subtree;
my %gbm_branch;
my @sessions;
my @session_body;
my $sum_session;
my $patch_session;
my $summary_footer;
my $patch_footer;
my $gbm_patches;
my %gbm_hash;

#
# This is to avoid digging too deeper at the tree looking for
# potential patches to the report.
#
my $start_date = sprintf "%04d-%02d-%02d", 2013, 1, 1;

GetOptions(
	"cfg|config=s" => \$config_file,
	"week=s" => \$force_week,
	"year=s" => \$force_year,
	"start-date=s" => \$start_date,
	"dry-run" => \$dry_run,
	"debug" => \$debug,
	'help|?' => \$help,
	man => \$man
) or pod2usage(2);

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

if ($config_file) {
	my $cfg = Config::IniFiles->new(-file => $config_file);

	my $val = $cfg->val('global', 'name');
	$name = $val if ($val);

	$val = $cfg->val('global', 'username');
	$username = $val if ($val);

	$val = $cfg->val('global', 'password');
	$password = $val if ($val);

	$val = $cfg->val('global', 'domain');
	$domain = $val if ($val);

	$val = $cfg->val('global', 'team');
	$team = $val if ($val);

	$val = $cfg->val('global', 'summary_footer');
	$summary_footer = $val if ($val);

	$val = $cfg->val('global', 'patch_footer');
	$patch_footer = $val if ($val);

	$val = $cfg->val('global', 'gbm_patches');
	$gbm_patches = $val if ($val);

	$val = $cfg->val('global', 'start-date');
	$start_date = $val if ($val);

	foreach my $prj ($cfg->GroupMembers('project')) {
		my $path = $cfg->val($prj, 'path');
		my $show_empty = $cfg->val($prj, 'show_empty');
		my $subtree = $cfg->val($prj, 'subtree');
		my $gbm = $cfg->val($prj, 'gbm_branch');
		$prj =~ s/^\S+\s+//;
		print "config: project $prj, path $path\n" if ($debug);
		$projects{$prj} = $path;
		push @project_name, $prj;
		$show_prj_empty{$prj} = $show_empty if ($show_empty);
		$prj_subtree{$prj} = $subtree if ($subtree);
		$gbm_branch{$prj} = $gbm if ($gbm);
	}

	foreach my $session ($cfg->GroupMembers('session')) {
		my $has_summary = $cfg->val($session, 'summary');
		my $has_patch = $cfg->val($session, 'patches');
		my $template = $cfg->val($session, 'template');
		$session =~ s/^\S+\s+//;
		printf "config: session $session, template $template%s%s\n",
			$has_summary ? ", has patch summary" : "",
			$has_patch ? ", has patch table" : "" if ($debug);
		push @sessions, $session;
		push @session_body, $template;

		$sum_session = $session if $has_summary;
		$patch_session = $session if $has_patch;
	}
}

if ($config_file eq "" || $name eq "" || $username eq "" || $password eq  "" || $domain eq "" || $team eq "") {
	printf STDERR "ERROR: mandatory parameters not specified\n\n";
	pod2usage(1);
}

if (!(scalar @sessions)) {
	printf STDERR "ERROR: at least one session should be defined at the config file\n\n";
	pod2usage(1);
}

#
# Convert from epoch to year-mo-dy
#
sub epoch_to_text($)
{
	my $epoch = shift;

	my @date = Add_Delta_Days(1970, 01, 01, floor($epoch / (60 * 60 * 24)));

	return sprintf "%04d-%02d-%02d", @date;
}

#
# Get GBM patch list
#
sub get_gbm_patches()
{
	open IN, $gbm_patches or return;
	while (<IN>) {
		if (m/^([0-9a-f]+)/) {
			$gbm_hash{$1} = 1;
		}
	}
	close IN;
}

#
# Get GIT patch statistics and patch table
#

sub get_patch_summary($$$$$$)
{
	my $proj = shift;
	my $dir = shift;
	my $since = shift;
	my $to = shift;
	my $subtree = shift;
	my $gbm_branch = shift;

	my $subtree = $prj_subtree{$proj} if ($prj_subtree{$proj});
	my $per_author = 0;
	my $per_committer = 0;
	my $reviewed = 0;
	my $gbm = 0;

	open IN, "cd $dir && git log --date=raw --format='%h|%ad|%an|%cd|%cn' --date-order --since '$start_date' $gbm_branch $subtree |grep '$name'|";
	while (<IN>) {
		if (m/([^\|]+)\|([^\|\s]+)\s+[^\|]+\|([^\|]+)\|([^\|]+)\s+[^\|]+\|([^\|]+?)\s*$/) {
			my $cs = $1;
			my $ad = $2;
			my $an = $3;
			my $cd = $4;
			my $cn = $5;
			my $check_review;

			if ($ad >= $since && $ad <= $to && $an =~ m/($name)/) {
				$per_author++;
				if ($gbm_branch || $gbm_hash{$cs}) {
					$gbm++;
				}
			}
			if ($cd >= $since && $cd <= $to && $cn =~ m/($name)/) {
				$per_committer++;
				$reviewed++ if (!($an =~ m/($name)/));
			}
		}
	}

	next if ($reviewed == 0 && $per_author == 0 && $per_committer == 0 && !$show_prj_empty{$proj});

	printf "\tproject $proj, directory $dir: %d authored, %d committed, %d reviewed, %d gbm\n", $per_author, $per_committer, $reviewed, $gbm if ($debug);

	close IN;

	return "| $proj | " . $per_author . " | " . $per_committer.	" | " .	$reviewed . " | $gbm |\n";
}

sub get_patches($$$$$$)
{
	my $proj = shift;
	my $dir = shift;
	my $since = shift;
	my $to = shift;
	my $subtree = shift;
	my $gbm_branch = shift;

	my $table = "";
	my $patch = "";

	open IN, "cd $dir && git log --date=raw --format='%h|%ad|%an|%cd|%cn|%s' --date-order --since '$start_date' $gbm_branch $subtree |grep '$name'|";
	while (<IN>) {
		if (m/([^\|]+)\|([^\|\s]+)\s+[^\|]+\|([^\|]+)\|([^\|]+)\s+[^\|]+\|([^\|]+)\|([^\|]+?)\s*$/) {
			my $cs = $1;
			my $ad = $2;
			my $an = $3;
			my $cd = $4;
			my $cn = $5;
			my $s = $6;

			next if (!($ad >= $since && $ad <= $to && $an =~ m/($name)/) && !($cd >= $since && $cd <= $to && $cn =~ m/($name)/));


			my $ad_txt = epoch_to_text($ad);
			my $cd_txt = epoch_to_text($cd);

			if ($ad >= $since && $ad <= $to && $an =~ m/($name)/) {
				if ($gbm_branch || $gbm_hash{$cs}) {
					$ad_txt = "<span style=\"background-color: orange;\">$ad_txt</span>";
				} else {
					$ad_txt = "<span style=\"background-color: lightgreen;\">$ad_txt</span>";
				}
			}

			if ($cd >= $since && $cd <= $to && $cn =~ m/($name)/) {
				if ($gbm_branch || $gbm_hash{$cs}) {
					$cd_txt = "<span style=\"background-color: orange;\">$cd_txt</span>";
				} else {
					$cd_txt = "<span style=\"background-color: lightgreen;\">$cd_txt</span>";
				}
			}

			$patch .= sprintf "| $cs | %s | %s | %s | %s | %s |\n", $ad_txt, encode_entities($an), $cd_txt, encode_entities($cn), $s;
		}
	}
	close IN;
	if ($patch ne "") {
		$table .= sprintf "---+++++ $proj Patch Table\n%%TABLE{headerrows=\"1\"}%%\n";
		$table .= sprintf '| *Changeset* | *Date* | *Author* | *Commit Date* | *Comitter* | *Subject* |';
		$table .= "\n$patch\n";
	}

	return $table;
}

sub get_patch_table($$$)
{
	my @saturday = @{$_[0]};
	my @sunday = @{$_[1]};
	my $summary = $_[2];

	my $table = "";

	foreach my $proj (@project_name) {
		my $dir = $projects{$proj};
		my $per_author = 0;
		my $per_committer = 0;
		my $reviewed = 0;
		my $gbm = 0;

		my $since = (Date_to_Days(@saturday) - Date_to_Days(1970, 01, 01)) * 60 * 60 * 24;
		my $to = (Date_to_Days(@sunday) - Date_to_Days(1970, 01, 01) + 1) * 60 * 60 * 24 - 1;

		my $subtree = $prj_subtree{$proj} if ($prj_subtree{$proj});
		my $gbm_brch = $gbm_branch{$proj} if ($gbm_branch{$proj});

		if ($summary) {
			$table .= get_patch_summary($proj, $dir, $since, $to, $subtree, $gbm_brch);
		} else {
			$table .= get_patches($proj, $dir, $since, $to, $subtree, $gbm_brch);
		}
	}
	return $table;
}

#
# Replace an already existing patch table/patch summary
#

sub replace_table($$$$$$)
{
	my $table_tag = shift;
	my $data = shift;
	my $session = shift;
	my $date1 = shift;
	my $date2 = shift;
	my $summary = shift;

	print "replace table $session\n" if ($debug);

	# If the session has tables remove
	$data =~ s/(STARTSECTION\{\")($session)(\"\}.*?)\-\-\-\+\+*\s+.*?(\%ENDSECTION\{\")($session)/\1\2\3$table_tag\4\5/s;

	# If the session doesn't have a session tag, add it
	if (!($data =~ m/$table_tag/)) {
		$data =~ s/(\%ENDSECTION\{\")($session)(\"\}.)/$table_tag\1\2\3/s;
	}

	my $table = get_patch_table($date1, $date2, $summary);

	if ($summary) {
		if ($table ne "") {
			my $sumtable = sprintf "---+++++ Patch Summary\n%%TABLE{headerrows=\"1\"}%%\n";
			$sumtable .= sprintf '| *Project* | *Submitted and merged* | *Committed by me* | *Reviewed by me* | *GBM Requested* |';
			$sumtable .= "\n$table\n";
			$sumtable .= qx(cat $summary_footer);
			$table = $sumtable;
		}
	} elsif ($table ne "") {
		$table .= qx(cat $patch_footer);
	}

	$data =~ s/($table_tag)/$table/;

	return $data;
}

######
# MAIN
######

#
# Handle dates. The week stats on Monday, in Perl.
# Please notice that the code below considers a week starting on Sunday
#

my $period;

#
# As, for the reports, the weeks start on Sunday, be sure that the script
# will get the right week. So, add one day to fix it.
#

my ($week, $year) = Week_of_Year(Add_Delta_Days(Today(), 1));

$week = $force_week if ($force_week);
$year = $force_year if ($force_year);

my @saturday = Add_Delta_Days(Monday_of_Week($week, $year), -1);
my @sunday = Add_Delta_Days(Monday_of_Week($week, $year), 5);

printf "From %04d-%02d-%02d to %04d-%02d-%02d\n", @saturday, @sunday if ($debug);

my $month1 = Month_to_Text($saturday[1]);

# Create a week's description

if ($saturday[0] != $sunday[0]) {
	my $month2 = Month_to_Text($sunday[1]);
	$period = sprintf "$name - Week %02d: %s %02d %04d - %s %02d %04d\n", $week, $month1, $saturday[2], $saturday[0], $month2, $sunday[2], $sunday[0];
} elsif ($saturday[1] != $sunday[1]) {
	my $month2 = Month_to_Text($sunday[1]);
	$period = sprintf "$name - Week %02d: %s %02d - %s %02d\n", $week, $month1, $saturday[2], $month2, $sunday[2];
} else {
	$period = sprintf "$name - Week %02d: %s %02d-%02d\n", $week, $month1, $saturday[2], $sunday[2];
}

#
# Do authentication
#

my $mech = WWW::Mechanize->new();

if (!$advanced_auth) {
	$mech->credentials($username, $password);
} else {
	my $url = sprintf "%s/bin/login/OpenSourceGroup/WebHome?origurl=/", $domain, $team, $username, $week, $year;
	printf "Authenticating with $url\n" if ($debug);

	my $res = $mech->get($url);
	if (!$res->is_success) {
		print STDERR $res->status_line, "\n";
		exit;
	}
	print Dumper($mech) if ($debug > 1);

	my $form = $mech->form_number(0);

	$form->param("username", $username);
	$form->param("password", $password);


	$mech->submit();
}

#
# Read the Twiki's page
#

my $url = sprintf "%s/bin/edit/%s/%sWeek%02dStatus%d?nowysiwyg=1", $domain, $team, $username, $week, $year;
printf "period = $period" if ($debug);

print "Reading $url\n" if (!$debug);
my $res = $mech->get($url);
if (!$res->is_success) {
	print STDERR $res->status_line, "\n";
	exit;
}

my $form = $mech->form_number(0);
my $data = $form->param("text");

#
# Detect if the week was not filled yet. In that case, fills it from the
# templates
#

my $empty = 0;
$empty = 1 if (!($data =~ m/STARTSECTION/));

my $sum_table_tag = '===SUMMARYTABLE===';
my $patch_table_tag = '===PATCHTABLE===';

get_gbm_patches();

if ($empty) {
	$data = sprintf "%TOC%\n\n---+ $period";

	for (my $i = 0; $i < scalar @sessions; $i++) {
		my $s = $sessions[$i];
		printf "session $s ($i): %s\n", $session_body[$i] if ($debug);

		$data .= sprintf "\n---++ $s\n\n%%STARTSECTION{\"$s\"}%%\n";
		$data .= qx(cat $session_body[$i]);
		$data .= $sum_table_tag if ($s eq $sum_session);
		$data .= $patch_table_tag if ($s eq $patch_session);
		$data .= sprintf "%%ENDSECTION{\"$s\"}%%\n";
	}
	$data .= sprintf "\n\n-- Main.$username - %04d-%02d-%02d\n", Today();

	print $data if ($debug > 1);
}

#
# Replace the summary and patch table, using GIT data
#

$data = replace_table($sum_table_tag, $data, $sum_session, \@saturday, \@sunday, 1) if ($sum_session);
$data = replace_table($patch_table_tag, $data, $patch_session, \@saturday, \@sunday, 0) if ($patch_session);

print "$data\n" if ($debug);
exit if ($dry_run);

#
# Update the Twiki's page
#

print "Updating $url\n" if (!$debug);

$form->param("text", $data);
$form->param("forcenewrevision", 1);
$mech->submit();

__END__

=head1 NAME

weekly_report.pl - Generate and update a weekly report at Twiki, adding git patch statistics

=head1 SYNOPSIS

B<weekly_report.pl> --config FILE [--start-date DATE] [--week WEEK] [--year YEAR] [--dry-run] [--debug] [--help] [--man]

Where:

	--config FILE		Config file to be read
	--start-date DATE	Starting date to seek for GIT patches (default: Jan 01 2013)
	--week WEEK		Force a different week, instead of using today's week
	--year YEAR		Force a different year, instead of using today's year
	--dry-run		Don't update the Twiki page
	--debug			Enable debug
	--help			Show this summary
	--man			Show a man page

=head1 OPTIONS

=over 8

=item B<--config FILE>

Read the configuration from the file. The configuration file is on .ini format, e. g.:

[global]

	name = My Name
	username = MyUserName
	password = MyPassword
	domain = http://twiki.example.org/
	team = MyWorkTeam

[project foo]

	path = /devel/foo

[session Summary]

	template = summary.twiki
	summary = 1

[session Development]

	template = development.twiki
	patches = 1

The configuration file should always passed as a parameter, and should contain at least
one session, otherwise the script won't work.

=item B<--name NAME>

Specify the name of the person to be added at the report.

=item B<--username USER>

Specify the Twiki's username.

=item B<--password PASS>

Specify the Twiki's password.

=item B<--domain DOMAIN>

Specify the Twiki's URL domain.

=item B<--start-date DATE>

In order to speedup the script, don't seek the entire GIT revlist, but,
instead, seek only for patches after B<DATE>.

The date format is: year-mo-dy

If not specified, the script will assume the default (currently,
the first day of January in 2013, e. g. 2013-01-01.

=item B<--team TEAM>

Specify the team where the person belongs.

=item B<--week> WEEK

Specify the week of the year, starting with 1.

=item B<--year> YEAR

Specify the 4-digit year. The default is the current year.

=item B<--dry-run>

Do everything, except for updating the Twiki page. Useful for debug purposes.

=item B<--debug>

Enable debug messages. Useful when seeking for a trouble at the script.

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<weekly_report.pl> Generate and update a weekly report at Twiki, adding git patch statistic.

This script is useful for those that need/want to generate per-week reports, describing the
activities done along the week, and generating patch statistics, and patch tables.

Both patch statistics and patch tables require git repositories, although it should not be
hard to change the logic to also accept other types of SCM.

It should be noticed that the git repository locations and the report sessions are
currently described on some tables inside the source code.

For the sessions, the script will automatically fill an empty week with the contents of the
*.twiki data.

=head1 BUGS

Report bugs to Mauro Carvalho Chehab <m.chehab@samsung.com>

=head1 COPYRIGHT

Copyright (c) 2014 by Mauro Carvalho Chehab <m.chehab@samsung.com>.
Copyright (c) 2014 by Samsung Eletrônica da Amazônia.

License GPLv2: GNU GPL version 2 <http://gnu.org/licenses/gpl.html>.

This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.

=cut
