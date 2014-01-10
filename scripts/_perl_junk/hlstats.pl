#!/usr/bin/perl
# HLstatsX Community Edition - Real-time player and clan rankings and statistics
# Copyleft (L) 2008-20XX Nicholas Hastings (nshastings@gmail.com)
# http://www.hlxce.com
#
# HLstatsX Community Edition is a continuation of 
# ELstatsNEO - Real-time player and clan rankings and statistics
# Copyleft (L) 2008-20XX Malte Bayer (steam@neo-soft.org)
# http://ovrsized.neo-soft.org/
# 
# ELstatsNEO is an very improved & enhanced - so called Ultra-Humongus Edition of HLstatsX
# HLstatsX - Real-time player and clan rankings and statistics for Half-Life 2
# http://www.hlstatsx.com/
# Copyright (C) 2005-2007 Tobias Oetzel (Tobi@hlstatsx.com)
#
# HLstatsX is an enhanced version of HLstats made by Simon Garner
# HLstats - Real-time player and clan rankings and statistics for Half-Life
# http://sourceforge.net/projects/hlstats/
# Copyright (C) 2001  Simon Garner
#             
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
# 
# For support and installation notes visit http://www.hlxce.com

use strict;
use warnings;

##
## Settings
##

# $opt_configfile - Absolute path and filename of configuration file.
my $opt_configfile = "./hlstats.conf";

# $opt_libdir - Directory to look in for local required files
#               (our *.plib, *.pm files).
our $opt_libdir = "./";


##
##
################################################################################
## No need to edit below this line
##

unshift @INC, $opt_libdir;

use Getopt::Long;
use Time::Local;
use IO::Socket;
use IO::Select;
use DBI;
use Digest::MD5;
use Encode;
use bytes;
use Carp;
use threads;
use threads::shared;

eval {
	# for crash uploader
	require LWP::UserAgent;
	require HTTP::Request::Common;
};

#  Perl didn't support shared array refs in versions before 5.8.9
if ($] < 5.008009)
{
	eval {
		require Thread::Queue::Any;
	};
	import Thread::Queue::Any;
}
else
{
	use Thread::Queue;
}

local $SIG{HUP} = 'HUP_handler';
if ($^O eq "Win32")
{
	$SIG{INT2} = 'INT_handler';  # windows
}
else
{
	$SIG{INT} = 'INT_handler';  # unix
}
$SIG{__DIE__} = 'DIE_handler';
$SIG{__WARN__} = 'WARN_handler';

do "HLstats_GameConstants.plib";

# Ultra globals
our $g_queryqueue;
our $g_rconqueue;
if ($] < 5.008009)
{
	$g_queryqueue = Thread::Queue::Any->new();
	$g_rconqueue = Thread::Queue::Any->new();
}
else
{
	$g_queryqueue = Thread::Queue->new();
	$g_rconqueue = Thread::Queue->new();
}

our %g_servers;
our %g_players;
our $g_db;
our $s_addr = "";
our $g_debug = 1;
our $g_mode = TRACKMODE_NORMAL();
our $g_rcon = 1;
our $g_rcon_record = 1;
our $g_ranktype = "skill";
our $g_stdin = 0;
our $g_mailto = "";
our $g_mailpath = "/bin/mail";
our $g_dns_resolveip = 1;
our $g_dns_timeout = 5;
our $g_global_chat = 0;
our $g_log_chat = 0;
our $g_log_chat_admins = 0;
our $g_player_minkills = 50;
our $g_cpanelhack = 0;
our $g_EventQueueSize = 10;
our $g_SubmitCrashes :shared;
$g_SubmitCrashes = 0;

require ConfigReaderSimple;
require HLstats_DB;
require HLstats_Common;
HLstats_Common->import(qw/FormatNumber FormatDate ResolveIp QueryHostGroups GetHostGroup
						ReadConfigFile PrintEvent Abbr IsNumber PrintNotice PrintDebug/);
require TRcon;
require BASTARDrcon;
require HLstats_Server;
require HLstats_Player;
require HLstats_Game;
require HLstats_EventMgr;

# silly perl syntax for flushing after every write/print
local $| = 1;

Getopt::Long::Configure ("bundling");

my $last_trend_timestamp = 0;

binmode STDIN, ":utf8";
binmode STDOUT, ":utf8";

##
## Globals
##

our %g_config_servers = ();

our %g_games = ();


##
## MAIN
##

# Options

my $opt_help = 0;
my $opt_version = 0;

my $configfile = undef;

our $db_host = "localhost";
our $db_user = "";
our $db_pass = "";
our $db_name = "hlstats";
our $db_lowpriority = 1;

our $s_ip = "";
our $s_port = "27500";

my $g_deletedays = 5;
my $g_requiremap = 0;
my $g_nodebug = 0;
my $g_rcon_ignoreself = 0;
my $g_server_ip = "";
my $g_server_port = 27015;
my $g_timestamp = 0;
our $g_skill_maxchange = 100;
our $g_skill_minchange = 2;
our $g_skill_ratio_cap = 0;
our $g_geoip_binary = 0;
my $g_onlyconfig_servers = 1;
my $g_track_stats_trend = 0;
my %g_lan_noplayerinfo = ();
my %g_preconnect = ();
my $g_global_banning = 0;
my %g_gi;
my $g_proxy_key = "";
my %g_EventTableData = ();
my $g_threadname = "main";
my $g_dbversion :shared;
$g_dbversion = 0;

# We'll reuse this later for making server matches with secrets
my $g_logpattern = "^L (\\d\\d)\\/(\\d\\d)\\/(\\d{4}) - (\\d\\d):(\\d\\d):(\\d\\d):\\s(.*)";
# and this will be our general match otherwise
my $g_logmatch = qr/$g_logpattern/;

my %directives_mysql = (
	"version",                 "HLstats_Common::version",
	"MailTo",                  "g_mailto",
	"MailPath",                "g_mailpath",
	"Mode",                    "g_mode",
	"DeleteDays",              "g_deletedays",
	"UseTimestamp",            "g_timestamp",
	"DNSResolveIP",            "g_dns_resolveip",
	"DNSTimeout",              "g_dns_timeout",
	"RconIgnoreSelf",          "g_rcon_ignoreself",
	"Rcon",                    "g_rcon",
	"RconRecord",              "g_rcon_record",
	"SkillMaxChange",          "g_skill_maxchange",
	"SkillMinChange",          "g_skill_minchange",
	"PlayerMinKills",          "g_player_minkills",
	"AllowOnlyConfigServers",  "g_onlyconfig_servers",
	"TrackStatsTrend",         "g_track_stats_trend",
	"GlobalBanning",           "g_global_banning",
	"LogChat",                 "g_log_chat",
	"LogChatAdmins",           "g_log_chat_admins",
	"GlobalChat",              "g_global_chat",
	"SkillRatioCap",           "g_skill_ratio_cap",
	"rankingtype",             "g_ranktype",
	"UseGeoIPBinary",          "g_geoip_binary",
	"Proxy_Key",               "g_proxy_key"
);

my %dysweaponcodes = (
	"1" => "Light Katana",
	"2" => "Medium Katana",
	"3" => "Fatman Fist",
	"4" => "Machine Pistol",
	"5" => "Shotgun",
	"6" => "Laser Rifle",
	"7" => "BoltGun",
	"8" => "SmartLock Pistols",
	"9" => "Assault Rifle",
	"10" => "Grenade Launcher",
	"11" => "MK-808 Rifle",
	"12" => "Tesla Rifle",
	"13" => "Rocket Launcher",
	"14" => "Minigun",
	"15" => "Ion Cannon",
	"16" => "Basilisk",
	"17" => "Frag Grenade",
	"18" => "EMP Grenade",
	"19" => "Spider Grenade",
	"22" => "Cortex Bomb"
);

my @hlxceFileNames = (
	"BASTARDrcon.pm",
	"hlstats.pl",
	"HLstats_Common.pm",
	"HLstats_DB.pm",
	"HLstats_EventMgr.pm",
	"HLstats_Game.pm",
	"HLstats_Player.pm",
	"HLstats_Server.pm",
	"TRcon.pm"
);

my %g_ThreadQueueMap :shared;

# Usage message

my $usage = <<"USAGE"
Usage: hlstats.pl [OPTION]...
Collect statistics from one or more Half-Life2 servers for insertion into
a MySQL database.

  -h, --help                      display this help and exit  
  -v, --version                   output version information and exit
  -d, --debug                     enable debugging output (-dd for more)
  -n, --nodebug                   disables above; reduces debug level
  -m, --mode=MODE                 player tracking mode. 1 - Normal (SteamID), 2 - LAN (IP)  [$g_mode]
      --db-host=HOST              database ip or ip:port  [$db_host]
      --db-name=DATABASE          database name  [$db_name]
      --db-password=PASSWORD      database password (WARNING: specifying the
                                    password on the command line is insecure.
                                    Use the configuration file instead.)
      --db-username=USERNAME      database username
      --dns-resolveip             resolve player IP addresses to hostnames
                                    (requires working DNS)
   -c,--configfile                Specific configfile to use, settings in this file can now
                                    be overidden with commandline settings.
      --nodns-resolveip           disables above
      --dns-timeout=SEC           timeout DNS queries after SEC seconds  [$g_dns_timeout]
  -i, --ip=IP                     set IP address to listen on for UDP log data
  -p, --port=PORT                 set port to listen on for UDP log data  [$s_port]
  -r, --rcon                      enables rcon command exec support (the default)
      --norcon                    disables rcon command exec support
  -s, --stdin                     read log data from standard input, instead of
                                    from UDP socket. Must specify --server-ip
                                    and --server-port to indicate the generator
                                    of the inputted log data (implies --norcon)
      --nostdin                   disables above
      --server-ip                 specify data source IP address for --stdin
      --server-port               specify data source port for --stdin  [$g_server_port]
  -t, --timestamp                 tells HLstatsX:CE to use the timestamp in the log
                                    data, instead of the current time on the
                                    database server, when recording events
      --notimestamp               disables above
      --event-queue-size=SIZE     manually set event queue size to control flushing
                                    (recommend 100+ for STDIN)

Long options can be abbreviated, where such abbreviation is not ambiguous.
Default values for options are indicated in square brackets [...].

Most options can be specified in the configuration file:
  $opt_configfile
Note: Options set on the command line take precedence over options set in the
configuration file. The configuration file name is set at the top of hlstats.pl.

HLstatsX: Community Edition http://www.hlxce.com

USAGE
;

# Init Timestamp
my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time());
our $ev_timestamp = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
our $ev_unixtime = time();
our $ev_remotetime = $ev_unixtime;
my $s_socket;
my $s_peerhost;
my $s_peerport;
my $s_output = "";

# Read Config File
ReadConfigFile($opt_configfile);

# Read Command Line Arguments

my %copts = ();

eval {
	GetOptions(
		"help|h"          =>  \$copts{opt_help},
		"version|v"       =>  \$copts{opt_version},
		"debug|d+"        =>  \$copts{g_debug},
		"nodebug|n+"      =>  \$copts{g_nodebug},
		"mode|m=i"        =>  \$copts{g_mode},
		"configfile|c=s"  =>  \$copts{configfile},
		"db-host=s"       =>  \$copts{db_host},
		"db-name=s"       =>  \$copts{db_name},
		"db-password=s"   =>  \$copts{db_pass},
		"db-username=s"   =>  \$copts{db_user},
		"dns-resolveip!"  =>  \$copts{g_dns_resolveip},
		"dns-timeout=i"   =>  \$copts{g_dns_timeout},
		"ip|i=s"          =>  \$copts{s_ip},
		"port|p=i"        =>  \$copts{s_port},
		"rcon!"           =>  \$copts{g_rcon},
		"r"               =>  \$copts{g_rcon},
		"stdin!"          =>  \$copts{g_stdin},
		"s"               =>  \$copts{g_stdin},
		"server-ip=s"     =>  \$copts{g_server_ip},
		"server-port=i"   =>  \$copts{g_server_port},
		"timestamp!"      =>  \$copts{g_timestamp},
		"t"               =>  \$copts{g_timestamp},
		"event-queue-size" => \$copts{g_EventQueueSize}
	);
};
if ($@)
{
	print ($usage);
	exit 1;
}

if (defined($configfile))
{
	ReadConfigFile($configfile);
}

sub MySetOptionsConf
{
	my (%optionsconf) = @_;
	
	while (my ($thekey, $theval) = each(%optionsconf))
	{
		if($theval)
		{
			my $tmp = "\$".$thekey." = '$theval'";
			#print " -> setting ".$tmp."\n";
			eval $tmp;
		}
	}
	
	return;
}
# these are set above, we then reload them to override values in the actual config
MySetOptionsConf(%copts);

if (!defined($g_SubmitCrashes))
{
	$g_SubmitCrashes = 0;
}

if ($g_cpanelhack)
{
	my $home_dir = $ENV{ HOME };
	my $base_module_dir = (-d "$home_dir/perl" ? "$home_dir/perl" : ( getpwuid($>) )[7] . '/perl/');
	unshift @INC, map { $base_module_dir . $_ } @INC;
}

eval {
  require Geo::IP::PurePerl;
};
import Geo::IP::PurePerl;

if ($opt_help)
{
	print $usage;
	exit(0);
}

if ($opt_version)
{
	$g_db = HLstats_DB->new($db_host, $db_name, $db_user, $db_pass);
	my $result = $g_db->DoQuery("SELECT value FROM hlstats_Options WHERE keyname='version'");

	if ($result->rows > 0)
	{
		$HLstats_Common::version = $result->fetchrow_array;
	}
	$result->finish;
	
	print "\nhlstats.pl (HLstatsX Community Edition) Version $HLstats_Common::version\n"
		. "Real-time player and clan rankings and statistics for Half-Life 2\n"
		. "Modified (C) 2008-20XX  Nicholas Hastings (nshastings\@gmail.com)\n"
		. "Copyleft (L) 2007-2008  Malte Bayer\n"
		. "Modified (C) 2005-2007  Tobias Oetzel (Tobi\@hlstatsx.com)\n"
		. "Original (C) 2001 by Simon Garner \n\n";
	
	print "Using ConfigReaderSimple module version $ConfigReaderSimple::VERSION\n";
	
	if ($g_rcon)
	{
		print "Using rcon module\n";
	}
	
	print "\nThis is free software; see the source for copying conditions.  There is NO\n"
		. "warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.\n\n";
	exit(0);
}

# Connect to the database
$g_db = HLstats_DB->new($db_host, $db_name, $db_user, $db_pass);
# Start async query thread as well
my $qthread = threads->new(\&DBThread);
if (!$qthread)
{
	croak("Failed to create query thread");
}

$g_ThreadQueueMap{$qthread->tid()} = $g_queryqueue;

# And async rcon thread while we're at it
my $rthread = threads->new(\&RconThread);
if (!$rthread)
{
	croak("Failed to create rcon thread");
}

$g_ThreadQueueMap{$rthread->tid()} = $g_rconqueue;

&readDatabaseConfig;
BuildEventInsertData();

if (!$g_mode)
{
	$g_mode = TRACKMODE_NORMAL();
}

$g_debug -= $g_nodebug;
$g_debug = 0 if ($g_debug < 0);


# Startup

&PrintEvent("HLSTATSX", "HLstatsX:CE $HLstats_Common::version starting...", 1);

# Create the UDP & TCP socket

if ($g_stdin)
{
	$g_rcon = 0;
	&PrintEvent("UDP", "UDP listen socket disabled, reading log data from STDIN.", 1);
	if (!$g_server_ip || !$g_server_port)
	{
		&PrintEvent("UDP", "ERROR: You must specify source of STDIN data using --server-ip and --server-port", 1);
		&PrintEvent("UDP", "Example: ./hlstats.pl --stdin --server-ip 12.34.56.78 --server-port 27015", 1);
		exit(255);
	}
	else
	{
		&PrintEvent("UDP", "All data from STDIN will be allocated to server '$g_server_ip:$g_server_port'.", 1);
		$s_peerhost = $g_server_ip;
		$s_peerport = $g_server_port;
		$s_addr = "$s_peerhost:$s_peerport";
	}
}
else
{
	my $ip;
	if ($s_ip)
	{
		$ip = $s_ip . ":";
	}
	else
	{
		$ip = "port ";
	}
	$s_socket = IO::Socket::INET->new(
		Proto=>"udp",
		LocalAddr=>"$s_ip",
		LocalPort=>"$s_port"
	) or die ("\nCan't setup UDP socket on $ip$s_port: $!\n");
	
	&PrintEvent("UDP", "Opening UDP listen socket on $ip$s_port ... ok", 1);
}

if ($g_track_stats_trend > 0) {
	&PrintEvent("HLSTATSX", "Tracking Trend of the stats are enabled", 1);
}

if ($g_global_banning > 0) {
	&PrintEvent("HLSTATSX", "Global Banning on all servers is enabled", 1);
}

&PrintEvent("HLSTATSX", "Maximum Skill Change on all servers are ".$g_skill_maxchange." points", 1);
&PrintEvent("HLSTATSX", "Minimum Skill Change on all servers are ".$g_skill_minchange." points", 1);
&PrintEvent("HLSTATSX", "Minimum Players Kills on all servers are ".$g_player_minkills." kills", 1);

if ($g_log_chat > 0)
{
	&PrintEvent("HLSTATSX", "Players chat logging is enabled", 1);
	if ($g_log_chat_admins > 0)
	{
		&PrintEvent("HLSTATSX", "Admins chat logging is enabled", 1);
	}
}

if ($g_global_chat == 1) {
	&PrintEvent("HLSTATSX", "Broadcasting public chat to all players is enabled", 1);
} elsif ($g_global_chat == 2) {
	&PrintEvent("HLSTATSX", "Broadcasting public chat to admins is enabled", 1);
} else {
	&PrintEvent("HLSTATSX", "Broadcasting public chat is disabled", 1);
}

if (!defined($g_EventQueueSize))
{
	$g_EventQueueSize = 10;
}
&PrintEvent("HLSTATSX", "Event queue size is set to ".$g_EventQueueSize, 1);

&PrintEvent("HLSTATSX", "HLstatsX:CE is now running (tracking mode $g_mode, debug level $g_debug)", 1);

my $start_time = time();
my $start_parse_time = time();
my $parse_time = 0;
my $import_logs_count = 0;
if ($g_stdin)
{
  $g_timestamp       = 1;
  $start_parse_time  = time();
  PrintEvent("IMPORT", "Start importing logs. Every dot signs 500 parsed lines", 1, 1);
}

# Main data loop
my $c = 0;

sub getLine
{
	if ($g_stdin) {
		return <STDIN>;
	} else {
		return 1;
	}
}


$g_db->DoFastQuery("TRUNCATE TABLE hlstats_Livestats");
my $timeout    = 0;
my ($proxy_s_peerhost, $proxy_s_peerport);
while ($s_output = &getLine()) {

    my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time());
    $ev_timestamp = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
	$ev_unixtime  = time();
	my $rproxy_key = "";

	if ($g_stdin && $import_logs_count > 0 && (($import_logs_count % 500) == 0))
	{
		$parse_time = time() - $start_parse_time;
		if ($parse_time == 0)
		{
			$parse_time++;
		}
		print ". [".($parse_time)." sec (".sprintf("%.3f", (500 / $parse_time)).")]\n";
		$start_parse_time = time();
	}
	else
	{
		if (IO::Select->new($s_socket)->can_read(2))
		{  # 2 second timeout
			$s_socket->recv($s_output, 1024);
			$s_output = decode( 'utf8', $s_output );
			$timeout = 0;
		}
		else
		{
			$timeout++;
			if ($timeout % 60 == 0)
			{
				&PrintEvent("HLSTATSX", "No data since 120 seconds");
			}    
		}

		#if (($s_output =~ /^.*PROXY\sKey=(.+)\s(.*)PROXY.+/x) && $g_proxy_key ne "")
		#{
		#	$rproxy_key = $1;
		#	$s_addr = $2;
		#
		#	if ($s_addr ne "")
		#	{
		#		($s_peerhost, $s_peerport) = split(/:/, $s_addr);
		#	}
		#
		#	$proxy_s_peerhost = $s_socket->peerhost;
		#	$proxy_s_peerport  = $s_socket->peerport;
		#	&PrintEvent("PROXY", "Detected proxy call from $proxy_s_peerhost:$proxy_s_peerport") if ($g_debug > 2);
		#
		#
		#	if ($g_proxy_key eq $rproxy_key)
		#	{
		#		$s_output =~ s/PROXY.*PROXY //;
		#		if ($s_output =~ /^C;HEARTBEAT;/)
		#		{
		#			&PrintEvent("PROXY, Heartbeat request from $proxy_s_peerhost:$proxy_s_peerport");
		#		}
		#		elsif ($s_output =~ /^C;RELOAD;/)
		#		{
		#			&PrintEvent("PROXY, Reload request from $proxy_s_peerhost:$proxy_s_peerport");
		#		}
		#		elsif ($s_output =~ /^C;KILL;/)
		#		{
		#			&PrintEvent("PROXY, Kill request from $proxy_s_peerhost:$proxy_s_peerport");
		#		}
		#		else
		#		{
		#			&PrintEvent("PROXY", $s_output);
		#		}
		#	}
		#	else
		#	{
		#		&PrintEvent("PROXY", "proxy_key mismatch, dropping package");
		#		&PrintEvent("PROXY", $s_output) if ($g_debug > 2);
		#		$s_output = "";
		#		next;
		#	}
		#}
		#else
		#{
		#	# Reset the proxy stuff and use it as "normal"
		#	$rproxy_key = "";
		#	$proxy_s_peerhost = "";
		#	$proxy_s_peerport = "";
		#
			$s_peerhost  = $s_socket->peerhost;
			$s_peerport  = $s_socket->peerport;
		
			if ($s_peerhost && $s_peerport)
			{
				$s_addr = "$s_peerhost:$s_peerport";
			}
		#}
	}

	if ($timeout == 0)
	{
		# Logs from STDIN don't have to worry about CONTROL commands or log packet types
		my $check_secret = 0;
		if (!$g_stdin)
		{
			my ($address, $port);
			my @data = split ";", $s_output;
			my $cmd = $data[0];
			if ($cmd eq "C" && ($s_peerhost eq "127.0.0.1" || (($g_proxy_key eq $rproxy_key) && $g_proxy_key ne "")))
			{
				#&PrintEvent("CONTROL", "Command received: ".$data[1], 1);
				#if ($proxy_s_peerhost ne "" && $proxy_s_peerport ne "")
				#{
				#	$address = $proxy_s_peerhost;
				#	$port = $proxy_s_peerport;
				#}
				#else
				#{
					$address = $s_peerhost;
					$port = $s_peerport;
				#}
				
				$s_addr = "$address:$port";
				
				my $dest = sockaddr_in($port, inet_aton($address));
				my $bytes;
				if ($data[1] eq "HEARTBEAT")
				{
					my $msg = "Heartbeat OK";
					$bytes = send($::s_socket, $msg, 0, $dest);
					&PrintEvent("CONTROL", "Send heartbeat status to frontend at '$address:$port'", 1);
				}
				else
				{
					my $msg = "OK, EXECUTING COMMAND: ".$data[1];
					$bytes = send($::s_socket, $msg, 0, $dest);
					&PrintEvent("CONTROL", "Sent $bytes bytes to frontend at '$address:$port'", 1);
				}
				
				if ($data[1] eq "RELOAD")
				{
					PrintEvent("CONTROL", "Re-Reading Configuration by request from Frontend...", 1);
					ReloadConfiguration();
				}
				elsif ($data[1] eq "KILL")
				{
					PrintEvent("CONTROL", "SHUTTING DOWN SCRIPT", 1);
					FlushAll();
					exit 0;
				} 
				
				next;
			}
			elsif ($s_output =~ /^(R|S)(.*)/)
			{
				if ($1 eq "S")
				{
					$check_secret = 1;
				}
				$s_output = $2;
				# Log line should match what would be on STDIN now unless there is a secret
			}
			else
			{
				PrintEvent(998, "MALFORMED DATA: " . $s_output);
				next;
			}
		}
		
		$s_output =~ tr/[\r\n\0]//d;     # remove naughty characters
		
		# Get the server info, if we know the server, otherwise ignore the data
		if (!defined($g_servers{$s_addr}))
		{
			if ($g_onlyconfig_servers == 1 && !defined($g_config_servers{$s_addr}))
			{
				# HELLRAISER disabled this for testing
				&PrintEvent(997, "NOT ALLOWED SERVER: " . $s_output);
				next;
			}
			elsif (!defined($g_config_servers{$s_addr})) # create std cfg.
			{
				my %std_cfg;
				$std_cfg{MinPlayers}                      = 6;
				$std_cfg{HLStatsURL}                      = "";
				$std_cfg{DisplayResultsInBrowser}         = 0;
				$std_cfg{BroadCastEvents}                 = 0;
				$std_cfg{BroadCastPlayerActions}          = 0;
				$std_cfg{BroadCastEventsCommand}          = "say";
				$std_cfg{BroadCastEventsCommandAnnounce}  = "say";
				$std_cfg{PlayerEvents}                    = 1;
				$std_cfg{PlayerEventsCommand}             = "say";
				$std_cfg{PlayerEventsCommandOSD}          = "";
				$std_cfg{PlayerEventsCommandHint}         = "";
				$std_cfg{PlayerEventsAdminCommand}        = "";
				$std_cfg{ShowStats}                       = 1;
				$std_cfg{TKPenalty}                       = 50;
				$std_cfg{SuicidePenalty}                  = 5;
				$std_cfg{AutoTeamBalance}                 = 0;
				$std_cfg{AutobanRetry}                    = 0;
				$std_cfg{TrackServerLoad}                 = 0;
				$std_cfg{MinimumPlayersRank}              = 0;
				$std_cfg{EnablePublicCommands}            = 1;
				$std_cfg{Admins}                          = "";
				$std_cfg{SwitchAdmins}                    = 0;
				$std_cfg{IgnoreBots}                      = 1;
				$std_cfg{SkillMode}                       = 0;
				$std_cfg{GameType}                        = 0;
				$std_cfg{Mod}                             = "";
				$std_cfg{BonusRoundIgnore}                = 0;
				$std_cfg{BonusRoundTime}                  = 20;
				$std_cfg{UpdateHostname}                  = 0;
				$std_cfg{ConnectAnnounce}                 = 1;
				$std_cfg{DefaultDisplayEvents}            = 1;
				%{$g_config_servers{$s_addr}}             = %std_cfg;
				&PrintEvent("CFG", "Created default config for unknown server [$s_addr]");
				&PrintEvent("DETECT", "New server with game: " . &getServerMod($s_peerhost, $s_peerport));
			}
			
			if ($g_config_servers{$s_addr})
			{
				my $tempsrv = &getServer($s_peerhost, $s_peerport);
				next if ($tempsrv == 0);
				$g_servers{$s_addr} = $tempsrv;
				my %s_cfg = %{$g_config_servers{$s_addr}};
				$g_servers{$s_addr}->{minplayers} = $s_cfg{MinPlayers};
				$g_servers{$s_addr}->{hlstats_url} = $s_cfg{HLStatsURL};
				$g_servers{$s_addr}->SetIngameUrl();
				
				if ($s_cfg{DisplayResultsInBrowser} > 0)
				{
					$g_servers{$s_addr}->{use_browser} = 1;
					&PrintEvent("SERVER", "Query results will displayed in valve browser", 1); 
				}
				else
				{ 
					$g_servers{$s_addr}->{use_browser} = 0;
					&PrintEvent("SERVER", "Query results will not displayed in valve browser", 1); 
				}
				
				if ($s_cfg{"ShowStats"} == 1)
				{
					$g_servers{$s_addr}->{show_stats} = 1;
					&PrintEvent("SERVER", "Showing stats is enabled", 1); 
				}
				else
				{
					$g_servers{$s_addr}->{show_stats} = 0;
					&PrintEvent("SERVER", "Showing stats is disabled", 1); 
				}
				
				if ($s_cfg{"BroadCastEvents"} == 1)
				{
					$g_servers{$s_addr}->{broadcasting_events} = 1;
					$g_servers{$s_addr}->{broadcasting_player_actions} = $s_cfg{BroadCastPlayerActions};
					$g_servers{$s_addr}->{broadcasting_command} = $s_cfg{BroadCastEventsCommand};
					if ($s_cfg{BroadCastEventsCommandAnnounce} eq "ma_hlx_csay")
					{
						$s_cfg{BroadCastEventsCommandAnnounce} = $s_cfg{BroadCastEventsCommandAnnounce}." #all";
					}
					$g_servers{$s_addr}->{broadcasting_command_announce} = $s_cfg{BroadCastEventsCommandAnnounce};
					
					&PrintEvent("SERVER", "Broadcasting Live-Events with \"".$s_cfg{BroadCastEventsCommand}."\" is enabled", 1); 
					if ($s_cfg{BroadCastEventsCommandAnnounce} ne "")
					{
						&PrintEvent("SERVER", "Broadcasting Announcements with \"".$s_cfg{BroadCastEventsCommandAnnounce}."\" is enabled", 1); 
					}  
				}
				else
				{
					$g_servers{$s_addr}->{broadcasting_events} = 0;
					&PrintEvent("SERVER", "Broadcasting Live-Events is disabled", 1); 
				}
				
				if ($s_cfg{PlayerEvents} == 1)
				{
					$g_servers{$s_addr}->{player_events} = 1;
					$g_servers{$s_addr}->{player_command} = $s_cfg{PlayerEventsCommand};
					$g_servers{$s_addr}->{player_command_osd} = $s_cfg{PlayerEventsCommandOSD};
					$g_servers{$s_addr}->{player_command_hint} = $s_cfg{PlayerEventsCommandHint};
					$g_servers{$s_addr}->{player_admin_command} = $s_cfg{PlayerEventsAdminCommand};
					&PrintEvent("SERVER", "Player Event-Handler with \"".$s_cfg{PlayerEventsCommand}."\" is enabled", 1); 
					if ($s_cfg{"PlayerEventsCommandOSD"} ne "") {
						&PrintEvent("SERVER", "Displaying amx style menu with \"".$s_cfg{"PlayerEventsCommandOSD"}."\" is enabled", 1); 
					}
				} else {
					$g_servers{$s_addr}->{player_events} = 0;
					&PrintEvent("SERVER", "Player Event-Handler is disabled", 1); 
				}
				if ($s_cfg{DefaultDisplayEvents} > 0) {
					$g_servers{$s_addr}->{default_display_events} = "1";
					&PrintEvent("SERVER", "New Players defaulting to show event messages", 1);
				} else {
					$g_servers{$s_addr}->{default_display_events} = "0";
					&PrintEvent("SERVER", "New Players defaulting to NOT show event messages", 1);
				}
				if ($s_cfg{TrackServerLoad} > 0) {
					$g_servers{$s_addr}->{track_server_load} = "1";
					&PrintEvent("SERVER", "Tracking server load is enabled", 1);
				} else {
					$g_servers{$s_addr}->{track_server_load} = "0";
					&PrintEvent("SERVER", "Tracking server load is disabled", 1);
				}
				
				if ($s_cfg{TKPenalty} > 0) {
					$g_servers{$s_addr}->{tk_penalty} = $s_cfg{TKPenalty};
					&PrintEvent("SERVER", "Penalty team kills with ".$s_cfg{TKPenalty}." points", 1);
				}  
				if ($s_cfg{SuicidePenalty} > 0) {
					$g_servers{$s_addr}->{suicide_penalty} = $s_cfg{SuicidePenalty};
					&PrintEvent("SERVER", "Penalty suicides with ".$s_cfg{SuicidePenalty}." points", 1);
				}  
				if ($s_cfg{BonusRoundTime} > 0) {
					$g_servers{$s_addr}->{bonusroundtime} = $s_cfg{BonusRoundTime};
					&PrintEvent("SERVER", "Bonus Round time set to: ".$s_cfg{BonusRoundTime}, 1);
				} 
				if ($s_cfg{BonusRoundIgnore} > 0) {
					$g_servers{$s_addr}->{bonusroundignore} = $s_cfg{BonusRoundIgnore};
					&PrintEvent("SERVER", "Bonus Round is being ignored. Length: (".$s_cfg{BonusRoundTime}.")", 1);
				}
				if ($s_cfg{AutoTeamBalance} > 0) {
					$g_servers{$s_addr}->{ba_enabled} = "1";
					&PrintEvent("TEAMS", "Auto-Team-Balancing is enabled", 1);
				} else {
					$g_servers{$s_addr}->{ba_enabled} = "0";
					&PrintEvent("TEAMS", "Auto-Team-Balancing is disabled", 1);
				}
				if ($s_cfg{AutoBanRetry} > 0) {
					$g_servers{$s_addr}->{auto_ban} = "1";
					&PrintEvent("TEAMS", "Auto-Retry-Banning is enabled", 1);
				} else {
					$g_servers{$s_addr}->{auto_ban} = "0";
					&PrintEvent("TEAMS", "Auto-Retry-Banning is disabled", 1);
				}
				
				if ($s_cfg{MinimumPlayersRank} > 0) {
					$g_servers{$s_addr}->{min_players_rank} = $s_cfg{MinimumPlayersRank};
					&PrintEvent("SERVER", "Requires minimum players rank is enabled [MinPos:".$s_cfg{MinimumPlayersRank}."]", 1);
				} else {
					$g_servers{$s_addr}->{min_players_rank} = "0";
					&PrintEvent("SERVER", "Requires minimum players rank is disabled", 1);
				}
				
				if ($s_cfg{EnablePublicCommands} > 0) {
					$g_servers{$s_addr}->{public_commands} = $s_cfg{EnablePublicCommands};
					&PrintEvent("SERVER", "Public chat commands are enabled", 1);
				} else {
					$g_servers{$s_addr}->{public_commands} = "0";
					&PrintEvent("SERVER", "Public chat commands are disabled", 1);
				}
				
				if ($s_cfg{Admins} ne "") {
					@{$g_servers{$s_addr}->{admins}} = split(/,/, $s_cfg{Admins});
					foreach(@{$g_servers{$s_addr}->{admins}})
					{
						$_ =~ s/^STEAM_[0-9]+?\://i;
					}
					&PrintEvent("SERVER", "Admins: ".$s_cfg{Admins}, 1);
				}
				
				if ($s_cfg{SwitchAdmins} > 0) {
					$g_servers{$s_addr}->{switch_admins} = "1";
					&PrintEvent("TEAMS", "Switching Admins on Auto-Team-Balance is enabled", 1);
				} else {
					$g_servers{$s_addr}->{switch_admins} = "0";
					&PrintEvent("TEAMS", "Switching Admins on Auto-Team-Balance is disabled", 1);
				}
				
				if ($s_cfg{IgnoreBots} > 0) {
					$g_servers{$s_addr}->{ignore_bots} = "1";
					&PrintEvent("SERVER", "Ignoring bots is enabled", 1);
				} else {
					$g_servers{$s_addr}->{ignore_bots} = "0";
					&PrintEvent("SERVER", "Ignoring bots is disabled", 1);
				}
				$g_servers{$s_addr}->{skill_mode} = $s_cfg{SkillMode};
				&PrintEvent("SERVER", "Using skill mode ".$s_cfg{SkillMode}, 1);
				
				if ($s_cfg{GameType} == 1) {
					$g_servers{$s_addr}->{game_type} = $s_cfg{GameType};
					&PrintEvent("SERVER", "Game type: Counter-Strike: Source - Deathmatch", 1);
				} else {
					$g_servers{$s_addr}->{game_type} = "0";
					&PrintEvent("SERVER", "Game type: Normal", 1);
				}
				
				$g_servers{$s_addr}->{mod} = $s_cfg{Mod};
				
				if ($s_cfg{Mod} ne "") {
					&PrintEvent("SERVER", "Using plugin ".$s_cfg{Mod}." for internal functions!", 1);
				}
				if ($s_cfg{ConnectAnnounce} == 1) {
					$g_servers{$s_addr}->{connect_announce} = $s_cfg{ConnectAnnounce};
					&PrintEvent("SERVER", "Connect Announce is enabled", 1);
				} else {
					$g_servers{$s_addr}->{connect_announce} = "0";
					&PrintEvent("SERVER", "Connect Announce is disabled", 1);
				}
				if ($s_cfg{UpdateHostname} == 1) {
					$g_servers{$s_addr}->{update_hostname} = $s_cfg{UpdateHostname};
					&PrintEvent("SERVER", "Auto-updating hostname is enabled", 1);
				} else {
					$g_servers{$s_addr}->{update_hostname} = "0";
					&PrintEvent("SERVER", "Auto-updating hostname is disabled", 1);
				}
				my $secret = $s_cfg{LogSecret};
				if ($secret ne "") {
					# S will already be stripped off. will be normal log with secret prepended
					my $match = sprintf("^%s%s", $secret, $g_logpattern);
					$g_servers{$s_addr}->{log_secret_match} = qr/$match/;
					&PrintEvent("SERVER", "Requiring logsecret of \"".$secret."\"", 1);
				} else {
					&PrintEvent("SERVER", "Not requiring logsecret", 1);
				}
				$g_servers{$s_addr}->get_game_mod_opts();
			}
		}
		
		if (!$g_servers{$s_addr}->{srv_players})
		{
			$g_servers{$s_addr}->{srv_players} = ();
			%g_players = ();
		}
		else
		{
			%g_players = %{$g_servers{$s_addr}->{srv_players}};
		}
		
		if (ProcessLogLine($s_output, $check_secret))
		{
			next;
		}
		
		if (!$g_stdin && defined($g_servers{$s_addr}) && time() > $g_servers{$s_addr}->{next_plyr_flush})
		{
			&PrintEvent("MYSQL", "Flushing player updates to database...",1);
			if ($g_servers{$s_addr}->{"srv_players"}) {
				while ( my($pl, $player) = each(%{$g_servers{$s_addr}->{"srv_players"}}) ) {
					if ($player->{needsupdate}) {
						$player->flushDB();
					}
				}
			}
			&PrintEvent("MYSQL", "Flushing player updates to database is complete.",1);
			
			$g_servers{$s_addr}->{next_plyr_flush} = time() + 15+int(rand(15));
		}
		
		if ($g_stdin == 0 && $g_servers{$s_addr})
		{
			my $s_lines = $g_servers{$s_addr}->{lines};
			# get ping from players
			if ($s_lines % 1000 == 0)
			{
				$g_servers{$s_addr}->update_players_pings();
			}
			
			# show stats
			if ($g_servers{$s_addr}->{show_stats} == 1
				&& $s_lines % 2500 == 40
				)
			{
				$g_servers{$s_addr}->dostats();
			}
			
			if ($s_lines > 500000)
			{
				$g_servers{$s_addr}->{lines} = 0;
			}
			else
			{
				$g_servers{$s_addr}->increment("lines");
			} 
		}
	}
	else
	{
		$s_addr = "";
	}

	while( my($server) = each(%g_servers))
	{
		if ($g_servers{$server}->{next_timeout} < $ev_unixtime)
		{
			#print "checking $ev_unixtime\n";
			# Clean up
			# look
			if ($g_servers{$server}->{srv_players})
			{
				my %players_temp=%{$g_servers{$server}->{srv_players}};
				while ( my($pl, $player) = each(%players_temp) )
				{
					my $timeout = 250; # 250;
					if ($g_mode == TRACKMODE_LAN())
					{
						$timeout = $timeout * 2;
					}

					my $userid = $player->{userid};
					my $uniqueid = $player->{uniqueid};
					if (($g_stdin || $player->{is_bot} == 0) && ($ev_unixtime - $player->{timestamp}) > $timeout )
					{
						# we delete any player who is inactive for over $timeout sec
						# - they probably disconnected silently somehow.
						# TODO: make timeout time configurable
						
						&PrintEvent(400, "Auto-disconnecting " . $player->getInfoString() ." for idling (" . ($ev_unixtime - $player->{timestamp}) . " sec) on server (".$server.")");
						RemovePlayer($server, $userid, $uniqueid);
					}
				}
			}
			$g_servers{$server}->{next_timeout} = $ev_unixtime + 30 + rand(30);
		}
		
		if (time() > $g_servers{$server}->{next_flush}
			&& $g_servers{$server}->{needsupdate}
		   )
		{
			$g_servers{$server}->flushDB();
			$g_servers{$server}->{needsupdate} = time() + 20;
		}
	}

	while ( my($pl, $player) = each(%g_preconnect) )
	{
		my $timeout = 600;
		if ( ($ev_unixtime - $player->{"timestamp"}) > $timeout )
		{
			&PrintEvent(401, "Clearing pre-connect entry with key ".$pl);
			delete($g_preconnect{$pl});
		}
	}
	
	if ($g_stdin == 0)
	{
		# Track the Trend
		if ($g_track_stats_trend > 0)
		{
			track_hlstats_trend();
		}  
		while (my($addr, $server) = each(%g_servers))
		{
			if ($server)
			{
				$server->track_server_load();
			}
		}
	
		if ($g_servers{$s_addr})
		{
			if ($g_servers{$s_addr}->{map} eq "" && ($timeout > 0 && ($timeout % 60) == 0))
			{
				$g_servers{$s_addr}->get_map();
			}
		}
		
		while( my($table) = each(%HLstats_Common::g_EventTables))
		{
			if (($g_EventTableData{$table}{lastflush} + 30) < time())
			{
				FlushEventTable($table);
			}
		}
	}  
	
	$c++;
	$c = 1 if ($c > 500000);
	$import_logs_count++ if ($g_stdin);
}

my $end_time = time();
if ($g_stdin)
{
	if ($import_logs_count > 0)
	{
		print "\n";
	}
	
	FlushAll(1);
	$g_db->DoFastQuery("UPDATE hlstats_Players SET last_event=UNIX_TIMESTAMP();");
	&PrintEvent("IMPORT", "Import of log file complete. Scanned ".$import_logs_count." lines in ".($end_time-$start_time)." seconds", 1, 1);
}

##
## Functions
##

#
# LookupPlayer
#
# Get player object ref from given server address, userid, and uniqueid
#

sub LookupPlayer
{
	my ($saddr, $id, $uniqueid) = @_;
	if (defined($g_servers{$saddr}->{srv_players}->{"$id/$uniqueid"}))
	{
		return $g_servers{$saddr}->{srv_players}->{"$id/$uniqueid"};
	}
	return;
}


#
# LookupPlayerByUniqueId
#
# Get player object ref from current server and given uniqueid
#

sub LookupPlayerByUniqueId
{
	my ($uniqueid) = @_;
	
	while ( my ($key, $player) = each(%g_players) )
	{
		if ($player->{uniqueid} eq $uniqueid)
		{
			return $player;
		}
	}
	
	return;
}


#
# RemovePlayer
#
# Safely remove player corresponding with given server address, userid, and uniqueid
#

sub RemovePlayer
{
	my ($saddr, $id, $uniqueid, $dontUpdateCount) = @_;
	my $deleteplayer = 0;
	if(defined($g_servers{$saddr}->{srv_players}->{"$id/$uniqueid"}))
	{
		$deleteplayer = 1;
	}
	else
	{
		&PrintEvent("400", "Bad attempted delete ($saddr) ($id/$uniqueid)");
	}
	
	if ($deleteplayer == 1)
	{
		$g_servers{$saddr}->{srv_players}->{"$id/$uniqueid"}->playerCleanup();
		delete($g_servers{$saddr}->{srv_players}->{"$id/$uniqueid"});
		if (!$dontUpdateCount)  # double negative, i know...
		{
			$g_servers{$saddr}->updatePlayerCount();
		}	
	}
	
	return;
}


#
# ProcessLogLine
#
# Parses log line and sends to necessary event handler
# A non-zero, defined return will cause to daemon to immediately continue to the next log line
#

sub ProcessLogLine
{
	# Get the datestamp (or complain)
	#if ($s_output =~ s/^.*L (\d\d)\/(\d\d)\/(\d{4}) - (\d\d):(\d\d):(\d\d):\s*//)
	
	#$is_streamed = 0;
	#$test_for_date = 0;
	#$is_streamed = ($s_output !~ m/^L\s*/);
	
	#if ( !$is_streamed ) {
	# $test_for_date = ($s_output =~ s/^L (\d\d)\/(\d\d)\/(\d{4}) - (\d\d):(\d\d):(\d\d):\s*//);
	#} else {
	# $test_for_date = ($s_output =~ s/^\S*L (\d\d)\/(\d\d)\/(\d{4}) - (\d\d):(\d\d):(\d\d):\s*//);
	#}
	
	#if ($test_for_date)
	
	# EXPLOIT FIX
	
	my ($logline, $check_secret) = @_;

	if (($check_secret && $logline =~ $g_servers{$s_addr}->{log_secret_match}) || (!$check_secret && $logline =~ $g_logmatch))
	{
		my $ev_month = $1;
		my $ev_day   = $2;
		my $ev_year  = $3;
		my $ev_hour  = $4;
		my $ev_min   = $5;
		my $ev_sec   = $6;
		my $ev_time  = "$ev_hour:$ev_min:$ev_sec";
		$ev_remotetime  = timelocal($ev_sec,$ev_min,$ev_hour,$ev_day,$ev_month-1,$ev_year);
		
		if ($g_timestamp)
		{
			$ev_timestamp = "$ev_year-$ev_month-$ev_day $ev_time";
			$ev_unixtime  = $ev_remotetime;
		}
		
		$logline = $7;
	}
	else
	{
		PrintEvent(998, "MALFORMED DATA: " . $logline);
		return 1;
	}
	
	PrintDebug($s_addr.": \"".$logline."\"", 4);
	
	
	if ($g_stdin == 0 && $g_servers{$s_addr}->{last_event} > 0 && ($ev_unixtime - $g_servers{$s_addr}->{last_event}) > 299)
	{
		$g_servers{$s_addr}->{map} = "";
		$g_servers{$s_addr}->get_map();
	}
	
	$g_servers{$s_addr}->{last_event} = $ev_unixtime;

	# Now we parse the events.
	
	my $ev_type   = 0;
	my $ev_status = "";
	my $ev_team   = "";
	my $ev_player = undef;
	my $ev_verb   = undef;
	my $ev_obj_a  = undef;
	my $ev_obj_b  = undef;
	my $ev_obj_c  = undef;
	my $ev_obj_d  = undef;
	my $ev_properties = undef;
	my %ev_properties_hash = ();
	my %ev_player = ();

	# pvkii parrot log lines also fit the death line parsing
	if ($g_servers{$s_addr}->{play_game} == PVKII()
		&& $logline =~ /^
			"(.+?(?:<[^>]*>){3})"		# player string
			\s[a-z]{6}\s				# 'killed'
			"npc_parrot<.+?>"			# parrot string
			\s[a-z]{5}\s[a-z]{2}\s		# 'owned by'
			"(.+?(?:<[^>]*>){3})"		# owner string
			\s[a-z]{4}\s				# 'with'
			"([^"]*)"				#weapon
			(.*)					#properties
			/x)
	{
		$ev_player = $1; # player
		$ev_obj_b  = $2; # victim
		$ev_obj_c  = $3; # weapon
		$ev_properties = $4;
		%ev_properties_hash = getProperties($ev_properties);
		
		my $playerinfo = getPlayerInfo($ev_player, 1);
		my $victiminfo = getPlayerInfo($ev_obj_b, 1);
		$ev_type = 10;
		
		if ($playerinfo)
		{
			if ($victiminfo)
			{
				$ev_status = HLstats_EventMgr::EvPlayerPlayerAction(
					$playerinfo->{userid},
					$playerinfo->{uniqueid},
					$victiminfo->{userid},
					$victiminfo->{uniqueid},
					"killed_parrot",
					undef,
					undef,
					undef,
					undef,
					undef,
					undef,
					\%ev_properties_hash
				);
			}
			
			$ev_type = 11;
			
			$ev_status = HLstats_EventMgr::EvPlayerAction(
				$playerinfo->{userid},
				$playerinfo->{uniqueid},
				"killed_parrot",
				undef,
				undef,
				undef,
				\%ev_properties_hash
			);
		}
	}
	elsif ($logline =~ /^
		(?:\(DEATH\))?		# l4d prefix
		"(.+?(?:<.+?>)*?
		(?:<setpos_exact\s(-?\d+?\.\d\d)\s(-?\d+?\.\d\d)\s(-?\d+?\.\d\d);[^"]*)?
		)"						# player string with or without l4d-style location coords
		\skilled\s			# verb (ex. attacked, killed, triggered)
		"(.+?(?:<.+?>)*?
		(?:<setpos_exact\s(-?\d+?\.\d\d)\s(-?\d+?\.\d\d)\s(-?\d+?\.\d\d);[^"]*)?
		)"						# player string as above or action name
		\swith\s				# (ex. with, against)
		"([^"]*)"
		(.*)					#properties
		$/x)
	{

		# Prototype: "player" verb "obj_a" ?... "obj_b"[properties]
		# Matches:
		#  8. Kills
		
		$ev_player = $1;
		my $ev_l4dXcoord = $2; # attacker/player coords (L4D)
		my $ev_l4dYcoord = $3;
		my $ev_l4dZcoord = $4;
		$ev_obj_a  = $5; # victim
		my $ev_l4dXcoordKV = $6; # kill victim coords (L4D)
		my $ev_l4dYcoordKV = $7;
		my $ev_l4dZcoordKV = $8;
		$ev_obj_b  = $9; # weapon
		$ev_properties = $10;
		%ev_properties_hash = getProperties($ev_properties);
		
		my $killerinfo = getPlayerInfo($ev_player, 1);
		my $victiminfo = getPlayerInfo($ev_obj_a, 1);
		$ev_type = 8;
		
		my $headshot = 0;
		if ($ev_properties =~ m/headshot/)
		{
			$headshot = 1;
		}
			
		if ($killerinfo && $victiminfo)
		{
			my $killerId = $killerinfo->{userid};
			my $killerUniqueId = $killerinfo->{uniqueid};
			my $killer = LookupPlayer($s_addr, $killerId, $killerUniqueId);
			if ($killer && $killerinfo->{team} ne "" && $killer->{team} ne $killerinfo->{team})
			{
				$killer->set("team", $killerinfo->{team});
				$killer->updateDB();
				$killer->updateTimestamp();
			}
			
			my $victimId       = $victiminfo->{userid};
			my $victimUniqueId = $victiminfo->{uniqueid};
			my $victim         = LookupPlayer($s_addr, $victimId, $victimUniqueId);
			if (($victim) && ($victiminfo->{team} ne "") && ($victim->{team} ne $victiminfo->{team}) )
			{
				$victim->set("team", $victiminfo->{team});
				$victim->updateDB();
				$victim->updateTimestamp();
			}
			
			$ev_status = HLstats_EventMgr::EvFrag(
				$killerinfo->{userid},
				$killerinfo->{uniqueid},
				$victiminfo->{userid},
				$victiminfo->{uniqueid},
				$ev_obj_b,
				$headshot,
				$ev_l4dXcoord,
				$ev_l4dYcoord,
				$ev_l4dZcoord,
				$ev_l4dXcoordKV,
				$ev_l4dYcoordKV,
				$ev_l4dZcoordKV,
				\%ev_properties_hash
			);
		}
	}
	elsif ($g_servers{$s_addr}->{play_game} == L4D() && $logline =~ /^
		\(INCAP\)		# l4d prefix, such as (DEATH) or (INCAP)
		"(.+?(?:<.+?>)*?
		<setpos_exact\s(-?\d+?\.\d\d)\s(-?\d+?\.\d\d)\s(-?\d+?\.\d\d);[^"]*
		)"						# player string with or without l4d-style location coords
		\swas\sincapped\sby\s			# verb (ex. attacked, killed, triggered)
		"(.+?(?:<.+?>)*?
		<setpos_exact\s(-?\d+?\.\d\d)\s(-?\d+?\.\d\d)\s(-?\d+?\.\d\d);[^"]*
		)"						# player string as above or action name
		\swith\s				# (ex. with, against)
		"([^"]*)"					# weapon name
		(.*)					#properties
		/x)
	{
		#  800. L4D Incapacitation
		
		$ev_player = $1;
		my $ev_l4dXcoord = $2; # attacker/player coords
		my $ev_l4dYcoord = $3;
		my $ev_l4dZcoord = $4;
		$ev_obj_a  = $5; # victim
		my $ev_l4dXcoordKV = $6; # kill victim coords
		my $ev_l4dYcoordKV = $7;
		my $ev_l4dZcoordKV = $8;
		$ev_obj_b  = $9; # weapon
		$ev_properties = $10;
		%ev_properties_hash = getProperties($ev_properties);
		
		# reverse killer/victim (x was incapped by y = y killed x)
		my $killerinfo = getPlayerInfo($ev_obj_a, 1);
		my $victiminfo = getPlayerInfo($ev_player, 1);
		
		if ($victiminfo->{team} eq "Infected")
		{
			$victiminfo = undef;
		}
		
		$ev_type = 800;
		
		my $headshot = 0;
		if ($ev_properties =~ m/headshot/)
		{
			$headshot = 1;
		}
			
		if ($killerinfo && $victiminfo)
		{
			my $killerId = $killerinfo->{userid};
			my $killerUniqueId = $killerinfo->{uniqueid};
			my $killer = LookupPlayer($s_addr, $killerId, $killerUniqueId);
			if ($killer && $killerinfo->{team} ne "" && $killer->{team} ne $killerinfo->{team})
			{
				$killer->set("team", $killerinfo->{team});
				$killer->updateDB();
				$killer->updateTimestamp();
			}
			
			my $victimId       = $victiminfo->{userid};
			my $victimUniqueId = $victiminfo->{uniqueid};
			my $victim         = LookupPlayer($s_addr, $victimId, $victimUniqueId);
			if (($victim) && ($victiminfo->{team} ne "") && ($victim->{team} ne $victiminfo->{team}) )
			{
				$victim->set("team", $victiminfo->{team});
				$victim->updateDB();
				$victim->updateTimestamp();
			}
			
			$ev_status = HLstats_EventMgr::EvFrag(
				$killerinfo->{userid},
				$killerinfo->{uniqueid},
				$victiminfo->{userid},
				$victiminfo->{uniqueid},
				$ev_obj_b,
				$headshot,
				$ev_l4dXcoord,
				$ev_l4dYcoord,
				$ev_l4dZcoord,
				$ev_l4dXcoordKV,
				$ev_l4dYcoordKV,
				$ev_l4dZcoordKV,
				\%ev_properties_hash
			);
		}
	}
	elsif ($g_servers{$s_addr}->{play_game} == L4D() && $logline =~ /^
		   \(TONGUE\)\sTongue\sgrab\sstarting\.
		   \s+
		   Smoker:"(.+?(?:<.+?>)*?(?:|<setpos_exact\s((?:|-)\d+?\.\d\d)\s((?:|-)\d+?\.\d\d)\s((?:|-)\d+?\.\d\d);.*?))"\.
		   \s+
		   Victim:"(.+?(?:<.+?>)*?(?:|<setpos_exact\s((?:|-)\d+?\.\d\d)\s((?:|-)\d+?\.\d\d)\s((?:|-)\d+?\.\d\d);.*?))"
		   .*$/x)
	{
		# Prototype: (TONGUE) Tongue grab starting.  Smoker:"player". Victim:"victim".
		# Matches:
		# 11. Player Action
		
		$ev_player        = $1;
		my $ev_l4dXcoord  = $2;
		my $ev_l4dYcoord  = $3;
		my $ev_l4dZcoord  = $4;
		$ev_obj_a         = $5;
		my $ev_l4dXcoordV = $6;
		my $ev_l4dYcoordV = $7;
		my $ev_l4dZcoordV = $8;
		
		my $playerinfo = getPlayerInfo($ev_player, 1);
		my $victiminfo = getPlayerInfo($ev_obj_a, 1);

		$ev_type = 11;
			
		if ($playerinfo)
		{
			$ev_status = HLstats_EventMgr::EvPlayerAction(
				$playerinfo->{userid},
				$playerinfo->{uniqueid},
				"tongue_grab"
			);
			if ($victiminfo)
			{
				$ev_status = HLstats_EventMgr::EvPlayerPlayerAction(
					$playerinfo->{userid},
					$playerinfo->{uniqueid},
					$victiminfo->{userid},
					$victiminfo->{uniqueid},
					"tongue_grab",
					$ev_l4dXcoord,
					$ev_l4dYcoord,
					$ev_l4dZcoord,
					$ev_l4dXcoordV,
					$ev_l4dYcoordV,
					$ev_l4dZcoordV
				);
			}
		}
	}
	elsif ($logline =~ /^
			"(.+?(?:<.+?>)*?
			)"						# player string
			\s(triggered(?:\sa)?)\s			# verb (ex. attacked, killed, triggered)
			"(.+?(?:<.+?>)*?
			)"						# player string as above or action name
			\s[a-zA-Z]+\s				# (ex. with, against)
			"(.+?(?:<.+?>)*?
			)"						# player string as above or weapon name
			(?:\s[a-zA-Z]+\s"(.+?)")?	# weapon name on plyrplyr actions
			(.*)					#properties
			/x)
	{
		# 10. Player-Player Actions
		
		# no l4d/2 actions are logged with the locations (in fact, very few are logged period) so the l4d/2 location parsing can be skipped
		
		$ev_player = $1;
		$ev_verb   = $2; # triggered or triggered a
		$ev_obj_a  = $3; # action
		$ev_obj_b  = $4; # victim
		$ev_obj_c  = $5; # weapon (optional)
		$ev_properties = $6;
		%ev_properties_hash = getProperties($ev_properties);
		
		if ($ev_verb eq "triggered")  # it's either 'triggered' or 'triggered a'
		{
			my $playerinfo = getPlayerInfo($ev_player, 1);
			my $victiminfo = getPlayerInfo($ev_obj_b, 1);
			$ev_type = 10;

			if ($playerinfo)
			{
				if ($victiminfo)
				{
					$ev_status = HLstats_EventMgr::EvPlayerPlayerAction(
						$playerinfo->{userid},
						$playerinfo->{uniqueid},
						$victiminfo->{userid},
						$victiminfo->{uniqueid},
						$ev_obj_a,
						undef,
						undef,
						undef,
						undef,
						undef,
						undef,
						\%ev_properties_hash
					);
				}

				$ev_type = 11;
				
				$ev_status = HLstats_EventMgr::EvPlayerAction(
					$playerinfo->{userid},
					$playerinfo->{uniqueid},
					$ev_obj_a,
					undef,
					undef,
					undef,
					\%ev_properties_hash
				);
			}
		}
		else
		{
			my $playerinfo = getPlayerInfo($ev_player, 1);
			$ev_type = 11;
			
			if ($playerinfo)
			{
				$ev_status = HLstats_EventMgr::EvPlayerAction(
					$playerinfo->{userid},
					$playerinfo->{uniqueid},
					$ev_obj_a,
					undef,
					undef,
					undef,
					\%ev_properties_hash
				);
			}
		}
	}
	elsif ($logline =~ /^(?:\[STATSME\] )?"(.+?(?:<.+?>)*)" triggered "(weaponstats\d{0,1})"(.*)$/)
	{
		# Prototype: [STATSME] "player" triggered "weaponstats?"[properties]
		# Matches:
		# 501. Statsme weaponstats
		# 502. Statsme weaponstats2

		$ev_player = $1;
		$ev_verb   = $2; # weaponstats; weaponstats2
		$ev_properties = $3;
		%ev_properties_hash = getProperties($ev_properties);

		if ($ev_verb eq /^weaponstats/)
		{
			$ev_type = 501;
			my $playerinfo = getPlayerInfo($ev_player, 0);
			
			if ($playerinfo)
			{
				my $playerId = $playerinfo->{"userid"};
				my $playerUniqueId = $playerinfo->{"uniqueid"};
				my $ingame = 0;
				
				$ingame = 1 if (LookupPlayer($s_addr, $playerId, $playerUniqueId));
				
				if (!$ingame)
				{
					getPlayerInfo($ev_player, 1);
				}
				
				$ev_status = HLstats_EventMgr::EvStatsme(
					$playerId,
					$playerUniqueId,
					$ev_properties_hash{weapon},
					$ev_properties_hash{shots},
					$ev_properties_hash{hits},
					$ev_properties_hash{headshots},
					$ev_properties_hash{damage},
					$ev_properties_hash{kills},
					$ev_properties_hash{deaths}
				);

				if (!$ingame)
				{
					HLstats_EventMgr::EvDisconnect(
						$playerId,
						$playerUniqueId,
						""
					);
				}
			}
		}
		elsif ($ev_verb eq "weaponstats2")
		{
			$ev_type = 502;
			my $playerinfo = getPlayerInfo($ev_player, 0);
			
			if ($playerinfo)
			{
				my $playerId = $playerinfo->{userid};
				my $playerUniqueId = $playerinfo->{uniqueid};
				my $ingame = 0;
				
				$ingame = 1 if (LookupPlayer($s_addr, $playerId, $playerUniqueId));
				
				if (!$ingame)
				{
					getPlayerInfo($ev_player, 1);
				}
				
				$ev_status = HLstats_EventMgr::EvStatsme2(
					$playerId,
					$playerUniqueId,
					$ev_properties_hash{weapon},
					$ev_properties_hash{head},
					$ev_properties_hash{chest},
					$ev_properties_hash{stomach},
					$ev_properties_hash{leftarm},
					$ev_properties_hash{rightarm},
					$ev_properties_hash{leftleg},
					$ev_properties_hash{rightleg}
				);
				
				if (!$ingame)
				{
					HLstats_EventMgr::EvDisconnect(
						$playerId,
						$playerUniqueId,
						""
					);
				}
			}
		}
	}
	elsif ($logline =~ /^(?:\[STATSME\] )?"(.+?(?:<.+?>)*)" triggered "(latency|time)"(.*)$/)
	{
		# Prototype: [STATSME] "player" triggered "latency|time"[properties]
		# Matches:
		# 503. Statsme latency
		# 504. Statsme time
		
		$ev_player     = $1;
		$ev_verb       = $2; # latency; time
		$ev_properties = $3;
		%ev_properties_hash = getProperties($ev_properties);
		
		if ($ev_verb eq "time")
		{
			$ev_type = 504;
			my $playerinfo = getPlayerInfo($ev_player, 0);
			
			if ($playerinfo)
			{
				my ($min, $sec) = split(/:/, $ev_properties_hash{time});
				my $hour = sprintf("%d", $min / 60);
				
				if ($hour)
				{
					$min = $min % 60;
				}
				
				$ev_status = HLstats_EventMgr::EvStatsme_Time(
					$playerinfo->{userid},
					$playerinfo->{uniqueid},
					"$hour:$min:$sec"
				);
			}
		}
		else  # latency
		{
			$ev_type = 503;
			my $playerinfo = getPlayerInfo($ev_player, 0);
			
			if ($playerinfo)
			{
				$ev_status = HLstats_EventMgr::EvStatsme_Latency(
					$playerinfo->{userid},
					$playerinfo->{uniqueid},
					$ev_properties_hash{ping}
				);
			}
		}
	}
	elsif ($logline =~ /^"(.+?(?:<.+?>)*?)" ([a-zA-Z,_\s]+) "(.+?)"(.*)$/)
	{
		# Prototype: "player" verb "obj_a"[properties]
		# Matches:
		#  1. Connection
		#  4. Suicides
		#  5. Team Selection
		#  6. Role Selection
		#  7. Change Name
		# 11. Player Objectives/Actions
		# 14. a) Chat; b) Team Chat
		
		$ev_player       = $1;
		$ev_verb         = $2;
		$ev_obj_a        = $3;
		$ev_properties   = $4;
		%ev_properties_hash = getProperties($ev_properties);
		
		if ($ev_verb eq "connected, address")
		{
			my $ipAddr = $ev_obj_a;
			my $playerinfo;
			
			if ($ipAddr =~ /([\d\.]+):(\d+)/)
			{
				$ipAddr = $1;
			}
			
			$playerinfo = getPlayerInfo($ev_player, 1, $ipAddr);
			
			$ev_type = 1;
			
			if ($playerinfo)
			{
				if ($playerinfo->{uniqueid} =~ /UNKNOWN/
					|| $playerinfo->{uniqueid} =~ /PENDING/
					|| $playerinfo->{uniqueid} =~ /VALVE_ID_LAN/
					)
				{
					$ev_status = "(DELAYING CONNECTION): $logline";

					if ($g_mode != TRACKMODE_LAN())
					{
						my $p_name   = $playerinfo->{name};
						my $p_userid = $playerinfo->{userid};
						PrintEvent("SERVER", "LATE CONNECT [$p_name/$p_userid] - STEAM_ID_PENDING");
						$g_preconnect{"$s_addr/$p_userid/$p_name"} = {
							ipaddress  => $ipAddr,
							name       => $p_name,
							server     => $s_addr,
							timestamp  => time()
						};
					}   
				}
				else
				{
					$ev_status = HLstats_EventMgr::EvConnect(
						$playerinfo->{userid},
						$playerinfo->{uniqueid},
						$ipAddr
					);
				}
			}
		}
		elsif ($ev_verb eq "committed suicide with")
		{
			my $playerinfo = getPlayerInfo($ev_player, 1);
			
			$ev_type = 4;
			
			if ($playerinfo)
			{
				$ev_status = HLstats_EventMgr::EvSuicide(
					$playerinfo->{userid},
					$playerinfo->{uniqueid},
					$ev_obj_a,
					\%ev_properties_hash
				);
			}
		}
		elsif ($ev_verb eq "joined team")
		{
			my $playerinfo = getPlayerInfo($ev_player, 1);
			
			$ev_type = 5;
			
			if ($playerinfo)
			{
				$ev_status = HLstats_EventMgr::EvTeamSelection(
					$playerinfo->{userid},
					$playerinfo->{uniqueid},
					$ev_obj_a
				);
			}
		}
		elsif ($ev_verb eq "changed role to")
		{
			my $playerinfo = getPlayerInfo($ev_player, 1);
			
			$ev_type = 6;
			
			if ($playerinfo)
			{
				$ev_status = HLstats_EventMgr::EvRoleSelection(
					$playerinfo->{userid},
					$playerinfo->{uniqueid},
					$ev_obj_a
				);
			}
		}
		elsif ($ev_verb eq "changed name to")
		{
			my $playerinfo = getPlayerInfo($ev_player, 1);
			
			$ev_type = 7;
			
			if ($playerinfo)
			{
				$ev_status = HLstats_EventMgr::EvChangeName(
					$playerinfo->{userid},
					$playerinfo->{uniqueid},
					$ev_obj_a
				);
			}
		}
		elsif ($ev_verb eq "triggered")
		{
			# in cs:s players dropp the bomb if they are the only ts
			# and disconnect...the dropp the bomb after they disconnected :/
			my $playerinfo;
			if ($ev_obj_a eq "Dropped_The_Bomb")
			{
				$playerinfo = getPlayerInfo($ev_player, 0);
			}
			else
			{
				$playerinfo = getPlayerInfo($ev_player, 1);
			}
			
			if ($playerinfo)
			{
				if ($ev_obj_a eq "player_changeclass" && defined($ev_properties_hash{newclass})) {
					
					$ev_type = 6;
					
					$ev_status = HLstats_EventMgr::EvRoleSelection(
						$playerinfo->{userid},
						$playerinfo->{uniqueid},
						$ev_properties_hash{newclass}
					);
				}
				else
				{
					$ev_type = 11;
					
					if ($g_servers{$s_addr}->{play_game} == TFC())
					{
						if ($ev_obj_a eq "Sentry_Destroyed")
						{
							$ev_obj_a = "Sentry_Dismantle";
						}
						elsif ($ev_obj_a eq "Dispenser_Destroyed")
						{
							$ev_obj_a = "Dispenser_Dismantle";
						}
						elsif ($ev_obj_a eq "Teleporter_Entrance_Destroyed")
						{
							$ev_obj_a = "Teleporter_Entrance_Dismantle"
						}
						elsif ($ev_obj_a eq "Teleporter_Exit_Destroyed")
						{
							$ev_obj_a = "Teleporter_Exit_Dismantle"
						}
					}
					
					$ev_status = HLstats_EventMgr::EvPlayerAction(
						$playerinfo->{userid},
						$playerinfo->{uniqueid},
						$ev_obj_a,
						undef,
						undef,
						undef,
						\%ev_properties_hash
					);
				}
			}
		}
		elsif ($ev_verb eq "triggered a")
		{
			my $playerinfo = getPlayerInfo($ev_player, 1);
			
			$ev_type = 11;
			
			if ($playerinfo)
			{
				$ev_status = HLstats_EventMgr::EvPlayerAction(
					$playerinfo->{userid},
					$playerinfo->{uniqueid},
					$ev_obj_a,
					undef,
					undef,
					undef,
					\%ev_properties_hash
				);
			}
		}
		elsif ($ev_verb eq "say")
		{
			my $playerinfo = getPlayerInfo($ev_player, 1);
			
			$ev_type = 14;
			
			if ($playerinfo)
			{
				$ev_status = HLstats_EventMgr::EvChat(
					"say",
					$playerinfo->{userid},
					$playerinfo->{uniqueid},
					$ev_obj_a
				);
			}
		}
		elsif ($ev_verb eq "say_team")
		{
			my $playerinfo = getPlayerInfo($ev_player, 1);
			
			$ev_type = 14;
			
			if ($playerinfo)
			{
				$ev_status = HLstats_EventMgr::EvChat(
					"say_team",
					$playerinfo->{userid},
					$playerinfo->{uniqueid},
					$ev_obj_a
				);
			}
		}
	}
	elsif ($logline =~ /^(?:Kick: )?"(.+?(?:<.+?>)*)" ([^\(]+)(.*)$/)
	{
		# Prototype: "player" verb[properties]
		# Matches:
		#  2. Enter Game
		#  3. Disconnection
		
		$ev_player     = $1;
		$ev_verb       = $2;
		$ev_properties = $3;
		%ev_properties_hash = getProperties($ev_properties);
		
		if ($ev_verb eq "entered the game")
		{
			my $playerinfo = getPlayerInfo($ev_player, 1);
			
			if ($playerinfo)
			{
				$ev_type = 2;
				$ev_status = HLstats_EventMgr::EvEnterGame(
					$playerinfo->{userid},
					$playerinfo->{uniqueid},
					$ev_obj_a
				);
			}
		}
		elsif ($ev_verb eq "disconnected" || $ev_verb eq "was kicked")
		{
			my $playerinfo = getPlayerInfo($ev_player, 0);
			
			if ($playerinfo)
			{
				$ev_type = 3;
				
				my $userid   = $playerinfo->{userid};
				my $uniqueid = $playerinfo->{uniqueid};
				
				$ev_status = HLstats_EventMgr::EvDisconnect(
					$playerinfo->{userid},
					$playerinfo->{uniqueid},
					\%ev_properties_hash
				);
			}
		}
		elsif ($ev_verb eq "STEAM USERID validated" || $ev_verb eq "VALVE USERID validated")
		{
			my $playerinfo = getPlayerInfo($ev_player, 0);
			
			if ($playerinfo)
			{
				$ev_type = 1;
			}
		}
	}
	elsif ($logline =~ /^Team "(.+?)" ([^"\(]+) "([^"]+)"(.*)$/)
	{
		# Prototype: Team "team" verb "obj_a"[properties]
		# Matches:
		# 12. Team Objectives/Actions
		# 1200. Team Objective With Players involved
		# 15. Team Alliances
		
		$ev_team   = $1;
		$ev_verb   = $2;
		$ev_obj_a  = $3;
		$ev_properties = $4;
		%ev_properties_hash = getProperties($ev_properties);
		
		if ($ev_obj_a eq "pointcaptured")
		{
			my $numcappers = $ev_properties_hash{numcappers};
			if ($g_debug > 1)
			{
				print "NumCappers = ".$numcappers."\n";
			}
			
			foreach (my $i = 1; $i <= $numcappers; $i++)
			{
				# reward each player involved in capturing
				my $player = $ev_properties_hash{"player$i"};
				if ($g_debug > 1)
				{
					print "$i -> $player\n";
				}
				
				#$position = $ev_properties_hash{"position".$i};
				my $playerinfo = getPlayerInfo($player, 1);
				if ($playerinfo)
				{
					$ev_status = HLstats_EventMgr::EvPlayerAction(
						$playerinfo->{userid},
						$playerinfo->{uniqueid},
						$ev_obj_a,
						"",
						"",
						"",
						\%ev_properties_hash
					);
				}
			}
		}
		elsif ($ev_obj_a eq "captured_loc")
		{
		#	$flag_name = $ev_properties_hash{flagname};
			my $player_a  = $ev_properties_hash{player_a};
			my $player_b  = $ev_properties_hash{player_b};
		  
			my $playerinfo_a = getPlayerInfo($player_a, 1);
			if ($playerinfo_a)
			{
				$ev_status = HLstats_EventMgr::EvPlayerAction(
					$playerinfo_a->{userid},
					$playerinfo_a->{uniqueid},
					$ev_obj_a,
					"",
					"",
					"",
					\%ev_properties_hash
				);
			}

			my $playerinfo_b = getPlayerInfo($player_b, 1);
			if ($playerinfo_b)
			{
				$ev_status = HLstats_EventMgr::EvPlayerAction(
					$playerinfo_b->{userid},
					$playerinfo_b->{uniqueid},
					$ev_obj_a,
					"",
					"",
					"",
					\%ev_properties_hash
				);
			}
			
			$ev_status = HLstats_EventMgr::EvTeamAction(
				$ev_team,
				$ev_obj_a,
				\%ev_properties_hash
			);
		}  
	}
	elsif ($logline =~ /^(Rcon|Bad Rcon): "rcon [^"]+"([^"]+)"\s+(.+)" from "([0-9\.]+?):(\d+?)".*$/)
	{
		# Prototype: verb: "rcon ?..."obj_a" obj_b" from "obj_c"[properties]
		# Matches:
		# 20. HL1 a) Rcon; b) Bad Rcon
		
		$ev_verb   = $1;
		$ev_obj_a  = $2; # password
		$ev_obj_b  = $3; # command
		$ev_obj_c  = $4; # ip
		$ev_obj_d  = $5; # port
		
		if ($g_rcon_ignoreself == 0 || $ev_obj_c ne $s_ip)
		{
			$ev_obj_b = substr($ev_obj_b, 0, 255); #db field will only hold 255chars of this and i've seen it longer
			if ($ev_verb eq "Rcon")
			{
				$ev_type = 20;
				$ev_status = HLstats_EventMgr::EvRcon(
					"OK",
					$ev_obj_b,
					"",
					$ev_obj_c
				);
			}
			elsif ($ev_verb eq "Bad Rcon")
			{
				$ev_type = 20;
				$ev_status = HLstats_EventMgr::EvRcon(
					"BAD",
					$ev_obj_b,
					$ev_obj_a,
					$ev_obj_c
				);
			}
		}
		else
		{
			$ev_status = "(IGNORED) Rcon from \"$ev_obj_a:$ev_obj_b\": \"$ev_obj_c\"";
		}
	}
	elsif ($logline =~ /^rcon from "(.+?):(.+?)": (?:command "(.*)".*|(Bad) Password)$/)
	{
		# Prototype: verb: "rcon ?..."obj_a" obj_b" from "obj_c"[properties]
		# Matches:
		# 20. a) Rcon;
		
		$ev_obj_a  = $1; # ip
		$ev_obj_b  = $2; # port
		$ev_obj_c  = $3; # command
		my $ev_isbad  = $4; # if bad, "Bad"
		
		if ($g_rcon_ignoreself == 0 || $ev_obj_a ne $s_ip)
		{
			if (!$ev_isbad || $ev_isbad ne "Bad")
			{
				$ev_type = 20;
			
				my @cmds = split(/;/,$ev_obj_c);
				foreach(@cmds)
				{
					$ev_status = HLstats_EventMgr::EvRcon(
						"OK",
						substr($_, 0, 255), #db field will only hold 255chars of this and i've seen it longer
						"",
						$ev_obj_a
					);
				}
			}
			else
			{
				$ev_type = 20;
				$ev_status = HLstats_EventMgr::EvRcon(
					"BAD",
					"",
					"",
					$ev_obj_a
				);
			}
		}
		else
		{
			$ev_status = "(IGNORED) Rcon from \"$ev_obj_a:$ev_obj_b\": \"$ev_obj_c\"";
		}
	}
	elsif ($logline =~ /^\[(.+)\.(smx|amxx)\]\s*(.+)$/i)
	{
		# Prototype: Cmd:[SM] obj_a
		# Matches:
		# Admin Mod messages
		
		my $ev_plugin = $1;
		my $ev_adminmod = $2;
		$ev_obj_a  = $3;
		$ev_type = 500;
		$ev_status = HLstats_EventMgr::EvAdmin(
			(($ev_adminmod eq "smx")?"Sourcemod":"AMXX")." ($ev_plugin)",
			substr($ev_obj_a, 0, 255)
		);
	}
	elsif ($logline =~ /^([^"\(]+) "([^"]+)"(.*)$/)
	{
		# Prototype: verb "obj_a"[properties]
		# Matches:
		# 13. World Objectives/Actions
		# 19. a) Loading map; b) Started map
		# 21. Server Name
		
		$ev_verb   = $1;
		$ev_obj_a  = $2;
		$ev_properties = $3;
		%ev_properties_hash = getProperties($ev_properties);
		
		if (like($ev_verb, "World triggered"))
		{
			$ev_type = 13;
			if ($ev_obj_a eq "killlocation")
			{
				$ev_status = HLstats_EventMgr::EvKillLoc(
					\%ev_properties_hash
				);
			}
			else
			{
				$ev_status = HLstats_EventMgr::EvWorldAction(
					$ev_obj_a
				);
				if ($ev_obj_a eq "Round_Win" || $ev_obj_a eq "Mini_Round_Win")
				{
					$ev_team = $ev_properties_hash{winner};
					$ev_status = HLstats_EventMgr::EvTeamAction(
					$ev_team,
					$ev_obj_a
					);
				}
			}
		}
		elsif ($ev_verb eq "Loading map")
		{
			$ev_type = 19;
			$ev_status = HLstats_EventMgr::EvChangeMap(
				"loading",
				$ev_obj_a
			);
		}
		elsif ($ev_verb eq "Started map")
		{
			$ev_type = 19;
			$ev_status = HLstats_EventMgr::EvChangeMap(
				"started",
				$ev_obj_a
			);
		}
	}
	elsif ($logline =~ /^\[MANI_ADMIN_PLUGIN\]\s*(.+)$/)
	{
		# Prototype: [MANI_ADMIN_PLUGIN] obj_a
		# Matches:
		# Mani-Admin-Plugin messages
		
		$ev_obj_a  = $1;
		$ev_type = 500;
		$ev_status = HLstats_EventMgr::EvAdmin(
			"Mani Admin Plugin",
			substr($ev_obj_a, 0, 255)
		);
	}
	elsif ($logline =~ /^\[BeetlesMod\]\s*(.+)$/)
	{
		# Prototype: Cmd:[BeetlesMod] obj_a
		# Matches:
		# Beetles Mod messages
		
		$ev_obj_a  = $1;
		$ev_type = 500;
		$ev_status = HLstats_EventMgr::EvAdmin(
			"Beetles Mod",
			substr($ev_obj_a, 0, 255)
		);
	}
	elsif ($logline =~ /^\[ADMIN:(.+)\] ADMIN Command: \1 used command (.+)$/)
	{
		# Prototype: [ADMIN] obj_a
		# Matches:
		# Admin Mod messages
		
		$ev_obj_a  = $1;
		$ev_obj_b  = $2;
		$ev_type = 500;
		$ev_status = HLstats_EventMgr::EvAdmin(
			"Admin Mod",
			substr($ev_obj_b, 0, 255),
			$ev_obj_a
		);
	}
	elsif ($g_mode == TRACKMODE_NORMAL() && $g_servers{$s_addr}->{play_game} == DYSTOPIA())
	{
		if ($logline =~ /^weapon { steam_id: 'STEAM_\d+:(.+?)', weapon_id: (\d+), class: \d+, team: \d+, shots: \((\d+),(\d+)\), hits: \((\d+),(\d+)\), damage: \((\d+),(\d+)\), headshots: \((\d+),(\d+)\), kills: \(\d+,\d+\) }$/)
		{
			# Prototype: weapon { steam_id: 'STEAMID', weapon_id: X, class: X, team: X, shots: (X,X), hits: (X,X), damage: (X,X), headshots: (X,X), kills: (X,X) }
			# Matches:
			# 501. Statsme weaponstats (Dystopia)
	
			my $steamid = $1;
			my $weapon = $2;
			my $shots = $3 + $4;
			my $hits = $5 + $6;
			my $damage = $7 + $8;
			my $headshots = $9 + $10;
			my $kills = $11 + $12;
			
			$ev_type = 501;
			
			my $weapcode = $dysweaponcodes{$weapon};
			
			$ev_type = 501;
			
			my $player = LookupPlayerByUniqueId($steamid);
			
			if ($player)
			{
				$ev_status = HLstats_EventMgr::EvStatsme(
					$player->{userid},
					$steamid,
					$weapcode,
					$shots,
					$hits,
					$headshots,
					$damage,
					$kills,
					0
				);
			}
		}
		elsif ($logline =~ /^(?:join|change)_class { steam_id: 'STEAM_\d+:(.+?)', .* (?:new_|)class: (\d+), .* }$/)
		{
			# Prototype: join_class { steam_id: 'STEAMID', team: X, class: Y, time: ZZZZZZZZZ }
			# Matches:
			#  6. Role Selection (Dystopia)
			
			my $steamid = $1;
			my $role = $2;
			$ev_type = 6;
			
			my $player = LookupPlayerByUniqueId($steamid);
			
			if ($player)
			{
				$ev_status = HLstats_EventMgr::EvRoleSelection(
					$player->{userid},
					$steamid,
					$role
				);
			}
		}
		elsif ($logline =~ /^objective { steam_id: 'STEAM_\d+:(.+?)', class: \d+, team: \d+, objective: '(.+?)', time: \d+ }$/)
		{
			# Prototype: objective { steam_id: 'STEAMID', class: X, team: X, objective: 'TEXT', time: X }
			# Matches:
			# 11. Player Action (Dystopia Objectives)
			
			my $steamid = $1;
			my $action = $2;
			
			my $player = LookupPlayerByUniqueId($steamid);
			
			if ($player)
			{
				$ev_status = HLstats_EventMgr::EvPlayerAction(
					$player->{userid},
					$steamid,
					$action
				);
			}
		}
	}

	if ($ev_type)
	{
		if ($g_debug > 2)
		{
			print <<"EOT"
				type   = "$ev_type"
				team   = "$ev_team"
				player = "$ev_player"
				verb   = "$ev_verb"
				obj_a  = "$ev_obj_a"
				obj_b  = "$ev_obj_b"
				obj_c  = "$ev_obj_c"
				properties = "$ev_properties"
EOT
;
			while (my($key, $value) = each(%ev_properties_hash))
			{
				print "property: \"$key\" = \"$value\"\n";
			}
			
			while (my($key, $value) = each(%ev_player))
			{
				print "player $key = \"$value\"\n";
			}
		}
		
		if ($ev_status ne "")
		{
			PrintEvent($ev_type, $ev_status);
		}
		else
		{
			PrintEvent($ev_type, "BAD DATA: $logline");
		}
	}
	elsif (($logline =~ /^Banid: "(.+?(?:<.+?>)*)" was (?:kicked and )?banned "for ([0-9]+).00 minutes" by "Console"$/) ||
		($logline =~ /^Banid: "(.+?(?:<.+?>)*)" was (?:kicked and )?banned "(permanently)" by "Console"$/)
		)
	{
		
		# Prototype: "player" verb[properties]
		# Banid: huaaa<1804><STEAM_0:1:10769><>" was kicked and banned "permanently" by "Console"
		
		$ev_player  = $1;
		my $ev_bantime = $2;
		my $playerinfo = getPlayerInfo($ev_player, 1);
		
		if ($ev_bantime eq "5")
		{
			PrintEvent("BAN", "Auto Ban - ignored");
		}
		elsif ($playerinfo)
		{
			if (($g_global_banning > 0) && ($g_servers{$s_addr}->{ignore_nextban}->{$playerinfo->{uniqueid}} == 1))
			{
				delete($g_servers{$s_addr}->{ignore_nextban}->{$playerinfo->{uniqueid}});
				PrintEvent("BAN", "Global Ban - ignored");
			}
			elsif (!$g_servers{$s_addr}->{ignore_nextban}->{$playerinfo->{uniqueid}})
			{
				my $p_userid = $playerinfo->{userid};
				my $p_steamid = $playerinfo->{uniqueid};
				my $player_obj = LookupPlayer($s_addr, $p_userid, $p_steamid);
				PrintEvent("BAN", "Steamid: ".$p_steamid);
				
				if ($player_obj)
				{
					$player_obj->{is_banned} = 1;
				}
				
				if ($p_steamid ne "" && $playerinfo->{is_bot} == 0 && $p_userid > 0
					&& $g_global_banning > 0
					)
				{
					if ($ev_bantime eq "permanently")
					{
						PrintEvent("BAN", "Hide player!");
						
						$g_queryqueue->enqueue("player_banandhide");
						$g_queryqueue->enqueue("UPDATE hlstats_Players INNER JOIN hlstats_PlayerUniqueIds ON hlstats_Players.playerId = hlstats_PlayerUniqueIds.playerId SET hideranking=2 WHERE uniqueId=?");
						$g_queryqueue->enqueue([$p_steamid]);
						
						$ev_bantime = 0;
					}
					
					my $pl_steamid  = $playerinfo->{plain_uniqueid};
					while (my($addr, $server) = each(%g_servers))
					{
						if ($addr ne $s_addr)
						{
							PrintEvent("BAN", "Global banning on ".$addr);
							$server->{ignore_nextban}->{$p_steamid} = 1;
							$server->DoRcon("banid ".$ev_bantime." $pl_steamid");
							$server->DoRcon("writeid");
						}  
					} 
				}  
			}  
		}
		else
		{
			PrintEvent("BAN", "No playerinfo");
		}
		PrintEvent("BAN", $logline);
	}
	elsif ($g_debug > 1)
	{
		# Unrecognized event
		# HELLRAISER
		PrintEvent(999, "UNRECOGNIZED: " .$logline);
	}
	return;
}

sub track_hlstats_trend
{
	my $now  = time();
	if ($last_trend_timestamp <= 0)
	{
		$last_trend_timestamp = $now;
		return;
	}
	
	if ($last_trend_timestamp+299 >= $now)
	{
		return;
	}
	
	my $result = $g_db->DoQuery("SELECT COUNT(playerId), a.game FROM hlstats_Players a INNER JOIN (SELECT game FROM hlstats_Servers GROUP BY game) AS b ON a.game=b.game GROUP BY a.game");
	my $insvalues = "";
	while ( my($total_players, $game) = $result->fetchrow_array)
	{
		my $data = $g_db->DoQuery("SELECT SUM(kills), SUM(headshots), COUNT(serverId), SUM(act_players), SUM(max_players) FROM hlstats_Servers WHERE game=".$g_db->Quote($game));
		my ($total_kills, $total_headshots, $total_servers, $act_slots, $max_slots) = $data->fetchrow_array;
		if ($act_slots > $max_slots && $max_slots > 0)
		{
			$act_slots = $max_slots;
		}
		if ($insvalues ne "")
		{
			$insvalues .= ",";
		}
		$insvalues .= "
			(
				$now,
				".$g_db->Quote($game).",
				$total_players,
				$total_kills,
				$total_headshots,
				$total_servers,
				$act_slots,
				$max_slots
			)
		";
	}
	if ($insvalues ne "")
	{
		$g_db->DoFastQuery("
			INSERT INTO
				hlstats_Trend
				(
					timestamp,
					game,
					players,
					kills,
					headshots,
					servers,
					act_slots,
					max_slots
				)
				VALUES $insvalues
		");
	}
	$last_trend_timestamp = $now;
	&PrintEvent("HLSTATSX", "Insert new server trend timestamp", 1);
	
	return;
}

sub SendGlobalChat
{
	my ($message) = @_;
	while( my($server) = each(%g_servers))
	{
		if ($server eq $s_addr || scalar(keys(%{$g_servers{$server}->{srv_players}})) == 0)
		{
			next;
		}
		
		my @userlist;
		
		while ( my($pl, $player) = each(%{$g_servers{$server}->{srv_players}}) )
		{
			my $b_userid = $player->{userid};
			# add to list if player has global chat on, has events on, and, if only-admin global chat enabled, is admin
			if ($player->{display_chat} == 1 && $player->{display_events} == 1 && ($g_global_chat != 1 || $g_servers{$server}->is_admin($player->{uniqueid}) == 1))
			{
				push(@userlist, $player->{userid});
			}
		}
		
		if (scalar(@userlist))
		{
			$g_servers{$server}->MessageMany($message, 0, \@userlist);
		}
	}
	
	return;
}

#
# void BuildEventInsertData ()
#
# Ran at startup to init event table queues, build initial queries, and set allowed-null columns
#

sub BuildEventInsertData
{
	my $insertType = "";
	$insertType = " DELAYED" if ($db_lowpriority);
	while ( my ($table, $colsref) = each(%HLstats_Common::g_EventTables) )
	{
		$g_EventTableData{$table}{queue}       = [];
		$g_EventTableData{$table}{nullallowed} = 0;
		$g_EventTableData{$table}{lastflush}   = time();
		$g_EventTableData{$table}{query}       = "
		INSERT INTO
			hlstats_Events_$table
			(
				eventTime,
				serverId,
				map"
				;
		my $j = 0;
		foreach (@{$colsref})
		{
			$g_EventTableData{$table}{query} .=  ",\n$_";
			if (substr($_, 0, 4) eq 'pos_')
			{
				$g_EventTableData{$table}{nullsallowed} |= (1<<$j);
			}
			$j++;
		}
		$g_EventTableData{$table}{query} .= ")VALUES\n";
	}
	
	return;
}

#
# void recordEvent (string table, array cols, bool getid, [mixed eventData ...])
#
# Queues an event for addition to an Events table, flushing when hitting table queue limit.
#

sub RecordEvent
{
	my $table   = shift;
	my $unused  = shift;
	my @coldata = @_;
	
	my $row = "(FROM_UNIXTIME($ev_unixtime),".$g_servers{$s_addr}->{id}.",".$g_db->Quote($g_servers{$s_addr}->get_map());
	my $j = 0;
	for (@coldata)
	{
		if ($g_EventTableData{$table}{nullallowed} & (1<<$j) && (!defined($_) || $_ eq ""))
		{
			$row .= ",NULL";
		}
		elsif (!defined($_))
		{
			$row .= ",''";
		}
		else
		{
			$row .= ",".$g_db->Quote($_);
		}
		$j++;
	}
	$row .= ")";
	
	push(@{$g_EventTableData{$table}{queue}}, $row);
	
	if (scalar(@{$g_EventTableData{$table}{queue}}) > $g_EventQueueSize)
	{
		FlushEventTable($table);
	}
	
	return;
}

sub FlushEventTable
{
	my ($table) = @_;
	
	if (scalar(@{$g_EventTableData{$table}{queue}}) == 0)
	{
 		return;
 	}
 	
	my $query = $g_EventTableData{$table}{query};
	foreach (@{$g_EventTableData{$table}{queue}})
	{
		$query .= $_.",";
	}
	$query =~ s/,$//;
	$g_queryqueue->enqueue('nc');
	$g_queryqueue->enqueue($query);
	$g_EventTableData{$table}{lastflush} = time();
	$g_EventTableData{$table}{queue} = [];
	
	return;
}


#
# int getPlayerId (uniqueId)
#
# Looks up a player's ID number, from their unique (WON) ID. Returns their PID.
#

sub getPlayerId
{
	my ($uniqueId) = @_;

	my $query = "
		SELECT
			playerId
		FROM
			hlstats_PlayerUniqueIds
		WHERE
			game=" . $g_db->Quote($g_servers{$s_addr}->{game}) . " AND
			uniqueId=" . $g_db->Quote($uniqueId)
			
	;
	my $result = $g_db->DoQuery($query);

	if ($result->rows > 0)
	{
		my ($playerId) = $result->fetchrow_array;
		$result->finish;
		return $playerId;
	}
	else
	{
		$result->finish;
		return 0;
	}
}


#
# int updatePlayerProfile (object player, string field, string value)
#
# Updates a player's profile information in the database.
#

sub updatePlayerProfile
{
	my ($player, $field, $value) = @_;
	my $rcmd = $g_servers{$s_addr}->{player_command};
	
	if (!$player)
	{
		&PrintNotice("updatePlayerInfo: Bad player");
		return 0;
	}

	if ($value eq "none" || $value eq " ")
	{
		$value = "";
	}
	
	my $playerName = &abbreviate($player->{name});
	my $playerId   = $player->{playerid};

	$g_db->DoFastQuery("
		UPDATE
			hlstats_Players
		SET
			$field=?
		WHERE
			playerId=?
	");
	
	$g_queryqueue->enqueue("player_update_$field");
	$g_queryqueue->enqueue("UPDATE hlstats_Players SET $field=? WHERE playerId=?");
	$g_queryqueue->enqueue([$value, $playerId]);
	
	if ($g_servers{$s_addr}->{player_events} == 1)
	{
		my $p_userid  = $g_servers{$s_addr}->FormatUserId($player->{userid});
		my $p_is_bot  = $player->{is_bot};
		my $cmd_str = $rcmd." $p_userid ".$g_servers{$s_addr}->quoteparam("SET command successful for '$playerName'.");
		$g_servers{$s_addr}->DoRcon($cmd_str);
	}
	return 1;
}


#
# mixed getClanId (string name)
#
# Looks up a player's clan ID from their name. Compares the player's name to tag
# patterns in hlstats_ClanTags. Patterns look like:  [AXXXXX] (matches 1 to 6
# letters inside square braces, e.g. [ZOOM]Player)  or  =\*AAXX\*= (matches
# 2 to 4 letters between an equals sign and an asterisk, e.g.  =*RAGE*=Player).
#
# Special characters in the pattern:
#    A    matches one character  (i.e. a character is required)
#    X    matches zero or one characters  (i.e. a character is optional)
#    a    matches literal A or a
#    x    matches literal X or x
#
# If no clan exists for the tag, it will be created. Returns the clan's ID, or
# 0 if the player is not in a clan.
#

sub getClanId
{
	my ($name) = @_;
	my $clanTag  = "";
	my $clanName = "";
	my $clanId   = 0;
	my $result = $g_db->DoQuery("
		SELECT
			pattern,
			position,
			LENGTH(pattern) AS pattern_length
		FROM
			hlstats_ClanTags
		ORDER BY
			pattern_length DESC,
			id
	");
	
	while ( my($pattern, $position) = $result->fetchrow_array)
	{
		my $regpattern = quotemeta($pattern);
		$regpattern =~ s/([A-Za-z0-9]+[A-Za-z0-9_-]*)/\($1\)/; # to find clan name from tag
		$regpattern =~ s/A/./g;
		$regpattern =~ s/X/.?/g;
		
		if ($g_debug > 2) {
			&PrintNotice("regpattern=$regpattern");
		}
		
		if ((($position eq "START" || $position eq "EITHER") && $name =~ /^($regpattern).+/i) ||
			(($position eq "END"   || $position eq "EITHER") && $name =~ /.+($regpattern)$/i))
		{
			
			if ($g_debug > 2)
			{
				&PrintNotice("pattern \"$regpattern\" matches \"$name\"! 1=\"$1\" 2=\"$2\"");
			}
			
			$clanTag  = $1;
			$clanName = $2;
			last;
		}
	}
	
	if (!$clanTag)
	{
		return 0;
	}

	my $query = "
		SELECT
			clanId
		FROM
			hlstats_Clans
		WHERE
			tag=?
			AND game=?
		";
	$result = $g_db->DoCachedQuery("clan_select_id", $query, [$clanTag, $g_servers{$s_addr}->{game}]);

	if ($result->rows)
	{
		($clanId) = $result->fetchrow_array;
		$result->finish;
		return $clanId;
	}
	else
	{
		# The clan doesn't exist yet, so we create it.
		$query = "
			REPLACE INTO
				hlstats_Clans
				(
					tag,
					name,
					game
				)
			VALUES
			(
				?,
				?,
				?
			)
		";
		my $vals = [$clanTag, $clanName, $g_servers{$s_addr}->{game}];
		$g_db->DoCachedQuery("clan_insert_clan", $query, $vals);
		
		$clanId = $g_db->GetInsertId();

		&PrintNotice("Created clan \"$clanName\" <C:$clanId> with tag "
				. "\"$clanTag\" for player \"$name\"");
		return $clanId;
	}
}


#
# object getServer (string address, int port)
#
# Looks up a server's ID number in the Servers table, by searching for a
# matching IP address and port. NOTE you must specify IP addresses in the
# Servers table, NOT hostnames.
#
# Returns a new "Server object".
#

sub getServer
{
	my ($address, $port) = @_;

	my $query = "
		SELECT
			a.serverId,
			a.game,
			a.name,
			a.rcon_password,
			a.publicaddress,
			IFNULL(b.`value`,3) AS game_engine,
			IFNULL(c.`realgame`, 'hl2mp') AS realgame,
			IFNULL(a.max_players, 0) AS maxplayers
			
		FROM
			hlstats_Servers a LEFT JOIN hlstats_Servers_Config b on a.serverId = b.serverId AND b.`parameter` = 'GameEngine' LEFT JOIN `hlstats_Games` c ON a.game = c.code
		WHERE
			address='$address' AND
			port='$port' LIMIT 1
		";
	my $result = $g_db->DoQuery($query);

	if ($result->rows)
	{
		my ($serverId, $game, $name, $rcon_pass, $publicaddress, $gameengine, $realgame, $maxplayers) = $result->fetchrow_array;
		$result->finish;
		if (!defined($g_games{$game}))
		{
			$g_games{$game} = HLstats_Game->new($game);
		}
		# l4d code should be reused for l4d2
		# trying first using l4d as "realgame" code for l4d2 in db. if default server config settings won't work, will leave as own "realgame" code in db but uncomment line.
		#$realgame = "l4d" if $realgame eq "l4d2";
		
		return HLstats_Server->new($serverId, $address, $port, $name, $rcon_pass, $game, $publicaddress, $gameengine, $realgame, $maxplayers);
	}
	else
	{
		$result->finish;
		return 0;
	}
}

#
# 
#
#
#

sub queryServer
{
	my ($iaddr, $iport, @query)            = @_;
	my $game = "";
	my $timeout=1;
	my $message = IO::Socket::INET->new(Proto=>"udp",Timeout=>$timeout,PeerPort=>$iport,PeerAddr=>$iaddr) or die "Can't make UDP socket: $@";
	$message->send("\xFF\xFF\xFF\xFFTSource Engine Query\x00");
	my ($datagram,$flags);
	my $end = time + $timeout;
	my $rin = '';
	vec($rin, fileno($message), 1) = 1;

	my %hash = ();

	while (1)
	{
		my $timeleft = $end - time;
		last if ($timeleft <= 0);
		my ($nfound, $t) = select(my $rout = $rin, undef, undef, $timeleft);
		last if ($nfound == 0); # either timeout or end of file
		$message->recv($datagram,1024,$flags);
		@hash{qw/key type netver hostname mapname gamedir gamename id numplayers maxplayers numbots dedicated os passreq secure gamever edf port/} = unpack("LCCZ*Z*Z*Z*vCCCCCCCZ*Cv",$datagram);
	}

	return @hash{@query};
}


sub getServerMod
{
	my ($address, $port) = @_;
	my ($playgame);

	&PrintEvent ("DETECT", "Querying $address".":$port for gametype");

	my @query = (
			'gamename',
			'gamedir',
			'hostname',
			'numplayers',
			'maxplayers',
			'mapname'
			);

	my ($gamename, $gamedir, $hostname, $numplayers, $maxplayers, $mapname) = &queryServer($address, $port, @query);

	if ($gamename =~ /^Counter-Strike$/i) {
		$playgame = "cstrike";
	} elsif ($gamename =~ /^Counter-Strike/i) {
		$playgame = "css";
	} elsif ($gamename =~ /^Team Fortress C/i) {
		$playgame = "tfc";
	} elsif ($gamename =~ /^Team Fortress/i) {
		$playgame = "tf";
	} elsif ($gamename =~ /^Day of Defeat$/i) {
		$playgame = "dod";
	} elsif ($gamename =~ /^Day of Defeat/i) {
		$playgame = "dods";
	} elsif ($gamename =~ /^Insurgency/i) {
		$playgame = "insmod";
	} elsif ($gamename =~ /^Neotokyo/i) {
		$playgame = "nts";
	} elsif ($gamename =~ /^Fortress Forever/i) {
		$playgame = "ff";
	} elsif ($gamename =~ /^Age of Chivalry/i) {
		$playgame = "aoc";
	} elsif ($gamename =~ /^Dystopia/i) {
		$playgame = "dystopia";
	} elsif ($gamename =~ /^Stargate/i) {
		$playgame = "sgtls";
	} elsif ($gamename =~ /^Battle Grounds/i) {
		$playgame = "bg2";
	} elsif ($gamename =~ /^Hidden/i) {
		$playgame = "hidden";
	} elsif ($gamename =~ /^L4D /i) {
		$playgame = "l4d";
	} elsif ($gamename =~ /^Left 4 Dead 2/i) {
		$playgame = "l4d2";
	} elsif ($gamename =~ /^ZPS /i) {
		$playgame = "zps";
	} elsif ($gamename =~ /^NS /i) {
		$playgame = "ns";
	} elsif ($gamename =~ /^pvkii/i) {
		$playgame = "pvkii";
	} elsif ($gamename =~ /^CSPromod/i) {
		$playgame = "csp";
	} elsif ($gamename eq "Half-Life") {
		$playgame = "valve";
		
	# We didn't found our mod, trying secondary way. This is required for some games such as FOF and GES and is a fallback for others
	} elsif ($gamedir =~ /^ges/i) {
		$playgame = "ges";
	} elsif ($gamedir =~ /^fistful_of_frags/i || $gamedir =~ /^fof/i) {
		$playgame = "fof";
	} elsif ($gamedir =~ /^hl2mp/i) {
		$playgame = "hl2mp";
	} elsif ($gamedir =~ /^tfc/i) {
		$playgame = "tfc";
	} elsif ($gamedir =~ /^tf/i) {
		$playgame = "tf";
	} elsif ($gamedir =~ /^ins/i) {
		$playgame = "insmod";
	} elsif ($gamedir =~ /^neotokyo/i) {
		$playgame = "nts";
	} elsif ($gamedir =~ /^fortressforever/i) {
		$playgame = "ff";
	} elsif ($gamedir =~ /^ageofchivalry/i) {
		$playgame = "aoc";
	} elsif ($gamedir =~ /^dystopia/i) {
		$playgame = "dystopia";
	} elsif ($gamedir =~ /^sgtls/i) {
		$playgame = "sgtls";
	} elsif ($gamedir =~ /^hidden/i) {
		$playgame = "hidden";
	} elsif ($gamedir =~ /^left4dead/i) {
		$playgame = "l4d";
	} elsif ($gamedir =~ /^left4dead2/i) {
		$playgame = "l4d2";
	} elsif ($gamedir =~ /^zps/i) {
		$playgame = "zps";
	} elsif ($gamedir =~ /^ns/i) {
		$playgame = "ns";
	} elsif ($gamedir =~ /^bg/i) {
		$playgame = "bg2";
	} elsif ($gamedir =~ /^pvkii/i) {
		$playgame = "pvkii";
	} elsif ($gamedir =~ /^cspromod/i) {
		$playgame = "csp";
	} elsif ($gamedir =~ /^valve$/i) {
		$playgame = "valve";
	} else {
		# We didn't found our mod, giving up.
		&PrintEvent("DETECT", "Failed to get Server Mod");
		return 0;
	}
	&PrintEvent("DETECT", "Saving server " . $address . ":" . $port . " with gametype " . $playgame);
	&addServerToDB($address, $port, $hostname, $playgame, $numplayers, $maxplayers, $mapname);
	return $playgame;
}

sub addServerToDB
{
	my ($address, $port, $name, $game, $act_players, $max_players, $act_map) = @_;
	my $sql = "INSERT INTO hlstats_Servers (address, port, name, game, act_players, max_players, act_map) VALUES ('$address', $port, ".$g_db->Quote($name).", ".$g_db->Quote($game).", $act_players, $max_players, ".$g_db->Quote($act_map).")";
	$g_db->DoFastQuery($sql);
   
	my $last_id = $g_db->GetInsertId();
	$g_db->DoFastQuery("DELETE FROM `hlstats_Servers_Config` WHERE serverId = $last_id");
	$g_db->DoFastQuery("INSERT INTO `hlstats_Servers_Config` (`serverId`, `parameter`, `value`)
				SELECT $last_id, `parameter`, `value`
				FROM `hlstats_Mods_Defaults` WHERE `code` = '';");
	$g_db->DoFastQuery("INSERT INTO `hlstats_Servers_Config` (`serverId`, `parameter`, `value`) VALUES
				($last_id, 'Mod', '');");
	$g_db->DoFastQuery("INSERT INTO `hlstats_Servers_Config` (`serverId`, `parameter`, `value`)
				SELECT $last_id, `parameter`, `value`
				FROM `hlstats_Games_Defaults` WHERE `code` = ".$g_db->Quote($game)."
				ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);");   
	&readDatabaseConfig();

	return 1;
}

#
# string GetPlayerInfoString (object player, string ident)
#

sub GetPlayerInfoString
{
	my ($player) = shift;
	my @ident = @_;
	
	if ($player)
	{
		return $player->getInfoString();
	}
	else
	{
		return "(" . join(",", @ident) . ")";
	}
}



#
# array getPlayerInfo (string player, string $ipAddr)
#
# Get a player's name, uid, wonid and team from "Name<uid><wonid><team>".
#

sub getPlayerInfo
{
	my ($player, $create_player, $ipAddr) = @_;

	if ($player =~ /^(.*?)<(\d+)><([^<>]*)><([^<>]*)>(?:<([^<>]*)>)?.*$/)
	{
		my $name       = $1;
		my $userid     = $2;
		my $uniqueid   = $3;
		my $team       = $4;
		my $role       = $5;
		my $bot        = 0;
		my $haveplayer = 0;
		
		my $plainuniqueid = $uniqueid;
		
		if (($uniqueid eq "Console") && ($team eq "Console"))
		{
			return 0;
		}
		$uniqueid =~ s/^STEAM_[0-9]+?\://;
		if (!defined($role))
		{
			$role = "";
		}
		if ($g_servers{$s_addr}->{play_game} == L4D())
		{
		#for l4d, create meta player object for each role
			if ($uniqueid eq "")
			{
				#infected & witch have blank steamid
				if ($name eq "infected")
				{
					$uniqueid = "BOT-Horde";
					$team = "Infected";
					$userid = -9;
				}
				elsif ($name eq "witch")
				{
					$uniqueid = "BOT-Witch";
					$team = "Infected";
					$userid = -10;
				}
				else
				{
					return 0;
				}
			}
			elsif ($uniqueid eq "BOT")
			{
				#all other bots have BOT for steamid
				if ($team eq "Survivor")
				{
					if ($name eq "Nick") {
						$userid = -11;
					} elsif ($name eq "Ellis") {
						$userid = -13;
					} elsif ($name eq "Rochelle") {
						$userid = -14;
					} elsif ($name eq "Coach") {
						$userid = -12;
					} elsif ($name eq "Louis") {
						$userid = -4;
					} elsif ($name eq "Zoey") {
						$userid = -1;
					} elsif ($name eq "Francis") {
						$userid = -2;
					} elsif ($name eq "Bill") {
						$userid = -3;
					} else {
						&PrintEvent("ERROR", "No survivor match for $name",0,1);
						$userid = -4;
					}
				} else {
					if ($name eq "Smoker") {
						$userid = -5;
					} elsif ($name eq "Boomer") {
						$userid = -6;
					} elsif ($name eq "Hunter") {
						$userid = -7;
					} elsif ($name eq "Spitter") {
						$userid = -15;
					} elsif ($name eq "Jockey") {
						$userid = -16;
					} elsif ($name eq "Charger") {
						$userid = -17;
					} elsif ($name eq "Tank") {
						$userid = -8;						
					} else {
						PrintDebug("No infected match for $name");
						$userid = -8;
					}
				}
				$uniqueid = "BOT-".$name;
				$name = "BOT-".$name;
			}
		}

		if (!defined($ipAddr) || $ipAddr eq "none")
		{
			$ipAddr = "";
		}
		
		$bot = botidcheck($uniqueid);
		
		if ($g_mode == TRACKMODE_LAN() && !$bot && $userid > 0) {
			if ($ipAddr ne "") {
				$g_lan_noplayerinfo{"$s_addr/$userid/$name"} = {
					ipaddress => $ipAddr,
					userid => $userid,
					name => $name,
					server => $s_addr
					};
				$uniqueid = $ipAddr;
			} else {
				while ( my($index, $player) = each(%g_players) ) {
					if (($player->{userid} eq $userid) &&
						($player->{name}   eq $name)) {
					
						$uniqueid = $player->{uniqueid}; 
						$haveplayer = 1;
						last;
					}   
				}
				if (!$haveplayer) {
					while ( my($index, $player) = each(%g_lan_noplayerinfo) ) {
						if (($player->{server} eq $s_addr) &&
							($player->{userid} eq $userid) &&
							($player->{name}   eq $name)) {
					
							$uniqueid = $player->{ipaddress}; 
							$haveplayer = 1;
						}    
					}  
				}
				if (!$haveplayer) {
					$uniqueid = "UNKNOWN";
				}
			}
		} else {
			# Normal (steamid) mode player and bot, as well as lan mode bots
			if ($bot) {
				my $md5 = Digest::MD5->new;
				$md5->add($name);
				$md5->add($s_addr);
				$uniqueid = "BOT:" . $md5->hexdigest;
			}
		
			if ($uniqueid eq "UNKNOWN"
				|| $uniqueid eq "STEAM_ID_PENDING" || $uniqueid eq "STEAM_ID_LAN"
				|| $uniqueid eq "VALVE_ID_PENDING" || $uniqueid eq "VALVE_ID_LAN"
			) {
				return {
					name     => $name,
					userid   => $userid,
					uniqueid => $uniqueid,
					team     => $team
				};
			}
		}
		
		if (!$haveplayer)
		{
			while ( my ($index, $player) = each(%g_players) ) {
				# Cannot exit loop early as more than one player can exist with same uniqueid
				# (bug? or just bad logging)
				# Either way, we disconnect any that don't match the current line
				if ($player->{uniqueid} eq $uniqueid) {
					$haveplayer = 1;
					# Catch players reconnecting without first disconnecting
					if ($player->{userid} != $userid) {
					
						HLstats_EventMgr::EvDisconnect(
							$player->{userid},
							$uniqueid,
							""
						);
						$haveplayer = 0;
					}
				}
			}
		}
		
		if ($haveplayer) {
			my $player = LookupPlayer($s_addr, $userid, $uniqueid);
			if ($player) {
				if ($player->{team} ne $team) {
					HLstats_EventMgr::EvTeamSelection(
						$userid,
						$uniqueid,
						$team
					);
				}
				if ($role ne "" && $role ne $player->{role}) {
					HLstats_EventMgr::EvRoleSelection(
						$player->{userid},
						$player->{uniqueid},
						$role
					);
				}
				
				$player->updateTimestamp();
			}  
		} else {
			if ($userid != 0) {
				if ($create_player > 0) {
					my $preIpAddr = "";
					if (defined($g_preconnect{"$s_addr/$userid/$name"})) {
						$preIpAddr = $g_preconnect{"$s_addr/$userid/$name"}->{ipaddress};
					}
					# Add the player to our hash of player objects
					$g_servers{$s_addr}->{srv_players}->{"$userid/$uniqueid"} = HLstats_Player->new(
						server => $s_addr,
						server_id => $g_servers{$s_addr}->{id},
						userid => $userid,
						uniqueid => $uniqueid,
						plain_uniqueid => $plainuniqueid,
						game => $g_servers{$s_addr}->{game},
						name => $name,
						team => $team,
						role => $role,
						is_bot => $bot,
						display_events => $g_servers{$s_addr}->{default_display_events},
						address => (($preIpAddr ne "") ? $preIpAddr : $ipAddr)
					);
					
					if ($preIpAddr ne "") {
						&PrintEvent("SERVER", "LATE CONNECT [$name/$userid] - steam userid validated");
						HLstats_EventMgr::EvConnect($userid, $uniqueid, $preIpAddr);
						delete($g_preconnect{"$s_addr/$userid/$name"});
					}
					# Increment number of players on server
					$g_servers{$s_addr}->updatePlayerCount();
				}  
			} elsif (($g_mode == TRACKMODE_LAN()) && (exists $g_lan_noplayerinfo{"$s_addr/$userid/$name"})) {
				if ((!$haveplayer) && ($uniqueid ne "UNKNOWN") && ($create_player > 0)) {
					$g_servers{$s_addr}->{srv_players}->{"$userid/$uniqueid"} = HLstats_Player->new(
						server => $s_addr,
						server_id => $g_servers{$s_addr}->{id},
						userid => $userid,
						uniqueid => $uniqueid,
						plain_uniqueid => $plainuniqueid,
						game => $g_servers{$s_addr}->{game},
						name => $name,
						team => $team,
						role => $role,
						is_bot => $bot
					);
					delete($g_lan_noplayerinfo{"$s_addr/$userid/$name"});
					# Increment number of players on server
					
					$g_servers{$s_addr}->updatePlayerCount();
				} 
			} else {
				&PrintNotice("No player object available for player \"$name\" <U:$userid>");
			}
		}
		
		return {
			name     => $name,
			userid   => $userid,
			uniqueid => $uniqueid,
			team     => $team,
			is_bot   => $bot
		};
	} elsif ($player =~ /^(.+)<([^<>]+)>$/) {
		my $name     = $1;
		my $uniqueid = $2;
		my $bot      = 0;
		
		if (&botidcheck($uniqueid)) {
			my $md5 = Digest::MD5->new;
			$md5->add(time());
			$md5->add($s_addr);
			$uniqueid = "BOT:" . $md5->hexdigest;
			$bot = 1;
		}
		return {
			name     => $name,
			uniqueid => $uniqueid,
			is_bot   => $bot
		};
	} elsif ($player =~ /^<><([^<>]+)><>$/) {
		my $uniqueid = $1;
		my $bot      = 0;
		if (&botidcheck($uniqueid)) {
			my $md5 = Digest::MD5->new;
			$md5->add(time());
			$md5->add($s_addr);
			$uniqueid = "BOT:" . $md5->hexdigest;
			$bot = 1;
		}
		return {
			uniqueid => $uniqueid,
			is_bot   => $bot
		};
	} else {
		return 0;
	}
}


#
# hash getProperties (string propstring)
#
# Parse (key "value") properties into a hash.
#

sub getProperties
{
	my ($propstring) = @_;
	my %properties;
	my $dods_flag = 0;
	
	while ($propstring =~ s/^\s*\((\S+)(?:(?: "(.+?)")|(?: ([^\)]+)))?\)//)
	{
		my $key = $1;
		
		if (defined($2))
		{
			if ($key eq "player")
			{
				if ($dods_flag == 1)
				{
					$key = "player_a";
					$dods_flag++;
				}
				elsif ($dods_flag == 2)
				{
					$key = "player_b";
				}
			}
			$properties{$key} = $2;
		}
		elsif (defined($3))
		{
			$properties{$key} = $3;
		}
		else
		{
			$properties{$key} = 1; # boolean property
		}
		
		if ($key eq "flagindex")
		{
			$dods_flag++;
		}
	}
	
	return %properties;
}


# 
# boolean like (string subject, string compare)
#
# Returns true if 'subject' equals 'compare' with optional whitespace.
#

sub like
{
	my ($subject, $compare) = @_;
	
	if ($subject =~ /^\s*\Q$compare\E\s*$/) {
		return 1;
	} else {
		return 0;
	}
}


# 
# boolean botidcheck (string uniqueid)
#
# Returns true if 'uniqueid' is that of a bot.
#

sub botidcheck
{
	# needs cleaned up
	# added /^00000000\:\d+\:0$/ check for "whichbot"
	my ($uniqueid) = @_;
	if ($uniqueid eq "BOT" || $uniqueid eq "__BOT__" || $uniqueid eq "0" || $uniqueid =~ /^00000000\:\d+\:0$/) {
		return 1
	}
	return 0;
}

sub isTrackableTeam
{
	my ($team) = @_;
	#if ($team =~ /spectator/i || $team =~ /unassigned/i || $team eq "") {
	if ($team =~ /spectator/i || $team eq "") {
		return 0;
	}
	return 1;
}

sub readDatabaseConfig
{
	&PrintEvent("CONFIG", "Reading database config...", 1);
	
	# Clear all, whether or not already init-ed
	%g_config_servers = ();
	%g_servers = ();
	%g_games = ();
	$g_rconqueue->enqueue(1);

	# elstatsneo: read the servers portion from the mysql database
	my $srv_id = $g_db->DoQuery("SELECT serverId,CONCAT(address,':',port) AS addr FROM hlstats_Servers");
	while ( my($serverId,$addr) = $srv_id->fetchrow_array)
	{
		$g_config_servers{$addr} = ();
		my $serverConfig = $g_db->DoQuery("SELECT parameter,value FROM hlstats_Servers_Config WHERE serverId=$serverId");
		while ( my($p,$v) = $serverConfig->fetchrow_array)
		{
			$g_config_servers{$addr}{$p} = $v;
		}
	}
	$srv_id->finish;
	# hlxce: read the global settings from the database!
	my $gsettings = $g_db->DoQuery("SELECT keyname,value FROM hlstats_Options WHERE opttype <= 1 OR keyname='dbversion'");  # do opttype 1 for dbversion later
	while ( my($p,$v) = $gsettings->fetchrow_array)
	{
		if ($g_debug > 1)
		{
			print "Config parameter '$p' = '$v'\n";
		}
		
		if ($p eq "version")  # this is hacky, but not much more than the eval
		{
			$HLstats_Common::version = $v;
			next;
		}
		elsif ($p eq 'dbversion')
		{
			$g_dbversion = $v;
			next;
		}
		elsif ($p eq 'Mode')
		{
			# can remove this after we update web and db to store/read as int
			if ($v eq 'LAN')
			{
				$v = TRACKMODE_LAN();
			}
			else
			{
				$v = TRACKMODE_NORMAL();
			}
		}
		my $tmp = "\$".$directives_mysql{$p}." = '$v'";
		#print " -> setting ".$tmp."\n";
		eval $tmp;
	}
	$gsettings->finish;
	# setting defaults

	&PrintEvent("DAEMON", "Proxy_Key DISABLED", 1) if ($g_proxy_key eq "");
	while (my($addr, $server) = each(%g_config_servers))
	{		
		if (!defined($g_config_servers{$addr}{"MinPlayers"})) {
			$g_config_servers{$addr}{"MinPlayers"}                      = 6;
		}  
		if (!defined($g_config_servers{$addr}{"DisplayResultsInBrowser"})) {
			$g_config_servers{$addr}{"DisplayResultsInBrowser"}         = 0;
		}  
		if (!defined($g_config_servers{$addr}{"BroadCastEvents"})) {
			$g_config_servers{$addr}{"BroadCastEvents"}                 = 0;
		}
		if (!defined($g_config_servers{$addr}{"BroadCastPlayerActions"})) {
			$g_config_servers{$addr}{"BroadCastPlayerActions"}          = 0;
		}
		if (!defined($g_config_servers{$addr}{"BroadCastEventsCommand"})) {
			$g_config_servers{$addr}{"BroadCastEventsCommand"}          = "say";
		}
		if (!defined($g_config_servers{$addr}{"BroadCastEventsCommandAnnounce"})) {
			$g_config_servers{$addr}{"BroadCastEventsCommandAnnounce"}  = "say";
		}
		if (!defined($g_config_servers{$addr}{"PlayerEvents"})) {
			$g_config_servers{$addr}{"PlayerEvents"}                    = 1;
		}
		if (!defined($g_config_servers{$addr}{"PlayerEventsCommand"})) {
			$g_config_servers{$addr}{"PlayerEventsCommand"}             = "say";
		}
		if (!defined($g_config_servers{$addr}{"PlayerEventsCommandOSD"})) {
			$g_config_servers{$addr}{"PlayerEventsCommandOSD"}          = "";
		}
		if (!defined($g_config_servers{$addr}{"PlayerEventsCommandHint"})) {
			$g_config_servers{$addr}{"PlayerEventsCommandHint"}         = "";
		}
		if (!defined($g_config_servers{$addr}{"PlayerEventsAdminCommand"})) {
			$g_config_servers{$addr}{"PlayerEventsAdminCommand"}        = "";
		}
		if (!defined($g_config_servers{$addr}{"ShowStats"})) {
			$g_config_servers{$addr}{"ShowStats"}                       = 1;
		}
		if (!defined($g_config_servers{$addr}{"AutoTeamBalance"})) {
			$g_config_servers{$addr}{"AutoTeamBalance"}                 = 0;
		}
		if (!defined($g_config_servers{$addr}{"AutoBanRetry"})) {
			$g_config_servers{$addr}{"AutoBanRetry"}                    = 0;
		}
		if (!defined($g_config_servers{$addr}{"TrackServerLoad"})) {
			$g_config_servers{$addr}{"TrackServerLoad"}                 = 0;
		}
		if (!defined($g_config_servers{$addr}{"MinimumPlayersRank"})) {
			$g_config_servers{$addr}{"MinimumPlayersRank"}              = 0;
		}
		if (!defined($g_config_servers{$addr}{"Admins"})) {
			$g_config_servers{$addr}{"Admins"}                          = "";
		}
		if (!defined($g_config_servers{$addr}{"SwitchAdmins"})) {
			$g_config_servers{$addr}{"SwitchAdmins"}                    = 0;
		}
		if (!defined($g_config_servers{$addr}{"IgnoreBots"})) {
			$g_config_servers{$addr}{"IgnoreBots"}                      = 1;
		}
		if (!defined($g_config_servers{$addr}{"SkillMode"})) {
			$g_config_servers{$addr}{"SkillMode"}                       = 0;
		}
		if (!defined($g_config_servers{$addr}{"GameType"})) {
			$g_config_servers{$addr}{"GameType"}                        = 0;
		}
		if (!defined($g_config_servers{$addr}{"BonusRoundTime"})) {
			$g_config_servers{$addr}{"BonusRoundTime"}                  = 0;
		}
		if (!defined($g_config_servers{$addr}{"BonusRoundIgnore"})) {
			$g_config_servers{$addr}{"BonusRoundIgnore"}                = 0;
		}
		if (!defined($g_config_servers{$addr}{"Mod"})) {
			$g_config_servers{$addr}{"Mod"}                             = "";
		}
		if (!defined($g_config_servers{$addr}{"EnablePublicCommands"})) {
			$g_config_servers{$addr}{"EnablePublicCommands"}            = 1;
		}
		if (!defined($g_config_servers{$addr}{"ConnectAnnounce"})) {
			$g_config_servers{$addr}{"ConnectAnnounce"}                 = 1;
		}
		if (!defined($g_config_servers{$addr}{"UpdateHostname"})) {
			$g_config_servers{$addr}{"UpdateHostname"}                  = 0;
		}
		if (!defined($g_config_servers{$addr}{"DefaultDisplayEvents"})) {
			$g_config_servers{$addr}{"DefaultDisplayEvents"}            = 1;
		}
	}

	&PrintEvent("CONFIG", "I have found the following server configs in database:", 1);
	while (my($addr, $server) = each(%g_config_servers)) {
		&PrintEvent("S_CONFIG", $addr, 1);
	}
	
	my $geotell = ((scalar keys %g_gi == 0) ? -1 : tell $g_gi{fh});
	
	if ($g_geoip_binary > 0 && $geotell == -1)
	{
		my $geoipfile = "$opt_libdir/GeoLiteCity/GeoLiteCity.dat";
		if (-r $geoipfile)
		{
			%g_gi = Geo::IP::PurePerl->open($geoipfile, "GEOIP_STANDARD");
		}
		else
		{
			&PrintEvent("ERROR", "GeoIP method set to binary file lookup but $geoipfile NOT FOUND", 1);
			%g_gi = ();
		}
	}
	elsif ($g_geoip_binary == 0 && $geotell > -1)
	{
		close($g_gi{fh});
		%g_gi = ();
	}
	
	return;
}

sub ReloadConfiguration
{
	FlushAll();
	readDatabaseConfig();
	
	return;
}

sub FlushAll
{
	# we only need to flush events if we're about to shut down. they are unaffected by server/player deletion
	my ($flushevents) = @_;
	if ($flushevents)
	{
		while ( my ($table, $colsref) = each(%HLstats_Common::g_EventTables) )
		{
			FlushEventTable($table);
		}
	}	
	
	while( my($saddr, $server) = each(%g_servers))
	{	
		while ( my($pl, $player) = each(%{$server->{srv_players}}) )
		{
			if ($player)
			{
				$player->playerCleanup();
			}
		}
		$server->flushDB();
	}
	
	return;
}

sub DBThread
{
	# Perl 5.12+ insists that we reiterate this
	use HLstats_Common;
	HLstats_Common->import(qw/PrintEvent PrintNotice PrintDebug/);
	##
	
	my $dbt = HLstats_DB->new($db_host, $db_name, $db_user, $db_pass);
	$g_threadname = "Query";
	
	$SIG{__DIE__} = 'Thread_DIE_handler';
	$SIG{__WARN__} = 'WARN_handler';
	
	# Only supports prepared queries
	#
	# Format:
	#  - Name to use as hash key for query, 'nc' for non-cached queries,
	#         or 'kill' to signal thread shutdown
	#  - Query
	#  - (cached queries only) Ref to array of query parameter values
	
	while(1)
	{
		my $name;
		if ($] < 5.008009)
		{
			($name) = $g_queryqueue->dequeue();
		}
		else
		{
			$name = $g_queryqueue->dequeue();
		}
		
		if ($name eq 'kill')
		{
			last;
		}
		
		my $query;
		if ($] < 5.008009)
		{
			($query) = $g_queryqueue->dequeue();
		}
		else
		{
			$query = $g_queryqueue->dequeue();
		}
		
		if ($name eq 'nc')
		{
			$dbt->DoFastQuery($query);
		}
		else
		{
			$dbt->DoCachedQuery($name, $query, $g_queryqueue->dequeue());
		}
	}
	
	PrintDebug("Exiting query thread gracefully");
	return;
}

sub RconThread
{
	# Perl 5.12+ insists that we reiterate this
	use HLstats_Common;
	HLstats_Common->import(qw/PrintEvent PrintNotice PrintDebug/);
	##
	
	my %rcons = ();
	$g_threadname = "Rcon";
	
	$SIG{__DIE__} = 'Thread_DIE_handler';
	$SIG{__WARN__} = 'WARN_handler';

	# Format:
	#  - control - 1 (clear all) / 2 (init) / 3 (command) / 4 (destroy) / 'kill' (stop thread)
	#  --------- 1 ----------
	#  (none)
	#  --------- 2 ---------
	#  - serverid
	#  - engine
	#  - address
	#  - port
	#  - password
	#  - (play)game
	#  --------- 3 ---------
	#  - serverid
	#  - command
	#  --------- 4 ---------
	#  - serverid
	#  ---------------------
	
	while (1)
	{
		my $control;
		if ($] < 5.008009)
		{
			($control) = $g_rconqueue->dequeue();
		}
		else
		{
			$control = $g_rconqueue->dequeue();
		}
		
		PrintDebug("Got \"$control\" as control packet in rcon queue", 5);
		
		if ($control eq 'kill')
		{
			last;
		}
		
		if ($control == 1)
		{
			# Clear all rcon objects
			%rcons = ();
			next;
		}
		
		my $serverid;
		if ($] < 5.008009)
		{
			($serverid) = $g_rconqueue->dequeue();
		}
		else
		{
			$serverid = $g_rconqueue->dequeue();
		}
		
		if ($control == 2)
		{
			# Init rcon for this server
			my $engine;
			my $address;
			my $port;
			my $password;
			my $game;
			
			if ($] < 5.008009)
			{
				($engine, $address, $port, $password, $game)     = $g_rconqueue->dequeue();
			}
			else
			{
				($engine, $address, $port, $password, $game)     = $g_rconqueue->dequeue(5);
			}
			
			if ($engine == 1)  # Goldsrc
			{
				$rcons{$serverid} = BASTARDrcon->new($address, $port, $password);
			}
			else  # Source
			{
				$rcons{$serverid} = TRcon->new($address, $port, $password, $game);
			}
			next;
		}
		
		
		if ($control == 3)
		{
			my $command;
			if ($] < 5.008009)
			{
				($command) = $g_rconqueue->dequeue();
			}
			else
			{
				$command = $g_rconqueue->dequeue();
			}
			
			# Send and forget!
			if (!$rcons{$serverid})
			{
				next;
			}
			$rcons{$serverid}->execute($command);
			next;
		}
		
		if ($control == 4)
		{
			# Server is gone, get rid of rcon object
			$rcons{$serverid} = undef;
		}
	}
	
	PrintDebug("Exiting rcon thread gracefully");
	
	return;
}

sub INT_handler
{
	print "SIGINT received. Flushing data and shutting down...\n";
	FlushAll(1);
	KillThreads();
	exit(0);
}

sub HUP_handler
{
	print "SIGHUP received. Flushing data and reloading configuration...\n";
	ReloadConfiguration();
}

sub WARN_handler
{
	PrintDebug("Entered WARN_handler", 3);
	if ($g_SubmitCrashes >= 2)
	{
		SubmitCrashOrWarning(2, @_);
	}
	print @_;
}

sub DIE_handler
{
	PrintDebug("Entered DIE_handler", 3);
	if ($g_SubmitCrashes >= 1)
	{
		SubmitCrashOrWarning(1, @_);
	}
	KillThreads();
	print @_;
}

sub Thread_DIE_handler
{
	PrintDebug("Entered Thread_DIE_handler", 3);
	PrintEvent("WARNING", "$g_threadname thread has died.");
	DIE_handler(@_);
	PrintEvent("ERROR", "A thread has died. Cannot continue");
	exit(1);  # we can just exit with non-zero code since we already 'died'
}

sub KillThreads
{
	PrintDebug("Entered KillThreads", 3);
	
	if ($] < 5.008009)
	{
		my $selfid = threads->tid();
		my (@threads) = threads->list();
		
		foreach (@threads)
		{
			my $id = $_->tid();
			if ($selfid && $id == $selfid)
			{
				next;
			}
			PrintDebug("Sending kill to thread $id", 3);
			if (defined($g_ThreadQueueMap{$id}))
			{
				$g_ThreadQueueMap{$id}->enqueue('kill');
				$_->join();
			}
			
			PrintDebug("Attempting to join thread $id", 3);
		}
	}
	else
	{
		if (!defined($qthread) || !$qthread->is_running())
		{
			PrintDebug("Query thread is not running", 3);
		}
		else
		{
			PrintDebug("Sending kill to query thread queue", 3);
			$g_queryqueue->enqueue('kill');
			PrintDebug("Attempting to join query thread", 3);
			my $res = $qthread->join();
			PrintDebug("Successfully joined query thread", 3);
		}
		
		if (!defined($rthread) || !$rthread->is_running())
		{
			PrintDebug("Rcon thread is not running", 3)
		}
		else
		{
			PrintDebug("Sending kill to rcon thread queue", 3);
			$g_rconqueue->enqueue('kill');
			PrintDebug("Attempting to join rcon thread", 3);
			my $res = $rthread->join();
			PrintDebug("Successfully joined rcon thread", 3);
		}
	}
	
	return;
}

sub SubmitCrashOrWarning
{
	PrintDebug("Entered SubmitCrashOrWarning", 5);
	my $type = shift;
	my $ua = LWP::UserAgent->new;
	
	my $error = "";
	foreach (@_)
	{
		$error .= $_."\n";
	}
	
	my $statsaddress = "";
	if (defined($g_servers{$s_addr}))
	{
		$statsaddress = $g_servers{$s_addr}->{hlstats_url};
	}
	
	my $daemonhashes = "";
	foreach (@hlxceFileNames)
	{
		open(my $FILE, '<', $opt_libdir."/".$_);
		my $shortname = $_;
		$shortname =~ tr/_//d;
		$shortname =~ s/\.p(?:l|m)$//;
		my $ctx = Digest::MD5->new;
		$ctx->addfile($FILE);
		$daemonhashes .= sprintf("%s:%s;", $shortname, $ctx->hexdigest);
		close($FILE);
	}
	
	my $content = [
		type => $type,
		time => time(),
		address => $s_addr,
		version => $HLstats_Common::version,
		dbversion => $g_dbversion,
		error => $error,
		statsaddress => $statsaddress,
		daemonhashes => $daemonhashes,
		lastlog => $s_output,
		perlversion => $]
	];
	
	my $req = HTTP::Request::Common::POST('http://master.hlxce.com/crashupload.php', $content);
	$ua->request($req);
	
	if ($type == 1)
	{
		PrintEvent("HLSTATSX", "Submitted Crash Report to master.hlxce.com");
	}
	elsif ($type == 2)
	{
		PrintEvent("HLSTATSX", "Submitted Warning Report to master.hlxce.com");
	}
	
	return;
}

