package HLstats_Common;

use Carp;
use Socket;

use strict;
use warnings;

require Exporter;
use base qw(Exporter);
our @EXPORT_OK = qw/FormatNumber FormatDate ResolveIp QueryHostGroups GetHostGroup ReadConfigFile PrintEvent IsNumber Abbr PrintNotice PrintDebug/;

our $version :shared;
$version = "<Unable to Detect>";

our %g_EventTables = (
	"TeamBonuses",
		["playerId", "actionId", "bonus"],
	"ChangeRole",
		["playerId", "role"],
	"ChangeName",
		["playerId", "oldName", "newName"],
	"ChangeTeam",
		["playerId", "team"],
	"Connects",
		["playerId", "ipAddress", "hostname", "hostgroup"],
	"Disconnects",
		["playerId"],
	"Entries",
		["playerId"],
	"Frags",
		["killerId", "victimId", "weapon", "headshot", "killerRole", "victimRole", "pos_x","pos_y","pos_z", "pos_victim_x","pos_victim_y","pos_victim_z"],
	"PlayerActions",
		["playerId", "actionId", "bonus", "pos_x","pos_y","pos_z"],
	"PlayerPlayerActions",
		["playerId", "victimId", "actionId", "bonus", "pos_x","pos_y","pos_z", "pos_victim_x","pos_victim_y","pos_victim_z"],
	"Suicides",
		["playerId", "weapon", "pos_x","pos_y","pos_z"],
	"Teamkills",
		["killerId", "victimId", "weapon", "pos_x","pos_y","pos_z", "pos_victim_x","pos_victim_y","pos_victim_z"],
	"Rcon",
		["type", "remoteIp", "password", "command"],
	"Admin",
		["type", "message", "playerName"],
	"Statsme",
		["playerId", "weapon", "shots", "hits", "headshots", "damage", "kills", "deaths"],
	"Statsme2",
		["playerId", "weapon", "head", "chest", "stomach", "leftarm", "rightarm", "leftleg", "rightleg"],
	"StatsmeLatency",
		["playerId", "ping"],
	"StatsmeTime",
		["playerId", "time"],
	"Latency",
		["playerId", "ping"],
	"Chat",
		["playerId", "message_mode", "message"]
);

my %configDirectives = (
	"DBHost",         \$::db_host,
	"DBUsername",     \$::db_user,
	"DBPassword",     \$::db_pass,
	"DBName",         \$::db_name,
	"DBLowPriority",  \$::db_lowpriority,
	"BindIP",         \$::s_ip,
	"Port",           \$::s_port,
	"DebugLevel",     \$::g_debug,
	"CpanelHack",     \$::g_cpanelhack,
	"EventQueueSize", \$::g_EventQueueSize,
	"SubmitCrashes",  \$::g_SubmitCrashes
);


sub FormatNumber
{
	local $_  = shift;
	1 while s/^(-?\d+)(\d{3})/$1,$2/;
	return $_;
}

sub FormatDate
{
  my $timestamp = shift;
  return sprintf('%dd %02d:%02d:%02dh', 
                  $timestamp / 86400, 
                  $timestamp / 3600 % 24, 
                  $timestamp / 60 % 60, 
                  $timestamp % 60 
                 );     
}

#
# string resolveIp (string ip, boolean quiet)
#
# Do a DNS reverse-lookup on an IP address and return the hostname, or empty
# string on error.
#

sub ResolveIp
{
	my ($ip, $quiet) = @_;
	my ($host) = "";
	
	unless ($::g_dns_resolveip)
	{
		return "";
	}
	
	eval
	{
		local $SIG{ALRM} = sub { croak("DNS Timeout\n") };
		alarm $::g_dns_timeout;  # timeout after $g_dns_timeout sec
		$host = gethostbyaddr(inet_aton($ip), AF_INET());
		alarm 0;
	};
	
	if ($@)
	{
		my $error = $@;
		chomp($error);
		PrintEvent("DNS", "Resolving hostname (timeout $::g_dns_timeout sec) for IP \"$ip\" - $error ", 1);
		$host = "";  # some error occurred
	}
	elsif (!defined($host))
	{
		PrintEvent("DNS", "Resolving hostname (timeout $::g_dns_timeout sec) for IP \"$ip\" - No Host ", 1);
		$host = "";  # ip did not resolve to any host
	} else {
		$host = lc($host);  # lowercase
		PrintEvent("DNS", "Resolving hostname (timeout $::g_dns_timeout sec) for IP \"$ip\" - $host ", 1);
	}
	chomp($host);
	return $host;
}


#
# object queryHostGroups ()
#
# Returns result identifier.
#

sub QueryHostGroups
{
	return $::g_db->DoQuery("
		SELECT
			pattern,
			name,
			LENGTH(pattern) AS patternlength
		FROM
			hlstats_HostGroups
		ORDER BY
			patternlength DESC,
			pattern ASC
	");
}


#
# string getHostGroup (string hostname[, object result])
#
# Return host group name if any match, or last 2 or 3 parts of hostname.
#

sub GetHostGroup
{
	my ($hostname, $result) = @_;
	my $hostgroup = "";
	
	# User can define special named hostgroups in hlstats_HostGroups, i.e.
	# '.adsl.someisp.net' => 'SomeISP ADSL'
	
	$result = QueryHostGroups()  unless ($result);
	$result->execute();
	
	while (my($pattern, $name) = $result->fetchrow_array())
	{
		$pattern = quotemeta($pattern);
		$pattern =~ s/\\\*/[^.]*/g;  # allow basic shell-style globbing in pattern
		if ($hostname =~ /$pattern$/)
		{
			$hostgroup = $name;
			last;
		}
	}
	$result->finish;
	
	if (!$hostgroup)
	{
		#
		# Group by last 2 or 3 parts of hostname, i.e. 'max1.xyz.someisp.net' as
		# 'someisp.net', and 'max1.xyz.someisp.net.nz' as 'someisp.net.nz'.
		# Unfortunately some countries do not have categorical SLDs, so this
		# becomes more complicated. The dom_nosld array below contains a list of
		# known country codes that do not use categorical second level domains.
		# If a country uses SLDs and is not listed below, then it will be
		# incorrectly grouped, i.e. 'max1.xyz.someisp.yz' will become
		# 'xyz.someisp.yz', instead of just 'someisp.yz'.
		#
		# Please mail psychonic@steamfriends.com with any additions.
		#
		
		my @dom_nosld = (
			"ca", # Canada
			"ch", # Switzerland
			"be", # Belgium
			"de", # Germany
			"ee", # Estonia
			"es", # Spain
			"fi", # Finland
			"fr", # France
			"ie", # Ireland
			"nl", # Netherlands
			"no", # Norway
			"ru", # Russia
			"se", # Sweden
		);
		
		my $dom_nosld = join("|", @dom_nosld);
		
		if ($hostname =~ /([\w-]+\.(?:$dom_nosld|\w\w\w))$/)
		{
			$hostgroup = $1;
		}
		elsif ($hostname =~ /([\w-]+\.[\w-]+\.\w\w)$/)
		{
			$hostgroup = $1;
		}
		else
		{
			$hostgroup = $hostname;
		}
	}
	
	return $hostgroup;
}


# Read Config File

sub ReadConfigFile
{
	my ($configfile) = @_;
	if ($configfile && -r $configfile)
	{
		my $conf = ConfigReaderSimple->new($configfile);
		$conf->parse();
		while ( my($directive, $variable) = each(%configDirectives))
		{
			if ($directive eq "Servers")
			{
				%$variable = $conf->get($directive);
			}
			else
			{
				$$variable = $conf->get($directive);
			}
		}
	}
	else
	{
		print "-- Warning: unable to open configuration file '$configfile'\n";
	}
	
	return;
}

#
# void setOptionsConf (hash optionsconf)
#
# Walk through configuration directives, setting values of global variables.
#




#
# string abbreviate (string thestring[, int maxlength)
#
# Returns thestring abbreviated to maxlength-3 characters plus "...", unless
# thestring is shorter than maxlength.
#

sub Abbr
{
	my ($thestring, $maxlength) = @_;
	
	$maxlength = 12  unless ($maxlength);
	
	if (length($thestring) > $maxlength)
	{
		$thestring = substr($thestring, 0, $maxlength - 3);
		return "$thestring...";
	}

	return $thestring;
}


#
# void PrintEvent (int code, string description)
#
# Logs event information to stdout.
#

sub PrintEvent
{
	my ($code, $description, $update_timestamp, $force_output) = @_;
	if ( ($::g_debug > 0 && $::g_stdin == 0) || ($::g_stdin == 1 && defined($force_output) && $force_output == 1) )
	{
		my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time());
		my $timestamp = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
		if (!defined($update_timestamp) || $update_timestamp == 0)
		{
			$timestamp = $::ev_timestamp; 
		}  
		if (IsNumber($code))
		{
			printf("%s: %21s - E%03d: %s\n", $timestamp, $::s_addr, $code, $description);
		}
		else
		{
			printf("%s: %21s - %s: %s\n", $timestamp, $::s_addr, $code, $description);
		}
	}
	
	return;
}

#
# void PrintDebug (message, minDebugLevel)
#
# Logs debug message if DebugLevel is set high enough
#

sub PrintDebug
{
	my ($message, $level) = @_;
	
	if (!defined($level))
	{
		$level = 1;
	}
	
	if ($::g_debug >= $level)
	{
		printf("%s: %21s - DEBUG: %s\n", $::ev_timestamp, $::s_addr, $message);
	}
	
	return;
}

#
# void PrintNotice (string notice)
#
# Prins a debugging notice to stdout.
#

sub PrintNotice
{
	my ($notice) = @_;
	
	if ($::g_debug > 1)
	{
		print ">> $notice\n";
	}
	
	return;
}

sub IsNumber
{
	my ($num) = @_;
	return ( $num ^ $num ) eq '0';
}

1;
