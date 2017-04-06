#!/usr/bin/perl
use strict;
use File::Temp;
use Date::Calc qw(:all);
use IPC::Open3;
use HTML::TokeParser::Simple;
use HTML::Entities;
use Getopt::Long;
use Config::IniFiles;
use Data::Dumper;

my $domain;
my $team;
my $username;

my $config_file;
my ($year,$month) = Today();

GetOptions(
        "cfg|config=s" => \$config_file,
        "month=s" => \$month,
        "year=s" => \$year,
) or die "unknown option";

die "config file is required" if (!$config_file);

sub get_week_range($$)
{
	my $month = shift;
	my $year = shift;
	my $day;

	($year,$month,$day) = Nth_Weekday_of_Month_Year($year, $month, 1, 1);

	my $start = Month_to_Text($month) . ", $day $year";
	my $week1 = Week_of_Year($year, $month, $day);

	if ($month == 12) {
		$day = 31;
	} else {
		my $mo = $month;
		($year,$month,$day) = Add_Delta_Days($year, $month, $day, 6);
		do {
			($year,$month,$day) = Add_Delta_Days($year, $month, $day, 7);
		} while ($mo == $month);
	}

	my $week2 = Week_of_Year($year, $month, $day);
	my $end = Month_to_Text($month) . ", $day $year";

	return ($week1, $week2, $start, $end);
}

my $full_name;
my (%week_contents, %week_title);

sub parse_week($$)
{
	my $week = shift;
	my $data = shift;
	my $mode;


	$data = decode_entities($data);


	open my $fh, "<", \$data;

	while (<$fh>) {
		next if (m/^\n/);

		if (m/^\-..\+\s+(.*)\s+\-\s+Week\s+(.*)/) {
			$full_name = $1 if (!$full_name);
			$week_title{$week} = $2;
			next;
		}

		if (m/^\-..\+.\s+(Summary|Meetings|Issues|Development)/) {
			$mode = $1;
			next;
		}
		if (m/^-..\+...*\s+(Patch Summary)/) {
			$mode = $1;
			next;
		}
		if (m/^-..\+...\+*\s+(.*\s+Table)/) {
			$mode = $1;
			next;
		}

		# Ignore notes
		next if (m/show the.*accountable events/);
		next if (m/reflects the incremental changes/);
		next if (m,^\&lt;br/\&gt;$,);

		# Ignore macros
		next if (m/\%.*\%/);

		next if (m/\-\-\s+Main.MauroCarvalhoChehab/);

		# Store everything else into a per-week hash of hash

		my $ln = $_;
		$ln = ~s/^   \*//;

		$week_contents{$week}{$mode} .= $_;
	}
	close $fh;
}

sub output_lines($)
{
	my $data = shift;

	printf "<ul>\n";

	open my $fh, "<", \$data;
	while (<$fh>) {
		my $ln = $_;
		$ln =~ s/\n//;
		printf "  <li>%s</li>\n", $ln;
	}
	close $fh;

	printf "</ul>\n";
}

sub output_table($)
{
	my $data = shift;

	printf '<table cellpadding="0" border="1" rules="all" cellspacing="0">';
	printf "\n";

	open my $fh, "<", \$data;
	while (<$fh>) {
		my $ln = $_;
		$ln =~ s/\n//;
		$ln =~ s/^\s*\|/<td>/;
		$ln =~ s,\|\s*$,</td>\n,;
		$ln =~ s,\|,</td>\n<td>,g;
		$ln =~ s,\*([^\*]+)\*,<strong>$1</strong>,g;

		printf "  <tr>%s</tr>\n", $ln;
	}
	close $fh;

	printf "</table>\n";
}

#
# MAIN
#

my ($week1, $week2, $start, $end) = get_week_range($month, $year);

## Read configuration data

my $cfg = Config::IniFiles->new(-file => $config_file);

$domain = $cfg->val('global', 'domain');
$team = $cfg->val('global', 'team');
$username = $cfg->val('global', 'username');

die "Config file syntax error" if (!$domain || !$team || !$username);

printf STDERR "$username from $start to $end (weeks: $week1 to $week2)\n";

# Get contents of weekly reports
for (my $week = $week1; $week <= $week2; $week++) {
	my $data;

	my $url = sprintf "%s/bin/view/%s/%sWeek%02dStatus%s?raw=on", $domain, $team, $username, $week, $year;

	print STDERR "$url\n";
	my $p = HTML::TokeParser::Simple->new(url => $url);

	while (my $tag = $p->get_tag('textarea')) {
		my $token = $p->get_token;
	        $data .= $token->as_is;
	}

	parse_week($week, $data);
}

# Output per-week contents

print "<h1>$full_name from $start to $end (weeks: $week1 to $week2)</h1>\n\n";

print "<h2>Summary<\h2>\n";
for (my $week = $week1; $week <= $week2; $week++) {
	if ($week_contents{$week}{"Summary"} || $week_contents{$week}{"Patch Summary"}) {
		printf "\n<h3>Week %s<\h3>\n\n",$week_title{$week};
		output_lines($week_contents{$week}{"Summary"});

		printf "\n<h4>Patch Summary<\h4>\n\n";
		output_table($week_contents{$week}{"Patch Summary"});
	}
}

print "\n<h2>Meetings<\h2>\n";
for (my $week = $week1; $week <= $week2; $week++) {
	if ($week_contents{$week}{"Meetings"}) {
		printf "\n<h3>Week %s<\h3>\n\n",$week_title{$week};
		output_lines($week_contents{$week}{"Meetings"});
	}
}

my $has_issues;

for (my $week = $week1; $week <= $week2; $week++) {
	if ($week_contents{$week}{"Issues"}) {
		print "\n<h2>Issues<\h2>\n" if (!$has_issues);
		$has_issues = 1;

		printf "\n<h3>Week %s<\h3>\n\n",$week_title{$week};
		output_lines($week_contents{$week}{"Issues"});
	}
}

print "\n<h2>Development<\h2>\n";
for (my $week = $week1; $week <= $week2; $week++) {
	if ($week_contents{$week}{"Development"}) {
		printf "\n<h3>Week %s<\h3>\n\n",$week_title{$week};
		output_lines($week_contents{$week}{"Development"});

		for my $table (keys %{$week_contents{$week}}) {
			next if ($table =~ m/(Summary|Patch Summary|Meetings|Issues|Development)/);

			printf "\n<h4>$table<\h4>\n\n";
			output_table($week_contents{$week}{$table});
		}

	}
}
