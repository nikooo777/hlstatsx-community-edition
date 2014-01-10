package HLstats_Server;
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

use POSIX;
use IO::Socket;
use Socket;
use Encode;

use strict;
use warnings;

do "$::opt_libdir/HLstats_GameConstants.plib";

my %gamelookuphash = (
		"css" => CSS(),
		"hl2mp" => HL2MP(),
		"tf" => TF(),
		"dods" => DODS(),
		"insmod" => INSMOD(),
		"ff" => FF(),
		"hidden" => HIDDEN(),
		"zps" => ZPS(),
		"aoc" => AOC(),
		"cstrike" => CSTRIKE(),
		"tfc" => TFC(),
		"dod" => DOD(),
		"ns" => NS(),
		"l4d" => L4D(),
		"fof" => FOF(),
		"ges" => GES(),
		"bg2" => BG2(),
		"sgtls" => SGTLS(),
		"dystopia" => DYSTOPIA(),
		"nts" => NTS(),
		"pvkii" => PVKII(),
		"csp" => CSP(),
		"valve" => VALVE()
);

sub new
{
	my ($class_name, $serverId, $address, $port, $server_name, $rcon_pass, $game, $publicaddress, $gameengine, $realgame, $maxplayers) = @_;
	
	my ($self) = {};
	
	bless($self, $class_name);
	
	$self->{id}             = $serverId;
	$self->{address}        = $address;
	$self->{port}           = $port;
	$self->{game}           = $game;
	$self->{rcon}           = $rcon_pass;
	$self->{srv_players}    = ();
	$self->{log_secret_match} = undef;
	
	# Game Engine
	# HL1 - 1
	# HL2 (original) - 2
	# HL2ep2 ("OrangeBox") - 3
	$self->{game_engine}    = $gameengine;
	
	$self->{rcon_obj}       = undef;
	$self->{name}           = $server_name;
	$self->{auto_ban}       = 0;
	$self->{contact}        = "";
	$self->{hlstats_url}    = "";
	$self->{publicaddress}  = $publicaddress;
	$self->{play_game}      = UNKNOWN();
	
	$self->{last_event}     = 0;
	$self->{last_check}     = 0;
	
	$self->{lines}          = 0;
	$self->{map}            = "";
	$self->{numplayers}     = 0;
	$self->{num_trackable_players} = 0;
	$self->{minplayers}     = 6;
	$self->{maxplayers}     = $maxplayers;
	$self->{difficulty}     = 0;
	
	$self->{players}        = 0;
	$self->{rounds}         = 0;
	$self->{kills}          = 0;
	$self->{suicides}       = 0;
	$self->{headshots}      = 0;
	$self->{ct_shots}       = 0;
	$self->{ct_hits}        = 0;
	$self->{ts_shots}       = 0;
	$self->{ts_hits}        = 0;
	$self->{bombs_planted}  = 0;
	$self->{bombs_defused}  = 0;
	$self->{ct_wins}        = 0;
	$self->{ts_wins}        = 0; 
	$self->{map_started}    = time();
	$self->{map_changes}    = 0;
	$self->{map_rounds}     = 0;
	$self->{map_ct_wins}    = 0;
	$self->{map_ts_wins}    = 0; 
	$self->{map_ct_shots}   = 0;
	$self->{map_ct_hits}    = 0;
	$self->{map_ts_shots}   = 0; 
	$self->{map_ts_hits}    = 0;

	# team balancer
	$self->{ba_enabled}     = 0;
	$self->{ba_ct_wins}     = 0;
	$self->{ba_ts_win}      = 0;
	$self->{ba_ct_frags}    = 0;
	$self->{ba_ts_frags}    = 0;
	$self->{ba_winner}      = ();
	$self->{ba_map_rounds}  = 0;
	$self->{ba_last_swap}   = 0;
	$self->{ba_player_switch} = 0;  # player switched on his own
	
	# Messaging commands
	$self->{show_stats}                     = 0;
	$self->{broadcasting_events}            = 0;
	$self->{broadcasting_player_actions}    = 0;
	$self->{broadcasting_command}           = "";
	$self->{broadcasting_command_announce}  = "say";
	$self->{player_events}                  = 1; 
	$self->{player_command}                 = "say";
	$self->{player_command_osd}             = "";
	$self->{player_command_hint}            = "";
	$self->{player_admin_command}           = 0;
	$self->{default_display_events}         = 1;
	$self->{browse_command}                 = "";
	$self->{swap_command}                   = "";
	$self->{exec_command}                   = "";
	$self->{global_chat_command}            = "say";
	
	# Message format operators
	$self->{format_color}             = "";
	$self->{format_action}            = "";
	$self->{format_actionend}         = "";
	
	$self->{total_kills}              = 0;
	$self->{total_headshots}          = 0;
	$self->{total_suicides}           = 0;
	$self->{total_rounds}             = 0;
	$self->{total_shots}              = 0;
	$self->{total_hits}               = 0;
	
	$self->{track_server_load}       = 0;
	$self->{track_server_timestamp}  = 0;
	
	$self->{ignore_nextban}          = ();
	$self->{use_browser}             = 0;
	$self->{round_status}            = 0;
	$self->{min_players_rank}        = 1;
	$self->{admins}                  = ();
	$self->{ignore_bots}             = 1;
	$self->{tk_penalty}              = 0;
	$self->{suicide_penalty}         = 0;
	$self->{skill_mode}              = 0;
	$self->{game_type}               = 0;
	$self->{bonusroundignore}        = 0;
	$self->{bonusroundtime}          = 0;
	$self->{bonusroundtime_ts}       = 0;
	$self->{bonusroundtime_state}    = 0;
	$self->{lastdisabledbonus}       = $::ev_unixtime;
	$self->{mod}                     = "";
	$self->{switch_admins}           = 0;
	$self->{public_commands}         = 1;
	$self->{connect_announce}        = 1;
	$self->{update_hostname}         = 0;
	
	$self->{lastblueflagdefend}      = 0;
	$self->{lastredflagdefend}       = 0;
	
	# location hax
	$self->{nextkillx}               = "";
	$self->{nextkilly}               = "";
	$self->{nextkillz}               = "";
	$self->{nextkillvicx}            = "";
	$self->{nextkillvicy}            = "";
	$self->{nextkillvicz}            = "";
	
	$self->{nextkillheadshot}        = 0;
	
	$self->{next_timeout}            = 0;
	$self->{next_flush}              = 0;
	$self->{next_plyr_flush}         = 0;
	$self->{needsupdate}             = 0;
	
	$self->{play_game} =  $gamelookuphash{$realgame};
	
	if (!$::g_stdin && $self->{rcon})
	{
		$self->init_rcon();
	}
	
	$self->updateDB();
	$self->update_server_loc();

	return $self;
}

sub set_play_game
{
	my ($self, $realgame) = @_;
	
	if (defined($gamelookuphash{$realgame}))
	{
		$self->{play_game} = $gamelookuphash{$realgame};
	}
	
	return;
}

sub is_admin
{
	my($self, $steam_id) = @_;
	for (@{$self->{admins}}) {
		if ($_ eq $steam_id) {
			return 1;
		}
	}
	return 0;
}

sub get_game_mod_opts
{
	# Runs immediately after server object is created and options are loaded.
	my ($self) = @_;

	if ($self->{mod} ne "") {
		my $mod = $self->{mod};
			
		if ($mod eq "SOURCEMOD") {
			$self->{browse_command} = "hlx_sm_browse";
			$self->{swap_command} = "hlx_sm_swap";
			$self->{global_chat_command} = "hlx_sm_psay";
			$self->setHlxCvars();
		} elsif ($mod eq "MANI") {
			$self->{browse_command} = "ma_hlx_browse";
			$self->{swap_command} = "ma_swapteam";
			$self->{exec_command} = "ma_cexec";
			$self->{global_chat_command} = "ma_psay";
		} elsif ($mod eq "AMXX") {
			$self->{browse_command} = "hlx_amx_browse";
			$self->{swap_command} = "hlx_amx_swap";
			$self->{global_chat_command} = "hlx_amx_psay";
			$self->setHlxCvars();
		} elsif ($mod eq "BEETLE") {
			$self->{browse_command} = "hlx_browse";
			$self->{swap_command} = "hlx_swap";
			$self->{exec_command} = "hlx_exec";
			$self->{global_chat_command} = "admin_psay";
		} elsif ($mod eq "MINISTATS") {
			$self->{browse_command} = "ms_browse";
			$self->{swap_command} = "ms_swap";
			$self->{global_chat_command} = "ms_psay";
		}
		
		# Turn on color and add game-specific color modifiers for when using hlx:ce sourcemod plugin
#		if (($self->{mod} eq "SOURCEMOD" &&
#				(
#				$self->{play_game} == CSS()
#				|| $self->{play_game} == TF()
#				|| $self->{play_game} == L4D()
#				|| $self->{play_game} == DODS()
#				|| $self->{play_game} == HL2MP()
#				|| $self->{play_game} == AOC()
#				|| $self->{play_game} == ZPS()
#				|| $self->{play_game} == FF()
#				|| $self->{play_game} == GES()
#				|| $self->{play_game} == FOF()
#				|| $self->{play_game} == PVKII()
#				|| $self->{play_game} == CSP()
#				)
#			)
#			|| ($self->{mod} eq "AMXX"
#				&& $self->{play_game} == CSTRIKE())
#		) {
#	
#			$self->{format_color} = " 1";
#			if ($self->{play_game} == ZPS() || $self->{play_game} == GES()) {
#				$self->{format_action} = "\x05";
#			} elsif ($self->{play_game} == FF()) {
#				$self->{format_action} = "^4";
#			} else {
#				$self->{format_action} = "\x04";
#			}
#			
#			if ($self->{play_game} == FF()) {
#				$self->{format_actionend} = "^0";
#			} else {
#				$self->{format_actionend} = "\x01";
#			}
#		}
		# Insurgency can only do one solid color afaik. The rest is handled in the plugin
		#if ($self->{mod} eq "SOURCEMOD" && $self->{play_game} == INSMOD()) {
			#$self->{format_color} = "1";
		#}
	}
	
	return;
}

sub FormatUserId
{
	### This needs to go away. There's no reason the AMXX plugin can't use same format if edited
	my ($self, $userid) = @_;
	if ($self->{mod} eq "AMXX")
	{
		return "#$userid";
	}
	return "\"$userid\"";
}

sub EscapeRconArg
{
	my ($self, $message) = @_;
	$message =~ s/'/ ' /g;
	$message =~ s/"/ '' /g;
	
	if (($self->{game_engine} != 2 || $self->{mod} eq "SOURCEMOD") && $self->{mod} ne "MANI")
	{
		return "\"$message\"";
	}
	return $message;
}

#
# Increment (or decrement) the value of 'key' by 'amount' (or 1 by default)
#

sub increment
{
	my ($self, $key, $amount) = @_;
	if ($amount)
	{
		$amount = int($amount);
	}
	else
	{
		$amount = 1
	}
	
	my $value = $self->{$key};
	$self->{$key} = $value + $amount;
	
	return;
}


sub init_rcon
{
	my ($self)      = @_;
	my $server_ip   = $self->{address};
	my $server_port = $self->{port};
	my $rcon_pass   = $self->{rcon};

	if ($::g_rcon && $rcon_pass)
	{
		if ($self->{game_engine} == 1)
		{
			$self->{rcon_obj} = BASTARDrcon->new($server_ip, $server_port, $rcon_pass);
		}
		else
		{
			$self->{rcon_obj} = TRcon->new($server_ip, $server_port, $rcon_pass, $self->{play_game});
		}
	}
   	if ($self->{rcon_obj})
	{
		&::PrintEvent ("SERVER", "Connecting to rcon on $server_ip:$server_port ... ok");
		#::PrintEvent("SERVER", "Server running game: ".$self->{play_game}, 1);
		&::PrintEvent("SERVER", "Server running map: ".$self->get_map(), 1);
		if ($::g_mode == TRACKMODE_LAN())
		{
			$self->get_lan_players();
		}
	}
	
	# Also need to init queues rcon objs
	$::g_rconqueue->enqueue(2);
	$::g_rconqueue->enqueue($self->{id});
	$::g_rconqueue->enqueue($self->{game_engine}, $self->{address}, $self->{port}, $self->{rcon}, $self->{play_game});
	return;
}

sub DoRcon
{
	my ($self, $command, $sendQueued) = @_;
    my $result;
    my $rcon_obj = $self->{rcon_obj};
	if (!$rcon_obj || $::g_rcon == 0 || $self->{rcon} eq "")
	{
		&::PrintNotice("Rcon error: No Object available");
		return;
	}
	 
	# replace ; to avoid executing multiple rcon commands.
	$command  =~ tr/;//d;
	
	&::PrintNotice("RCON", $command, 1);
	
	if ($sendQueued)
	{
		$self->__DoQueuedRcon($command);
		return;
	}
	$result = $rcon_obj->execute($command);

	return $result;
}

sub DoRconMulti
{
	my ($self, $commands, $sendQueued) = @_;
	my $result;
	my $rcon_obj = $self->{rcon_obj};
	if (!$rcon_obj || $::g_rcon == 0 || $self->{rcon} eq "")
	{
		&::PrintNotice("Rcon error: No Object available");
		return;
	}
	
	if ($self->{game_engine} > 1)
	{
		my $fullcmd = "";
		foreach (@$commands)
		{
			# replace ; to avoid executing multiple rcon commands.
			my $cmd = $_;
			$cmd =~ tr/;//d;
			$fullcmd .="$cmd;";
		}
		&::PrintNotice("RCON", $fullcmd, 1);
	
		if ($sendQueued)
		{
			$self->__DoQueuedRcon($fullcmd);
			return;
		}
		
		$result = $rcon_obj->execute($fullcmd);
	}
	else
	{
		foreach (@$commands)
		{
			&::PrintNotice("RCON", $_, 1);
			
			if ($sendQueued)
			{
				$self->__DoQueuedRcon($_);
				next;
			}
		
			$result = $rcon_obj->execute($_);
		}
	}
	
	return $result;
}

sub rcon_getaddress
{
	my ($self, $uniqueid) = @_;
	my $result = undef;
	my $rcon_obj = $self->{rcon_obj};
	if (($rcon_obj) && ($::g_rcon == 1) && ($self->{rcon} ne ""))
	{
		$result = $rcon_obj->getPlayer($uniqueid);
	}
	else
	{
		::PrintNotice("Rcon error: No Object available");
	}
	return $result;
}

sub rcon_getStatus
{
	my ($self) = @_;
    my $rcon_obj = $self->{rcon_obj};
    my $map_result = "";
    my $max_player_result = -1;
	my $servhostname = "";
	my $difficulty = 0;
	
	if (($rcon_obj) && ($::g_rcon == 1) && ($self->{rcon} ne ""))
	{
		($servhostname, $map_result, $max_player_result, $difficulty) = $rcon_obj->GetServerData();
		my ($visible_maxplayers) = $rcon_obj->GetVisiblePlayers();
		if (($visible_maxplayers != -1) && ($visible_maxplayers < $max_player_result))
		{
			$max_player_result = $visible_maxplayers;
		}
	}
	else
	{
		&::PrintNotice("Rcon error: No Object available");
	}
	return ($map_result, $max_player_result, $servhostname, $difficulty);
}

sub rcon_getplayers
{
	my ($self) = @_;
	my %result;
	my $rcon_obj = $self->{rcon_obj};
	if (($rcon_obj) && ($::g_rcon == 1) && ($self->{rcon} ne ""))
	{
		%result = $rcon_obj->GetPlayers();
	}
	else
	{
		&::PrintNotice("Rcon error: No Object available");
	}
	return %result;
}

sub track_server_load
{
	my ($self) = @_;
	
	if ($::g_stdin || !$self->{track_server_load})
	{
		return;
	}
	
	my $last_timestamp = $self->{track_server_timestamp};
	my $new_timestamp  = time();
	
	if ($last_timestamp <= 0)
	{
		$self->{track_server_timestamp} = $new_timestamp;
		return;
	}

	if ($last_timestamp+299 >= $new_timestamp)
	{
		return;
	}

	#        print "\ntrying rcon to get fps & uptime...\n";
	# fetch fps and uptime via rcon
	#$statsOutput = "          0.00  0.00  0.00      54     1  249.81       0 dhjdsk";
	my $statsOutput = $self->DoRcon("stats");
	my $uptime = 0;
	my $fps = 0;
	
	#		$string =~ /.*\n(.*)\Z/;
	if ($statsOutput && $statsOutput =~ /CPU.*\n(.*)\n*L?.*\Z/)
	{
		$statsOutput = $1;
		$statsOutput =~ s/[\s\s]{2,10}/ /g;
		if ($statsOutput =~ /([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+)+/)
		{
			$uptime = $4;
			$fps = $6;
		}
	}
	
	my $act_players  = $self->{numplayers};
	my $max_players  = $self->{maxplayers};
	if ($max_players > 0 && $act_players > $max_players)
	{
		$act_players = $max_players;
	}
	
	my $query = "
		INSERT IGNORE INTO
			hlstats_server_load
		SET
			server_id=?,
			timestamp=?,
			act_players=?,
			min_players=?,
			max_players=?,
			map=?,
			uptime=?,
			fps=?
	";
	
	my $vals = [$self->{id}, $new_timestamp, $act_players, $self->{minplayers},
				$max_players, $self->{map}, (($uptime)?$uptime:0), (($fps)?$fps:0)];
	
	$::g_queryqueue->enqueue("server_insert_load");
	$::g_queryqueue->enqueue($query);
	$::g_queryqueue->enqueue($vals);
	
	$self->{track_server_timestamp} = $new_timestamp;
	&::PrintEvent("SERVER", "Insert new server load timestamp", 1);
	
	return;
}

sub dostats 
{
	my ($self) = @_;
	my $rcon_obj = $self->{rcon_obj};

	if ($::g_stdin || !$rcon_obj || !$self->{rcon} || !$self->{broadcasting_events})
	{
		return;
	}
	
	my $rcmd = $self->{broadcasting_command_announce};
	my $hpk = sprintf("%.0f", 0);
	if ($self->{total_kills} > 0) {
		$hpk = sprintf("%.2f", (100/$self->{total_kills})*$self->{total_headshots});
	}  
	
	if ($rcmd ne "")
	{
		$self->DoRcon("$rcmd ".$self->EscapeRconArg("HLstatsX:CE - Tracking ".::FormatNumber($self->{players})." players with ".::FormatNumber($self->{total_kills})." kills and ".::FormatNumber($self->{total_headshots})." headshots ($hpk%)"));
	}
	else
	{
		$self->MessageAll("HLstatsX:CE - Tracking ".::FormatNumber($self->{players})." players with ".::FormatNumber($self->{total_kills})." kills and ".::FormatNumber($self->{total_headshots})." headshots ($hpk%)");
	}
	
	return;
}

sub get_map
{
	my ($self, $fromupdate) = @_;

	if ($::g_stdin == 0)
	{
		if ((time() - $self->{last_check})>120)
		{
			$self->{last_check} = time();
			&::PrintNotice("get_rcon_status");
			my $temp_map         = "";
			my $temp_maxplayers  = -1;
			my $servhostname     = "";
			my $difficulty       = 0;
			my $update           = 0;
			
			if ($self->{rcon_obj})
			{
				($temp_map, $temp_maxplayers, $servhostname, $difficulty) = $self->rcon_getStatus();
				
				if ($temp_map eq "")
				{
					goto STATUSFAIL;
				}
					
				
				if ($self->{map} ne $temp_map)
				{
					$self->{map} = $temp_map;
					$update++;
				}
				
				if ($temp_maxplayers > 0 && $self->{maxplayers} != $temp_maxplayers)
				{
					$self->{maxplayers} = $temp_maxplayers;
					$update++;
				}
				
				if ($difficulty > 0 && $self->{play_game} == L4D())
				{
					$self->{difficulty} = $difficulty;
				}
				
				if ($self->{update_hostname} > 0 && $servhostname ne "" && $self->{name} ne $servhostname)
				{
					$self->{name} = $servhostname;
					$update++;
				}
			}
			else
			{
				STATUSFAIL:
				($temp_map, $temp_maxplayers, $servhostname) = &::queryServer($self->{address}, $self->{port}, 'mapname', 'maxplayers', 'hostname');
				
				if ($temp_map ne "" && $self->{map} ne $temp_map)
				{
					$self->{map} = $temp_map;
					$update++;
				}
				
				if ($temp_maxplayers > 0 && $self->{maxplayers} != $temp_maxplayers)
				{
					$self->{maxplayers} = $temp_maxplayers;
					$update++;
				}
				
				if ($self->{update_hostname} > 0 && $servhostname ne "" && $self->{name} ne $servhostname)
				{
					$self->{name} = $servhostname;
					$update++;
				}
			}
				
			if ($update > 0 && (!defined($fromupdate) || $fromupdate > 0))
			{
				$self->updateDB();
			}
		  
			&::PrintNotice("get_rcon_status successfully");
		}
	}  
	return $self->{map};
}


sub update_players_pings
{
	my ($self) = @_;

	if ($self->{num_trackable_players} < $self->{minplayers}) 
	{
		&::PrintNotice("(IGNORED) NOTMINPLAYERS: Update_player_pings");
		return;
	}

	&::PrintNotice("update_player_pings");
	&::PrintEvent("RCON", "Update Player pings", 1);

	my %players = $self->rcon_getplayers();
	while ( my($pl, $player) = each(%{$self->{srv_players}}) )
	{
		my $uniqueid = $player->{uniqueid};
		if (defined($players{$uniqueid})
			&& $player->{is_bot} == 0 && $player->{userid} > 0
			) 
		{
			my $ping = $players{$uniqueid}->{"Ping"};
			$player->set("ping", $ping);
			if ($ping > 0)
			{
				&::RecordEvent(
					"Latency", 0,
					$player->{playerid},
					$ping
				);
			}
		}
	}
	
	&::PrintNotice("update_player_pings successfully");
	
	return;
}

sub get_lan_players
{
	my ($self) = @_;
	
	&::PrintNotice("get_lan_players");
	&::PrintEvent("RCON", "Get LAN players", 1);
	my %players = $self->rcon_getplayers();
	while ( my($p_uid, $p_obj) = each(%players) )
	{	
		my $srv_addr = $self->{address}.":".$self->{port};
		my $userid   = $p_obj->{"UserID"};
		my $name     = $p_obj->{"Name"};
		my $address  = $p_obj->{"Address"};
		$::g_lan_noplayerinfo{"$srv_addr/$userid/$name"} = {
			ipaddress => $address,
			userid => $userid,
			name => $name,
			server => $srv_addr
		};
	}
	&::PrintNotice("get_lan_players successfully");
	
	return;
}

sub clear_winner
{
	my ($self) = @_;
	&::PrintNotice("clear_winner");
	@{$self->{winner}} = ();
	
	return;
}

sub add_round_winner
{
	my ($self, $team) = @_;
  
	&::PrintNotice("add_round_winner");
	$self->{winner}[($self->{map_rounds} % 7)] = $team;
	$self->increment("ba_map_rounds");
	$self->increment("map_rounds");
	$self->increment("rounds");
	$self->increment("total_rounds");
  
	$self->{ba_ct_wins} = 0;
	$self->{ba_ts_wins} = 0;
  
	for (@{$self->{winner}}) 
	{
		if ($_ eq "ct")
		{
			$self->increment("ba_ct_wins");
		}
		elsif
		($_ eq "ts")
		{
			$self->increment("ba_ts_wins");
		}
	}
	
	return;
}

sub switch_player
{
	my ($self, $playerid, $name) = @_;
	my $rcmd = $self->{player_command_hint};
	
	$self->DoRcon($self->{swap_command}." ".$self->FormatUserId($playerid));
	if ($self->{player_command_hint} eq "")
	{
		$rcmd = $self->{player_command};
	}
	$self->DoRcon(sprintf("%s %s %s", $rcmd, $self->FormatUserId($playerid), $self->EscapeRconArg("HLstatsX:CE - You were switched to balance teams")));
	if ($self->{player_admin_command} ne "")
	{
		$self->DoRcon(sprintf("%s %s",$self->{player_admin_command}, $self->EscapeRconArg("HLstatsX:CE - $name was switched to balance teams")));
	}
	
	return;
}


sub analyze_teams
{
	my ($self) = @_;
  
	return if ($::g_stdin == 1);	
	return if ($self->{ba_enabled} == 0);
	
	if ($self->{num_trackable_players} < $self->{minplayers})
	{
		&::PrintNotice("(IGNORED) NOTMINPLAYERS: analyze_teams");
		return;
	}

	&::PrintNotice("analyze_teams");
	my $ts_skill     = 0;
	my $ts_avg_skill = 0;
	my $ts_count     = 0;
	my $ts_wins      = $self->{ba_ts_wins};
	my $ts_kills     = 0;
	my $ts_deaths    = 0;
	my $ts_diff      = 0;
	my @ts_players   = ();

	my $ct_skill     = 0;
	my $ct_avg_skill = 0;
	my $ct_count     = 0;
	my $ct_wins      = $self->{ba_ct_wins};
	my $ct_kills     = 0;
	my $ct_deaths    = 0;
	my $ct_diff      = 0;
	my @ct_players   = ();
	
	my $server_id   = $self->{id};
	while ( my($pl, $player) = each(%{$self->{srv_players}}) )
	{	
		my @Player      = ( $player->{name},        #0
							$player->{uniqueid},    #1
							$player->{skill},       #2
							$player->{team},        #3
							$player->{map_kills},   #4
							$player->{map_deaths},  #5
							($player->{map_kills}-$player->{map_deaths}), #6
							$player->{is_dead},	    #7
							$player->{userid},      #8
							);

		if ($Player[3] eq "TERRORIST")
		{
			push(@{$ts_players[$ts_count]}, @Player);
			$ts_skill   += $Player[2]; 
			$ts_count   += 1;
			$ts_kills   += $Player[4];
			$ts_deaths  += $Player[5];
		}
		elsif ($Player[3] eq "CT")
		{
			push(@{$ct_players[$ct_count]}, @Player);
			$ct_skill   += $Player[2]; 
			$ct_count   += 1;
			$ct_kills   += $Player[4]; 
			$ct_deaths  += $Player[5]; 
		}
	}
	@ct_players = sort { $b->[6] <=> $a->[6]} @ct_players;
	@ts_players = sort { $b->[6] <=> $a->[6]} @ts_players;

	&::PrintEvent("TEAM", "Checking Teams", 1);
	my $admin_msg = "AUTO-TEAM BALANCER: CT ($ct_count) $ct_kills:$ct_deaths  [$ct_wins - $ts_wins] $ts_kills:$ts_deaths ($ts_count) TS";
	if ($self->{player_events} == 1)  
	{
		if ($self->{player_admin_command} ne "")
		{
			my $cmd_str = $self->{player_admin_command}." $admin_msg";
			$self->DoRcon($cmd_str);
		}  
	}

	$self->MessageAll("HLstatsX:CE - ATB - Checking Teams", 0, 1);

	if ($self->{ba_map_rounds} >= 2)    # need all players for numerical balacing, at least 2 for getting all players
	{
		my $action_done = 0;
		if ($self->{ba_last_swap} > 0)
		{
			$self->{ba_last_swap}--;
		}
  
		if ($ct_count + 1 < $ts_count)         # ct need players
		{
			my $needed_players = floor( ($ts_count - $ct_count) / 2);
			if ($ct_wins < 2)
			{
				@ts_players = sort { $b->[7] <=> $a->[7]} @ts_players;
			}
			else
			{
				@ts_players = sort { $a->[7] <=> $b->[7]} @ts_players;
			}
			foreach my $entry (@ts_players) 
			{
				if ($needed_players > 0 # how many we need to make teams even (only numerical)
					&& @{$entry}[7] == 1   # only dead players!!
					&& ($self->{switch_admins} == 1 || ($self->{switch_admins} == 0 && $self->is_admin(@{$entry}[1]) == 0))
					)
				{
					$self->switch_player(@{$entry}[8], @{$entry}[0]); 
					$action_done++;
					$needed_players--;
				}
			}
		}
		elsif  ($ts_count + 1 < $ct_count)  # ts need players
		{
			my $needed_players = floor( ($ct_count - $ts_count) / 2);
			if ($ts_wins < 2)
			{
				@ct_players = sort { $b->[6] <=> $a->[6]} @ct_players;  # best player
			}
			else
			{
				@ct_players = sort { $a->[6] <=> $b->[6]} @ct_players;  # worst player
			}
			foreach my $entry (@ct_players) 
			{
				if ($needed_players > 0  # how many we need to make teams even (only numerical)
					&& @{$entry}[7] == 1  # only dead players!!
					&& ($self->{switch_admins} == 1 || ($self->{switch_admins} == 0 && $self->is_admin(@{$entry}[1]) == 0)))
				{
					$self->switch_player(@{$entry}[8], @{$entry}[0]); 
					$action_done++;
					$needed_players--;
				}
			}
		}
  
		if (($action_done == 0) && ($self->{ba_last_swap} == 0) && ($self->{ba_map_rounds} >= 7) && ($self->{ba_player_switch} == 0)) # frags balancing (last swap 3 rounds before)
		{
			if ($ct_wins < 2)
			{
				if ($ct_count < $ts_count)     # one player less we dont need swap just bring one over
				{
					my $ts_found = 0;
					@ts_players = sort { $b->[6] <=> $a->[6]} @ts_players;  # best player
					foreach my $entry (@ts_players) 
					{
						if ($ts_found == 0
							&& @{$entry}[7] == 1  # only dead players!!
							&& ($self->{switch_admins} == 1 || ($self->{switch_admins} == 0 && $self->is_admin(@{$entry}[1]) == 0))
							)
						{
							$self->{ba_last_swap} = 3;
							$self->switch_player(@{$entry}[9], @{$entry}[0]); 
							$ts_found++;
						}
					}
				}
				else                  # need to swap to players
				{
					my $ts_playerid = 0;
					my $ts_name     = "";
					my $ts_kills    = 0;
					my $ts_deaths   = 0;
					my $ct_playerid = 0;
					my $ct_name     = "";
					my $ct_kills    = 0;
					my $ct_deaths   = 0;
					my $ts_found = 0;
					@ts_players = sort { $b->[6] <=> $a->[6]} @ts_players;  # best player
					foreach my $entry (@ts_players) 
					{
						if ($ts_found == 0
							&& @{$entry}[7] == 1  # only dead players!!
							&& ($self->{switch_admins} == 1 || ($self->{switch_admins} == 0 && $self->is_admin(@{$entry}[1]) == 0))
							)
						{
							$ts_playerid = @{$entry}[8];
							$ts_name     = @{$entry}[0];
							$ts_found++;
						}
					}

					my $ct_found = 0;
					@ct_players = sort { $a->[6] <=> $b->[6]} @ct_players;  # worst player
					foreach my $entry (@ct_players) 
					{
						if ($ct_found == 0
							&& @{$entry}[7] == 1  # only dead players!!
							&& ($self->{switch_admins} == 1 || ($self->{switch_admins} == 0 && $self->is_admin(@{$entry}[1]) == 0))
							)
						{
							$ct_playerid = @{$entry}[8];
							$ct_name     = @{$entry}[0];
							$ct_found++;
						}
					}
					if ($ts_found > 0 && $ct_found > 0)
					{
						$self->{ba_last_swap} = 3;
						$self->switch_player($ts_playerid, $ts_name); 
						$self->switch_player($ct_playerid, $ct_name); 
					}
				}
			}
			elsif ($ts_wins < 2)
			{
				if ($ts_count < $ct_count)     # one player less we dont need swap just bring one over
				{
					my $ct_found = 0;
					@ct_players = sort { $b->[6] <=> $a->[6]} @ct_players;  # best player
					foreach my $entry (@ct_players) 
					{
						if ($ct_found == 0
							&& @{$entry}[7] == 1  # only dead players!!
							&& ($self->{switch_admins} == 1 || ($self->{switch_admins} == 0 && $self->is_admin(@{$entry}[1]) == 0))
							)
						{
							$self->{ba_last_swap} = 3;
							$self->switch_player(@{$entry}[8], @{$entry}[0]); 
							$ct_found++;
						}
					}
				}
				else                  # need to swap to players
				{
					my $ts_playerid  = 0;
					my $ts_name      = "";
					my $ct_playerid  = 0;
					my $ct_name      = "";
					my $ct_found = 0;
					@ct_players = sort { $b->[6] <=> $a->[6]} @ct_players;  # best player
					foreach my $entry (@ct_players) 
					{
						if ($ct_found == 0
							&& @{$entry}[7] == 1  # only dead players!!
							&& ($self->{switch_admins} == 1 || ($self->{switch_admins} == 0 && $self->is_admin(@{$entry}[1]) == 0))
							)
						{
							$ct_playerid = @{$entry}[8];
							$ct_name     = @{$entry}[0];
							$ct_found++;
						}
					}

					my $ts_found = 0;
					@ts_players = sort { $a->[6] <=> $b->[6]} @ts_players;  # worst player
					foreach my $entry (@ts_players) 
					{
						if ($ts_found == 0
							&& @{$entry}[7] == 1  # only dead players!!
							&& ($self->{switch_admins} == 1 || ($self->{switch_admins} == 0 && $self->is_admin(@{$entry}[1]) == 0))
							)
						{
							$ts_playerid = @{$entry}[8];
							$ts_name     = @{$entry}[0];
							$ts_found++;
						}
					}
					if ($ts_found > 0 && $ct_found > 0)
					{
						$self->{ba_last_swap} = 3;
						$self->switch_player($ts_playerid, $ts_name); 
						$self->switch_player($ct_playerid, $ct_name); 
					}
				}
			}
		}
	} # end if rounds > 1
	
	return;
}

#
# Marks server as needing flush
#

sub updateDB
{
	my ($self) = @_;
	$self->{needsupdate} = 1;
}

#
# Flushes server information in database
#

sub flushDB
{
	my ($self) = @_;
   	$self->get_map(1);
	
	my $serverid = $self->{id};

    if ($self->{total_kills} == 0)
    {
		my $query = "
			SELECT kills, headshots, suicides, rounds, ct_shots+ts_shots as shots, ct_hits+ts_hits as hits
			FROM hlstats_Servers
			WHERE serverId=?
		";
		my $result = $::g_db->DoCachedQuery("server_select_stats", $query, [$serverid]);
		
		($self->{total_kills}, $self->{total_headshots}, $self->{total_suicides},$self->{total_rounds},$self->{total_shots},$self->{total_hits}) = $result->fetchrow_array();
		$result->finish;
	}   

	my $query = "
		SELECT count(playerId) as players
		FROM hlstats_Players
		WHERE game=? and hideranking<>2
	";
	my $result = $::g_db->DoCachedQuery("server_select_players", $query, [$self->{game}]);
	
	$self->{players} = $result->fetchrow_array();
	$result->finish;
	
	
	# Update player details
	$query = "
		UPDATE
			hlstats_Servers
		SET  
			name=?,
		    rounds=rounds + ?,
			kills=kills + ?,
			suicides=suicides + ?,
			headshots=headshots + ?,
			bombs_planted=bombs_planted + ?,
			bombs_defused=bombs_defused + ?,
			players=?,
			ct_wins=ct_wins + ?,
			ts_wins=ts_wins + ?,
			act_players=?,
			max_players=?,
			act_map=?,
			map_rounds=?,
			map_ct_wins=?,
			map_ts_wins=?,
			map_started=?,
			map_changes=map_changes+?,
			ct_shots=ct_shots + ?,
			ct_hits=ct_hits + ?,
			ts_shots=ts_shots + ?,
			ts_hits=ts_hits + ?,
			map_ct_shots=?,
			map_ct_hits=?,
			map_ts_shots=?,
			map_ts_hits=?,
			last_event=?
		WHERE
			serverId=?
	";
	my $vars = [$self->{name}, $self->{rounds}, $self->{kills}, $self->{suicides}, $self->{headshots}, $self->{bombs_planted},
		$self->{bombs_defused}, $self->{players}, $self->{ct_wins}, $self->{ts_wins}, $self->{numplayers}, $self->{maxplayers},
		$self->{map}, $self->{map_rounds}, $self->{map_ct_wins}, $self->{map_ts_wins}, $self->{map_started}, $self->{map_changes},
		$self->{ct_shots}, $self->{ct_hits}, $self->{ts_shots}, $self->{ts_hits}, $self->{map_ct_shots}, $self->{map_ct_hits},
		$self->{map_ts_shots}, $self->{map_ts_hits}, $::ev_unixtime, $serverid];
	
	$::g_db->DoCachedQuery("server_update_server", $query, $vars);

	$self->{rounds} = 0;
	$self->{kills} = 0;
	$self->{suicides} = 0;
	$self->{headshots} = 0;
	$self->{bombs_planted} = 0;
	$self->{bombs_defused} = 0;
	$self->{ct_wins} = 0;
	$self->{ts_wins} = 0;
	$self->{ct_shots} = 0;
	$self->{ct_hits} = 0;
	$self->{ts_shots} = 0;
	$self->{ts_hits} = 0;
	$self->{map_changes} = 0;
	$self->{needsupdate} = 0;
	
	return;
}

sub flush_player_count
{
	my ($self) = @_;
	
	$::g_db->DoCachedQuery("flush_plyr_cnt",
		"UPDATE hlstats_Servers SET act_players=? WHERE serverId=?", [$self->{numplayers}, $self->{id}]);
	
	return;
}

sub update_server_loc
{
	my ($self)      = @_;
	my $serverid    = $self->{id};
    my $server_ip   = $self->{address};
	my $publicaddress = $self->{publicaddress};

	if ($publicaddress =~ /^(\d+\.\d+\.\d+\.\d+)/) {
		$server_ip = $publicaddress;
	} elsif ($publicaddress =~ /^([0-9a-zA-Z\-\.]+)\:*.*/) {
		my $hostip = inet_aton($1);
		if ($hostip) {
			$server_ip = inet_ntoa($hostip);
		}
	}
	my $found = 0;
	my $servcity = "";
	my $servcountry = "";
	my $servlat=undef;
	my $servlng=undef;
	if ($::g_geoip_binary > 0) {
		if(!defined($::g_gi)) {
			return;
		}
		my ($country_code, $country_code3, $country_name, $region, $city, $postal_code, $latitude, $longitude,
$metro_code, $area_code) = $::g_gi->get_city_record($server_ip);
		if ($longitude) {
			$found++;
			$servcity = ((defined($city))?encode("utf8",$city):"");
			$servcountry = ((defined($country_name))?encode("utf8",$country_name):"");
			$servlat = $latitude;
			$servlng = $longitude;
		}
	} else {
		my @ipp = split (/\./,$server_ip);
		my $ip_number = $ipp[0]*16777216+$ipp[1]*65536+$ipp[2]*256+$ipp[3];
		my $query = "
			SELECT locId FROM geoLiteCity_Blocks WHERE startIpNum<= $ip_number AND endIpNum>= $ip_number LIMIT 1";
		my $result = $::g_db->DoQuery($query);
		if ($result->rows > 0) {
			my $locid = $result->fetchrow_array;
			$result->finish;
			my $query = "
				SELECT
					city,
					name AS country,
					latitude AS lat,
					longitude AS lng
				FROM
					geoLiteCity_Location a 
				INNER JOIN
					hlstats_Countries b ON a.country=b.flag
				WHERE
					locId= $locid
				LIMIT 1";
			my $result = $::g_db->DoQuery($query);
			if ($result->rows > 0) {
				$found++;
				($servcity,$servcountry,$servlat,$servlng) = $result->fetchrow_array;
				$result->finish;
			}
		}
	}
	if ($found > 0) {
		my $query = "
			UPDATE
				`hlstats_Servers`
			SET
				city = ?,
				country=?,
				lat=?,
				lng=?
			WHERE
				serverId = ?
		";
		my $vals = [(defined($servcity)?$servcity:""),  # no NULLs allow
				(defined($servcountry)?$servcountry:""),  # no NULLs allow
				$servlat,
				$servlng,
				$serverid];
		
		$::g_queryqueue->enqueue("server_update_geodata");
		$::g_queryqueue->enqueue($query);
		$::g_queryqueue->enqueue($vals);
	}
	
	return;
}

sub MessageAll
{
	my ($self, $msg, $noshow, $force) = @_;
	
	if (!$self->{broadcasting_events} &&  !$force)
	{
		return;
	}
	
	if ($self->{mod} eq "SOURCEMOD" || $self->{mod} eq "AMXX")
	{
		my @userlist;
		
		foreach my $player (values(%{$self->{srv_players}}))
		{
			if (($player->{is_bot} == 0) && ($player->{userid} > 0) && ($player->{playerid} != $noshow) && ($player->{display_events} == 1 || $force == 1))
			{
				push(@userlist, $player->{userid});
			}
		}
		
		if ($self->{play_game} != FF())
		{
			$msg = $self->{format_action}.$msg;
		}
		$self->MessageMany($msg, 1, \@userlist);
	}
	else
	{
		$self->DoRcon("say ".$msg);
	}
	
	return;
}

sub MessageMany
{
	my ($self, $msg, $toall, $userlist) = @_;
	if (!@$userlist)
	{
		return;
	}
	
	if ($self->{mod} eq "SOURCEMOD" || $self->{mod} eq "AMXX")
	{
		my $usersendlist = "";
		foreach (@$userlist)
		{
			$usersendlist .= $_.",";
		}
		$usersendlist =~ s/,$//;
		my $color = $self->{format_color};
		if ($toall > 0 && $color eq "1")
		{
			$color = "2";
		}
		$self->DoRcon($self->{player_command}." \"$usersendlist\" $color ".$self->EscapeRconArg($msg));
	}
	else
	{
		my $rcmd = $self->{broadcasting_command};
		foreach (@$userlist)
		{
			$self->DoRcon(sprintf("%s %s %s %s",$rcmd, $self->FormatUserId($_), $self->{format_color}, $self->EscapeRconArg($msg)));
		}
	}
	
	return;
}


sub setHlxCvars
{
	my ($self) = @_;

	if ($self->{hlstats_url} ne "")
	{
		$self->DoRcon("hlxce_webpage \"".$self->{hlstats_url}."\"");
	}
	$self->DoRcon("hlxce_version \"".$HLstats_Common::version."\"");
	
	if ($self->{play_game} eq "MANI" && $self->dorcon("mani_hlx_prefix" =~ /gameme/i))
	{
		$self->DoRcon("mani_hlx_prefix \"HLstatsX\"");
	}
	
	return;
}

sub updatePlayerCount
{
	my ($self) = @_;
	
	if ($::g_debug > 1)
	{
		&::PrintEvent("SERVER","Updating Player Count");
	}
	
	my $trackable = 0;

	if ($self->{play_game} == L4D())
	{
		my $num = 0;
		while (my($pl, $player) = each(%{$self->{srv_players}}))
		{
			if ($player->{trackable} == 1)
			{
				$trackable++;
			}
			if ($player->{userid} > 0)
			{
				$num++;
			}
		}
		$self->{numplayers} = $num;
		$self->{num_trackable_players} = $trackable;
	}
	else
	{
		$self->{numplayers} = scalar keys %{$self->{srv_players}};
		while (my($pl, $player) = each(%{$self->{srv_players}}))
		{
			if ($player->{trackable} == 1)
			{
				$trackable++;
			}
		}
		$self->{num_trackable_players} = $trackable;
	}
	
	$self->flush_player_count();
	
	return;
}

sub CheckBonusRound
{
	my ($self) = @_;
	if ($self->{bonusroundtime} > 0 && ($::ev_remotetime > ($self->{bonusroundtime_ts} + $self->{bonusroundtime})))
	{
		if ($self->{bonusroundtime_state} == 1)
		{
			&::PrintEvent("SERVER", "Bonus Round Expired", 1);
		}
		$self->{bonusroundtime_state} = 0;
	}
	
	if ($self->{bonusroundignore} == 1 && $self->{bonusroundtime_state} == 1)
	{
		return 1;
	}
	
	return 0;
}

sub SetIngameUrl
{
	my ($self) = @_;
	
	# so ingame browsing will work correctly
	my $url = $self->{hlstats_url};
	$url  =~ s/\/hlstats.php//i;
	$url  =~ s/\/$//;
	
	$self->{ingame_url}  = $url;
	
	&::PrintEvent("SERVER", "Ingame-URL: ".$url, 1);
	
	return;
}

sub __DoQueuedRcon
{
	my ($self, $cmd) = @_;
	$::g_rconqueue->enqueue(3);
	$::g_rconqueue->enqueue($self->{id});
	$::g_rconqueue->enqueue($cmd);
	
	return;
}

DESTROY
{
	my ($self) = @_;
	$self->updateDB();
	$::g_rconqueue->enqueue(4);
	$::g_rconqueue->enqueue($self->{id});
}

1;
