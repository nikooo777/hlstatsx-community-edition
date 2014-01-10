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

package HLstats_EventMgr;

use strict;
use warnings;

do "$::opt_libdir/HLstats_GameConstants.plib";

sub get_fav_weapon
{

	my ($player)  = @_;
	my $p_connect_time = $player->{connect_time};
	
	my $result = $::g_db->DoQuery("
		SELECT
			hlstats_Events_Frags.weapon,
			COUNT(hlstats_Events_Frags.weapon) AS kills,
			SUM(hlstats_Events_Frags.headshot=1) as headshots
		FROM
			hlstats_Events_Frags,hlstats_Servers
		WHERE
			hlstats_Servers.serverId=hlstats_Events_Frags.serverId
			AND hlstats_Servers.game=".$::g_db->Quote($::g_servers{$::s_addr}->{game})." AND hlstats_Events_Frags.killerId=".$player->{playerid}."
		GROUP BY
			hlstats_Events_Frags.weapon
		ORDER BY
			kills desc, headshots desc
		LIMIT 1	
	");
	my ($fav_weapon, $fav_weapon_kills, $fav_weapon_headshots) = $result->fetchrow_array;
	$result->finish;

	$result = $::g_db->DoQuery("
		SELECT
			IFNULL(ROUND((SUM(hlstats_Events_Statsme.hits) / SUM(hlstats_Events_Statsme.shots) * 100), 0), 0) AS acc
		FROM
			hlstats_Events_Statsme, hlstats_Servers
		WHERE
			hlstats_Servers.serverId=hlstats_Events_Statsme.serverId
			AND hlstats_Servers.game=".$::g_db->Quote($::g_servers{$::s_addr}->{game})." AND hlstats_Events_Statsme.PlayerId=".$player->{playerid}."
			AND hlstats_Events_Statsme.weapon=".$::g_db->Quote($fav_weapon)."
		LIMIT 0,1	
	");
	my ($fav_weapon_sm_acc) = $result->fetchrow_array;
	$result->finish;

	$result = $::g_db->DoQuery("
		SELECT
			hlstats_Events_Frags.weapon,
			COUNT(hlstats_Events_Frags.weapon) AS kills,
			SUM(hlstats_Events_Frags.headshot=1) as headshots
		FROM
			hlstats_Events_Frags,hlstats_Servers
		WHERE
			hlstats_Servers.serverId=hlstats_Events_Frags.serverId
			AND hlstats_Servers.game=".$::g_db->Quote($::g_servers{$::s_addr}->{game})." AND hlstats_Events_Frags.killerId='".$player->{playerid}."'
			AND (hlstats_Events_Frags.eventTime > FROM_UNIXTIME(".$p_connect_time."))
		GROUP BY
			hlstats_Events_Frags.weapon
		ORDER BY
			kills desc, headshots desc
		LIMIT 0, 1	
	");

	my $s_fav_weapon = "";
	my $s_fav_weapon_kills = 0;
	my $s_fav_weapon_headshots = 0;
	if($result->rows)
	{
		($s_fav_weapon, $s_fav_weapon_kills, $s_fav_weapon_headshots) = $result->fetchrow_array;
	}
	$result->finish;
	my $s_fav_weapon_sm_acc = 0;
	   
	if (($s_fav_weapon ne "") && ($s_fav_weapon_kills > 0))
	{
		my $result = $::g_db->DoQuery("
			SELECT
				IFNULL(ROUND((SUM(hlstats_Events_Statsme.hits) / SUM(hlstats_Events_Statsme.shots) * 100), 0), 0) AS acc
			FROM
				hlstats_Events_Statsme, hlstats_Servers
			WHERE
				hlstats_Servers.serverId=hlstats_Events_Statsme.serverId
				AND hlstats_Servers.game=".$::g_db->Quote($::g_servers{$::s_addr}->{game})." AND hlstats_Events_Statsme.PlayerId='".$player->{playerid}."'
				AND hlstats_Events_Statsme.weapon=".$::g_db->Quote($s_fav_weapon)."
				AND (hlstats_Events_Statsme.eventTime > FROM_UNIXTIME(".$p_connect_time."))
			LIMIT 0,1	
		");
		($s_fav_weapon_sm_acc) = $result->fetchrow_array;
		$result->finish;
	}
	
	return ($::g_games{$::g_servers{$::s_addr}->{game}}{weapons}{$fav_weapon}{name}, $fav_weapon_kills, $fav_weapon_sm_acc, $::g_games{$::g_servers{$::s_addr}->{game}}{weapons}{$s_fav_weapon}{name}, $s_fav_weapon_kills, $s_fav_weapon_sm_acc);
}

sub get_next_ranks
{
	my ($player)  = @_;

	my $result = $::g_db->DoQuery("
		SELECT
			$::g_ranktype,
			kpd
		FROM
			hlstats_Players
		WHERE
			playerId=" . $player->{playerid}
	);
	my ($base, $kpd) = $result->fetchrow_array;
	$result->finish;
	my $playerName = $player->{name};

	if (!$base)
	{
		$base = 0;
	}

	my $ranknumber = $player->getRank();

	my $rankword = "";
	if ($::g_ranktype eq "kills")
	{
		$rankword = " kills";
	}
	my $osd_message = "->1 - Next Players\\n".sprintf("   %02d  %s%s        -      %s", $ranknumber, &::FormatNumber($base), $rankword, $playerName)."\\n";
	
	$result = $::g_db->DoQuery("
		SELECT
			playerId,
			lastName,
			$::g_ranktype,
			kpd
		FROM
			hlstats_Players
		WHERE
			game=".$::g_db->Quote($player->{game})."
			AND $::g_ranktype = $base
			AND hideranking = 0
			AND kills >= 1
			AND playerId <> " . $player->{playerid} . "
		HAVING
			kpd>=$kpd
		ORDER BY $::g_ranktype, kpd
		LIMIT 0,10
	");

	my $player_count = 0;
	my $i = $ranknumber;
	while ($player_count < 11 && (my ($playerId, $lastName, $p_base, $kpd) = $result->fetchrow_array))
	{
		$i--;
		if (length($lastName) > 20)
		{
			$lastName = substr($lastName, 0, 17)."...";
		}
		$player_count++;
		$osd_message .= sprintf("   %02d  %s%s  +%04d  %s", $i, &::FormatNumber($p_base), $rankword, &::FormatNumber($p_base-$base), $lastName)."\\n";
	}
	$result->finish;

	if ($player_count < 11)
	{
		my $result = $::g_db->DoQuery("
			SELECT
				playerId,
				lastName,
				$::g_ranktype,
				kpd
			FROM
				hlstats_Players
			WHERE
				game=".$::g_db->Quote($player->{game})."
				AND hideranking = 0
				AND $::g_ranktype > $base
				AND kills >= 1
			ORDER BY
				$::g_ranktype,
				kpd
			LIMIT 0,10
		");
      
		while (($player_count < 11) && (my ($playerId, $lastName, $p_base, $kpd) = $result->fetchrow_array))
		{
			$i--;
			if (length($lastName) > 20)
			{
				$lastName = substr($lastName, 0, 17)."...";
			}
			$osd_message .= sprintf("   %02d  %s%s  +%04d  %s", $i, &::FormatNumber($p_base), $rankword, ($p_base-$base), $lastName)."\\n";
			$player_count++;
		}
		$result->finish;
	}
   
	return ($ranknumber, $::g_games{$player->{game}}->getTotalPlayers(), $osd_message);
}


sub get_player_rank
{
	my ($player)  = @_;
	
	my $base = 0;
	if ($::g_ranktype ne "kills")
	{
		$base = $player->{skill};
	}
	else
	{
		$base = $player->{total_kills};
	}
   
	return ($base, $player->getRank(), $::g_games{$player->{game}}->getTotalPlayers());

}

sub get_player_data
{
	my ($player, $get_rank)  = @_;

	my $result = $::g_db->DoQuery("
		SELECT
			skill, kills, deaths, suicides, headshots,
			IFNULL(ROUND((hits / shots * 100), 0), 0) AS acc,
			connection_time
		FROM
			hlstats_Players
		WHERE
			playerId=" . $player->{playerid} . "
	");
    my ($skill, $kills, $deaths, $suicides, $headshots, $acc, $connection_time) = $result->fetchrow_array;
	$result->finish;
	
    my $playerName = $player->{name};

	my $kd;
    if ($deaths > 0)
	{
		$kd = sprintf("%.2f", $kills/$deaths);
    }
	else
	{
		$kd = sprintf("%.2f", $kills);
    }
	
	my $hpk;
    if ($kills > 0)
	{
		$hpk = sprintf("%.0f", (100/$kills) * $headshots);
    }
	else
	{
		$hpk = sprintf("%.0f", $kills);
    }
    
	my ($fav_weapon, $fav_weapon_kills, $fav_weapon_acc, $s_fav_weapon, $s_fav_weapon_kills, $s_fav_weapon_acc);
    if ($kills > 0)
	{
		($fav_weapon, $fav_weapon_kills, $fav_weapon_acc, $s_fav_weapon, $s_fav_weapon_kills, $s_fav_weapon_acc) = get_fav_weapon($player);
    }
	else
	{
		$fav_weapon   = "-";
		$s_fav_weapon = "-";
    }  
    
    if ($get_rank > 0)
	{
		my ($rang_skill, $rank_number, $total_players) = get_player_rank($player);
		return ($skill, $kills, $deaths, $kd, $suicides, $headshots, $hpk, $acc, $connection_time,$fav_weapon, $fav_weapon_kills, $fav_weapon_acc, $s_fav_weapon, $s_fav_weapon_kills, $s_fav_weapon_acc, $rank_number, $total_players);
    }
	else
	{
		return ($skill, $kills, $deaths, $kd, $suicides, $headshots, $hpk, $acc, $connection_time, $fav_weapon, $fav_weapon_kills, $fav_weapon_acc, $s_fav_weapon, $s_fav_weapon_kills, $s_fav_weapon_acc);
    }
    
}

sub get_menu_text
{
	my ($player, $skill, $kills, $deaths, $kd, $suicides, $headshots, $hpk, $acc, $connection_time, $fav_weapon, $fav_weapon_kills, $fav_weapon_acc, $s_fav_weapon, $s_fav_weapon_kills, $s_fav_weapon_acc, $rank_number, $total_players) = @_;

	my $p_name         = $player->{name};
	my $p_connect_time = $player->{connect_time};

	my $s_pos_change = "N/A";
	if ($player->{session_start_pos} > 0)
	{
		$s_pos_change   = ($player->{session_start_pos} - $rank_number);
		if ($s_pos_change > 0)
		{
			$s_pos_change = "+".$s_pos_change;
		}
	}

	my $s_skill_change = $player->{session_skill};
	if ($s_skill_change > 0)
	{
		$s_skill_change = "+".$s_skill_change;
	}
  
	my $s_kills        = $player->{session_kills};
	my $s_deaths       = $player->{session_deaths};
	my $s_headshots    = $player->{session_headshots};
	my $s_hits         = $player->{session_hits};
	my $s_shots        = $player->{session_shots};
	
	my $s_kd;
	if ($s_deaths > 0)
	{
		$s_kd = sprintf("%.2f", $s_kills/$s_deaths);
	}
	elsif ($s_kills > 0)
	{
		$s_kd = sprintf("%.2f", $s_kills);
	}
	else
	{
		$s_kd = sprintf("%.2f", 0);
	}
  
	my $s_hpk;
	if ($s_kills > 0)
	{
		$s_hpk = sprintf("%.0f", (100/$s_kills) * $s_headshots);
	}
	elsif ($s_headshots > 0)
	{
		$s_hpk = sprintf("%.0f", $s_headshots);
	}
	else
	{
		$s_hpk = sprintf("%.0f", 0);
	}

	my $s_acc;
	if ($s_shots > 0)
	{
		$s_acc = sprintf("%.0f", (100/$s_shots) * $s_hits);
	}
	elsif ($s_hits > 0)
	{
		$s_acc = sprintf("%.0f", $s_hits);
	}
	else
	{
		$s_acc = sprintf("%.0f", 0);
	}

	my $weapon_str =  "   No Fav Weapon\\n";
	my $acc_str    =  "   $acc% Accuracy\\n";
	if ($fav_weapon_kills > 0)
	{
		$weapon_str = "   ".$fav_weapon_kills." kills with ".$fav_weapon."\\n";
		$acc_str    = "   $acc% Accuracy (".$fav_weapon." ".$fav_weapon_acc."%)\\n";
	}
	if ($acc == 0)
	{
		$acc_str = "";
	}

	my $s_weapon_str =  "   No Fav Weapon\\n";
	my $s_acc_str    =  "   $s_acc% Accuracy\\n";
	if ($s_fav_weapon_kills > 0)
	{
		$s_weapon_str = "   ".$s_fav_weapon_kills." kills with ".$s_fav_weapon."\\n";
		$s_acc_str    = "   $s_acc% Accuracy (".$s_fav_weapon." ".$s_fav_weapon_acc."%)\\n";
	}
  
	if ($s_acc == 0)
	{
		$s_acc_str = "";
	}
	my $cmd_text = "";
	
	if ($::g_ranktype eq "kills")
	{
		$cmd_text = 	"->1 - Total\\n".
					"   Position ".&::FormatNumber($rank_number)." of ".&::FormatNumber($total_players)."\\n".
                    "   ".&::FormatNumber($kills).":".&::FormatNumber($deaths)." Frags ($kd)\\n".
					"   ".&::FormatNumber($headshots)." Headshots ($hpk%)\\n".
					"   ".&::FormatNumber($skill)." Points\\n".
					$weapon_str.
                    $acc_str.
                    "   Time ".&::FormatDate($connection_time)."\\n \\n".
                    "->2 - Session\\n".
                    "   ".&::FormatNumber($s_pos_change)." Positions\\n".
                    "   ".&::FormatNumber($s_kills).":".&::FormatNumber($s_deaths)." Frags ($s_kd)\\n".
                    "   ".&::FormatNumber($s_headshots)." Headshots ($s_hpk%)\\n".
					"   ".&::FormatNumber($s_skill_change)." Points\\n".
                    $s_weapon_str.
                    $s_acc_str.
                    "   Time ".&::FormatDate(time() - $p_connect_time)."\\n";
	}
	else
	{
		$cmd_text = 	"->1 - Total\\n".
					"   Position ".&::FormatNumber($rank_number)." of ".&::FormatNumber($total_players)."\\n".
					"   ".&::FormatNumber($skill)." Points\\n".
                    "   ".&::FormatNumber($kills).":".&::FormatNumber($deaths)." Frags ($kd)\\n".
					"   ".&::FormatNumber($headshots)." Headshots ($hpk%)\\n".
					$weapon_str.
                    $acc_str.
                    "   Time ".&::FormatDate($connection_time)."\\n \\n".
                    "->2 - Session\\n".
                    "   ".&::FormatNumber($s_pos_change)." Positions\\n".
                    "   ".&::FormatNumber($s_skill_change)." Points\\n".
                    "   ".&::FormatNumber($s_kills).":".&::FormatNumber($s_deaths)." Frags ($s_kd)\\n".
                    "   ".&::FormatNumber($s_headshots)." Headshots ($s_hpk%)\\n".
                    $s_weapon_str.
                    $s_acc_str.
                    "   Time ".&::FormatDate(time() - $p_connect_time)."\\n";
	}

	return $cmd_text;
}

sub __EndKillStreak
{
	my ($player) = @_;
	
	my $killtotal = $player->{kills_per_life};
	if ($killtotal > $player->{kill_streak})
	{
		$player->{kill_streak} = $killtotal;
	}
	if ($killtotal > 12)
	{
		$killtotal = 12;
	}
	# octo: I don't think suicides should count as deaths in a row
	if ($killtotal > 1)
	{
		EvPlayerAction(
			$player->{userid},
			$player->{uniqueid},
			"kill_streak_" . $killtotal
		);
	}
	$player->{kills_per_life} = 0;
	
	return;
}

#
# 001. Connect
#

sub EvConnect
{
	my ($playerId, $playerUniqueId, $ipAddr) = @_;

	my $desc = "";
	my $hostname = "";
	my $hostgroup = "";
	my $player = &::LookupPlayer($::s_addr, $playerId, $playerUniqueId);
	my $playerstr = &::GetPlayerInfoString($player, $playerId);
	
	if (!$player)
	{
		$desc = "(IGNORED) NOPLAYERINFO: ";
	}
	else
	{
		my $server = $::g_servers{$::s_addr};
		my $isbot = $player->{is_bot};
		
		$player->set("connect_time", time());
		
		if ($server->{ignore_bots} == 1 && $isbot)
		{
			$player->updateDB();
			$desc = "(IGNORED) BOT: ";
		}
		else
		{
			if (!$isbot)
			{
				my $player_rank = $player->getRank();
				&__CheckMinPlayerRank($player, $player_rank);
			
				if ($::g_mode == TRACKMODE_NORMAL())
				{
					$hostname = ::ResolveIp($ipAddr);
			
					if ($hostname ne "")
					{
						$hostgroup = ::GetHostGroup($hostname);
					}
					if ($::g_stdin == 0 && $server->{connect_announce} > 0)
					{
						my $msg = "";
						if ($player->{country} ne "")
						{
							if ($player_rank == 0)
							{
								$msg = sprintf("Player %s has connected from %s", $player->{name}, $player->{country});
							}
							elsif ($player->{skill} == 1000)
							{
								$msg = sprintf("New player %s has connected from %s", $player->{name}, $player->{country});
							}
							elsif ($::g_ranktype ne "kills")
							{
								$msg = sprintf("%s (Pos %s with %s points) has connected from %s", $player->{name}, $player_rank, $player->{skill}, $player->{country});
							}
							else
							{
								$msg = sprintf("%s (Pos %s with %s kills) has connected from %s", $player->{name}, $player_rank, $player->{total_kills}, $player->{country});
							}
							$::g_servers{$::s_addr}->MessageAll($msg, $player->{playerid}, 1);
						}
						else
						{
							if ($::g_ranktype ne "kills")
							{
								$msg = sprintf("%s (Pos %s with %s points) has connected", $player->{name}, $player_rank, $player->{skill});
							}
							else
							{
								$msg = sprintf("%s (Pos %s with %s kills) has connected", $player->{name}, $player_rank, $player->{total_kills});
							}
							$server->MessageAll($msg, $player->{playerid}, 1);
						}
					}
				}
				elsif ($::g_mode == TRACKMODE_LAN())
				{
					$player->set("uniqueid", $ipAddr);
				}
			}
			&::RecordEvent(
				"Connects", 0,
				$player->{playerid},
				$ipAddr,
				$hostname,
				$hostgroup
			);
		}
	}
	
	return $desc . $playerstr . " connected, address \"$ipAddr\","
		. " hostname \"$hostname\", hostgroup \"$hostgroup\"";
}


#
# 002. Enter Game
#

sub EvEnterGame
{
	my ($playerId, $playerUniqueId) = @_;
	
	my $desc = "";
	my $player = &::LookupPlayer($::s_addr, $playerId, $playerUniqueId);
	my $playerstr = &::GetPlayerInfoString($player, $playerId);
    
	if ($player)
	{
		my $server = $::g_servers{$::s_addr};
		my $isbot = $player->{is_bot};
		
		if ($player->{connect_time} == 0)
		{
			$player->set('connect_time', time());
		}
		
		if ($server->{ignore_bots} == 1 && $isbot)
		{
			$desc = "(IGNORED) BOT: ";
		}
		else
		{
			if (!$isbot)
			{
				&__CheckMinPlayerRank($player, $player->getRank());
			}
			
			&::RecordEvent(
				"Entries", 0,
				$player->{playerid}
			);
		}
		$player->updateDB();
	}
	else
	{
		$desc = "(IGNORED) NOPLAYERINFO: ";
	}
	
	return $desc . $playerstr . " entered the game";
}


#
# 003. Disconnect
#

sub EvDisconnect
{
	my ($pUserId, $playerUniqueId, $properties) = @_;
	
	my $desc = "";
	my $player = &::LookupPlayer($::s_addr, $pUserId, $playerUniqueId);
	my $playerstr = &::GetPlayerInfoString($player, $pUserId);
	my $reason = ($properties && (exists($properties->{reason})) ? $properties->{reason} : "");
	
	if ($player)
	{
		my $server = $::g_servers{$::s_addr};
		
		if ($server->{ignore_bots} == 1 && $player->{is_bot} == 1)
		{
			$player->updateDB();
			&::RemovePlayer($::s_addr, $pUserId, $playerUniqueId);
			$desc = "(IGNORED) BOT: ";
		}
		else
		{
			&::RecordEvent(
				"Disconnects", 0,
				$player->{playerid}
			);
			
			&__EndKillStreak($player);
			
			if ($::g_global_chat > 0)
			{
				my $p_name    = $player->{name};
				my $b_message = $p_name." (".$::g_servers{$::s_addr}->{name}.") disconnected";
				if ($player->{is_dead} == 1)
				{
					$b_message  = "*DEAD* ".$p_name." (".$::g_servers{$::s_addr}->{name}.") disconnected";
				}
				&::SendGlobalChat($b_message);
			}
		
			my $p_steamid = $player->{plain_uniqueid};
			my $p_connect_time = $player->{connect_time};
			my $p_is_banned = $player->{is_banned};
        
			if ($p_connect_time == 0)
			{
				$p_connect_time = time();
			}
        
			my $auto_ban = $::g_servers{$::s_addr}->{auto_ban};
			# time()-$p_connect_time > 30 to avoid permanent bans changes in 5 min bans
			# $p_is_banned > 0 for not converting bans to "just" 5 minutes bans
			if (($auto_ban > 0) && ((time() - $p_connect_time) > 30) && ($p_is_banned == 0)
				&& $player->{is_bot} == 0 && $::g_servers{$::s_addr}->is_admin($playerUniqueId) == 0)
			{
				$::g_servers{$::s_addr}->DoRcon("banid 5 $p_steamid");
			}
			$player->updateDB();
			&::RemovePlayer($::s_addr, $pUserId, $playerUniqueId);
		}
	}
	else
	{
		$desc = "(IGNORED) NOPLAYERINFO: ";
		if ($playerUniqueId eq "" || $reason eq "")
		{
			return "(IGNORED) NOPLAYERINFO: " . $playerstr . " disconnected";
		}
		
		if ($reason eq "VAC banned from secure server")
		{
			$desc = "(IGNORED) VAC BANNED PLAYER [".$playerUniqueId."]: ";
			my $playerid = &getPlayerId($playerUniqueId);
			if ($playerid)
			{
				my $query = "SELECT lastName, hideranking FROM hlstats_Players WHERE playerId=$playerid";
				my $result = $::g_db->DoQuery($query);
				my ($lastName, $hideranking) = $result->fetchrow_array;
				$result->finish;
				if ($hideranking < 2)
				{
					$::g_queryqueue->enqueue('nc');
					$::g_queryqueue->enqueue("UPDATE hlstats_Players SET last_event=UNIX_TIMESTAMP(), hideranking=2 WHERE playerId=$playerid");
					$desc = "HIDING VAC BANNED PLAYER [".$playerUniqueId.", ".$lastName."]: ";
				}
				else
				{
					$desc = "VAC BANNED PLAYER [".$playerUniqueId.", ".$lastName."] ALREADY HIDDEN: ";
				}
			}
		}
		elsif ($properties->{reason} eq "Kicked by Console :  You have been banned, visit www.steambans.com for information.")
		{
			$desc = "(IGNORED) STEAMBANS BANNED PLAYER [".$playerUniqueId."]: ";
			my $playerid = &getPlayerId($playerUniqueId);
			if ($playerid)
			{
				my $query      = "SELECT lastName, hideranking FROM hlstats_Players WHERE playerId=$playerid";
				my $result     = $::g_db->DoQuery($query);
				my ($lastName, $hideranking) = $result->fetchrow_array;
				$result->finish;
				if ($hideranking < 2)
				{
					$::g_queryqueue->enqueue('nc');
					$::g_queryqueue->enqueue("UPDATE hlstats_Players SET last_event=UNIX_TIMESTAMP(), hideranking=2 WHERE playerId=$playerid");
					$desc = "HIDING STEAMBANS BANNED PLAYER [".$playerUniqueId.", ".$lastName."]: ";
				}
				else
				{
					$desc = "STEANBANS BANNED PLAYER [".$playerUniqueId.", ".$lastName."] ALREADY HIDDEN: ";
				}
			}
		}
	}

	return $desc . $playerstr . " disconnected. Reason: $reason";
}


#
# 004. Suicide
#

sub EvSuicide
{
	my ($playerId, $playerUniqueId, $weapon, $properties) = @_;
	
	my $x = undef;
	my $y = undef;
	my $z = undef;
	my $coords;
	
	if (defined($properties->{attacker_position}))
	{
		$coords = $properties->{attacker_position};
		# print "\nCoords SUICIDE: ".$coords."\n\n";
		($x,$y,$z) = split(/ /,$coords);
	}

	my $desc = "";
	my $player = &::LookupPlayer($::s_addr, $playerId, $playerUniqueId);
	my $playerstr = &::GetPlayerInfoString($player, $playerId);
	
	if ($::g_servers{$::s_addr}->{num_trackable_players} < $::g_servers{$::s_addr}->{minplayers})
	{
		$desc = "(IGNORED) NOTMINPLAYERS: ";
	}
	elsif ($::g_servers{$::s_addr}->CheckBonusRound())
	{
		$desc = "(IGNORED) BonusRound: ";
	}
	elsif (!$player)
	{
		$desc = "(IGNORED) NOPLAYERINFO: ";
	}
	elsif ($player->{last_team_change}+2 > $::ev_remotetime)
	{
		$desc = "(IGNORED) TEAMSWITCH: ";
	}	
	else
	{
		if ($::g_servers{$::s_addr}->{ignore_bots} == 1 && $player->{is_bot} == 1)
		{
			$desc = "(IGNORED) BOT: ";
		}
		else
		{
			__EndKillStreak($player);
			
			if ($::g_servers{$::s_addr}->{play_game} == TF() && defined($properties->{customkill}))
			{
				if ($properties->{customkill} eq "train")
				{
					EvPlayerAction(
						$player->{userid},
						$player->{uniqueid},
						"hit_by_train",
						$x,
						$y,
						$z,
						$properties
					);
				}
				elsif ($properties->{customkill} eq "saw")
				{
					EvPlayerAction(
						$player->{userid},
						$player->{uniqueid},
						"death_sawblade",
						$x,
						$y,
						$z,
						$properties
					);
				}
			}
			
			&::RecordEvent(
				"Suicides", 0,
				$player->{playerid},
				$weapon,
				$x,
				$y,
				$z
			);

			my $suicide_penalty = (-1) * $::g_servers{$::s_addr}->{suicide_penalty};
			$player->increment("suicides");
			$player->increment("skill", $suicide_penalty);
			$player->increment("session_suicides");
			$player->increment("session_skill", $suicide_penalty);
			$player->increment("map_suicides");
			$::g_servers{$::s_addr}->increment("suicides");
			$::g_servers{$::s_addr}->increment("total_suicides");
			$player->updateDB();
		}
	}
	
	return $desc . $playerstr . " committed suicide with \"$weapon\"";
}


#
# 005. Team Selection
#

sub EvTeamSelection
{
	my ($playerId, $playerUniqueId, $team) = @_;
	
	my $desc = "";
	my $player = &::LookupPlayer($::s_addr, $playerId, $playerUniqueId);
	my $playerstr = &::GetPlayerInfoString($player, $playerId);
	
	if (!$player)
	{
		$desc = "(IGNORED) NOPLAYERINFO: ";
	}
	else
	{
		if ($::g_servers{$::s_addr}->{ignore_bots} == 1 && $player->{is_bot} == 1)
		{
			$player->set('team', $team);
			$desc = "(IGNORED) BOT: ";
		}
		else
		{
			my $old_team = $player->{team};
			if (($old_team eq "CT") || ($old_team eq "TERRORIST"))
			{
				$::g_servers{$::s_addr}->increment('ba_player_switch');
			}  
			$player->set('last_team_change', $::ev_remotetime);
			$player->set('team', $team);
			&::RecordEvent(
				"ChangeTeam", 0,
				$player->{playerid},
				$team
			);
			
			$player->UpdateTrackable();
			$player->updateDB();
			$::g_servers{$::s_addr}->updatePlayerCount();
		}
	}
	
	return $desc . $playerstr . " joined team \"$team\"";
}


#
# 006. Role Selection
#

sub EvRoleSelection
{
	my ($playerId, $playerUniqueId, $role) = @_;
	
	my $desc = "";
	my $player = &::LookupPlayer($::s_addr, $playerId, $playerUniqueId);
	my $playerstr = &::GetPlayerInfoString($player, $playerId);
	
	if ($player)
	{
		if ($::g_servers{$::s_addr}->{ignore_bots} == 1 && $player->{is_bot} == 1)
		{
			$player->set("role", $role);
			$desc = "(IGNORED) BOT: ";
		}
		else
		{
			$player->set("role", $role);
			&::RecordEvent(
				"ChangeRole", 0,
				$player->{playerid},
				$role
			);
			my $query = "
				UPDATE
					hlstats_Roles
				SET
					picked=picked+1
				WHERE 
					game=?
					AND code=?
				";
			$::g_queryqueue->enqueue('role_update_picks');
			$::g_queryqueue->enqueue($query);
			$::g_queryqueue->enqueue([$::g_servers{$::s_addr}->{game}, $role]);
			$player->updateDB();
		}
	}
	else
	{
		$desc = "(IGNORED) NOPLAYERINFO: ";
	}
	
	return $desc . $playerstr . " changed role to \"$role\"";
}


#
# 007. Change Name
#

sub EvChangeName
{
	my ($playerId, $playerUniqueId, $newname) = @_;
	
	my $desc = "";
	my $player = &::LookupPlayer($::s_addr, $playerId, $playerUniqueId);
	my $playerstr = &::GetPlayerInfoString($player, $playerId);
	
	if (!$player)
	{
		$desc = "(IGNORED) NOPLAYERINFO: ";
	}
	else
	{
		if ($::g_servers{$::s_addr}->{ignore_bots} == 1 && $player->{is_bot} == 1)
		{
			$player->updateDB();
			&::RemovePlayer($::s_addr, $playerId, $playerUniqueId);
			$desc = "(IGNORED) BOT: ";
		}
		else
		{
			&::RecordEvent(
				"ChangeName", 0,
				$player->{playerid},
				$player->{name},
				$newname
			);

			if ($player->{is_bot} == 1)
			{
				$player->updateDB();
				&::RemovePlayer($::s_addr, $playerId, $playerUniqueId);
			}
			else
			{
				$player->set('name', $newname);
				$player->updateDB();
			}
		}
	}
	
	return $desc . $playerstr . " changed name to \"$newname\"";
}


#
# E008. Frag
#

sub EvFrag
{
	my ($k_userid, $k_uniqueid, $v_userid, $v_uniqueid, $weapon, $headshot, $x, $y, $z, $vx, $vy, $vz, $properties) = @_;
	my $server = $::g_servers{$::s_addr};
	my $playgame = $server->{play_game};
	my $rcmd = $server->{broadcasting_command};
	my $coords;
	
	# if killer coords were on kill line, use them
	if (defined($properties->{attacker_position}))
	{
		$coords = $properties->{attacker_position};
		($x,$y,$z) = split(/ /,$coords);
	}
	elsif (defined($properties->{killerpos}))  # pvkii
	{
		$coords = $properties->{killerpos};
		($x,$y,$z) = split(/ /,$coords);
	}
	elsif ($server->{nextkillx} ne "")
	{
		# else use coords stored from plugin if available
		$x = $server->{nextkillx};
		$y = $server->{nextkilly};
		$z = $server->{nextkillz};
	}
	# regardless, reset last kill coords
	$server->{nextkillx} = "";
	$server->{nextkilly} = "";
	$server->{nextkillz} = "";
	
	# if victim coords were on kill line, use them
	if (defined($properties->{victim_position}))
	{
		$coords = $properties->{victim_position};
		($vx,$vy,$vz) = split(/ /,$coords);
	}
	elsif (defined($properties->{victimpos}))  # pvkii
	{
		$coords = $properties->{victimpos};
		($x,$y,$z) = split(/ /,$coords);
	}
	elsif ($server->{nextkillvicx} ne "")
	{
		# else use coords stored from plugin if available
		$vx = $server->{nextkillvicx};
		$vy = $server->{nextkillvicy};
		$vz = $server->{nextkillvicz};
	}
	# regardless, reset last kill coords
	$server->{nextkillvicx} = "";
	$server->{nextkillvicy} = "";
	$server->{nextkillzvic} = "";

	# determine if kill was fake
	# currently only applicable to TF2's "Dead Ringer"
	my $isfake = (defined($properties->{customkill}) && $properties->{customkill} eq "feign_death")?1:0;
	
	my $desc = "";
	my $killer = &::LookupPlayer($::s_addr, $k_userid, $k_uniqueid);
	my $victim = &::LookupPlayer($::s_addr, $v_userid, $v_uniqueid);
	my $killerstr = &::GetPlayerInfoString($killer, $k_userid);
	my $victimstr = &::GetPlayerInfoString($victim, $v_userid);
	
	my $headshotFromAction = 0;

	if (($server->{num_trackable_players} < $server->{minplayers}) && $playgame != L4D())
	{
		$desc = "(IGNORED) NOTMINPLAYERS: ";
	}
	elsif ($server->CheckBonusRound())
	{
		$desc = "(IGNORED) BonusRound: ";
	}
	elsif ($killer && $victim)
	{
		if ($server->{ignore_bots} == 1 && ($killer->{is_bot} == 1 || $victim->{is_bot} == 1))
		{
			$desc = "(IGNORED) BOT: ";
		}
		elsif ($playgame == L4D() && $killer->{team} eq "Infected" && $victim->{team} eq "Infected")
		{
			$desc = "(IGNORED) L4D Infected TK: ";
		}
		else
		{
			my $k_role = $killer->{role};
			my $v_role = $victim->{role};
			
			# weapon fixes
			if ($weapon eq "")
			{
				if ($k_role ne "")
				{
					$weapon = $k_role;
				}
				else
				{
					$weapon = "world";
				}
			}
			elsif ($playgame == TF() && $k_role ne "")
			{
				&EvPlayerAction(
					$killer->{userid},
					$killer->{uniqueid},
					"kill_as_".$k_role,
					$x,
					$y,
					$z,
					$properties
				);
			}
			elsif ($playgame == ZPS() && $weapon eq "broom")
			{
				$weapon = "crowbar";
			}
			elsif ($playgame == FF())
			{
				if ($weapon eq "BOOM_HEADSHOT")
				{
					$weapon = "weapon_sniperrifle";
					$headshot = 1;
				}
				elsif ($weapon eq "grenade_napalmlet")
				{
					$weapon = "grenade_napalm";
				}
			}
			elsif ($playgame == TFC() && $weapon eq "headshot")
			{
				$weapon = "sniperrifle";
				$headshot = 1;
			}
			elsif ($playgame == PVKII())
			{
				if (defined($properties->{killerclass}))
				{
					my $krole = $properties->{killerclass};
					if ($krole ne "" && $krole ne $killer->{role})
					{
						EvRoleSelection(
							$killer->{userid},
							$killer->{uniqueid},
							$krole
						);
					}
				}
				if (defined($properties->{victimclass}))
				{
					my $vrole = $properties->{victimclass};
					if ($vrole ne "" && $vrole ne $victim->{role})
					{
						EvRoleSelection(
							$victim->{userid},
							$victim->{uniqueid},
							$vrole
						);
					}
				}
			}
			elsif ($playgame == FOF())
			{
				# strip off the 2 at the end of some weapon names in FoF so weapon is right hand is counted the same as same weapon in the left hand
				$weapon =~ s/2$//;
				if ($weapon eq "bow")
				{
					$weapon = "arrow";
				}
			}
			
			# if plugin marked next kill as headshot for this player, headshot
			if ($server->{nextkillheadshot} == $killer->{playerid})
			{
				$headshot = 1;
				$headshotFromAction = 1;
			}
			# reset nextkillheadshot flag at end of sub
			
			my $was_tk = &__SameTeam($killer->{team}, $victim->{team});

			# This is a fix for TF2 - they report player death after reporting team switch
			# I don't know how soon after a team switch in other games that you can actually attempt to kill someone
			if (($was_tk == 1 && ($victim->{last_team_change}+2 > $::ev_remotetime)) && ($playgame == TF()))
			{
				# print "NOT A TEAM KILL - RECENT TEAM SWITCH by " . $victim->{name} . "(Now:" . $::ev_remotetime . ") Changed(" . $victim->{last_team_change} .")";
				$desc = "NOT A TEAM KILL - RECENT TEAM SWITCH";
				$was_tk=0;
			}
			if ($was_tk==0 || $server->{game_type} == 1)
			{
				# Frag
				
				if ($isfake == 0)
				{
					#kill streak code by octo
					
					$killer->{kills_per_life} += 1;
					$victim->{deaths_in_a_row} += 1;
					if ($victim->{deaths_in_a_row} > $victim->{death_streak})
					{
						$victim->set('death_streak', $victim->{deaths_in_a_row});
					}

					# we don't need to update the kills death_streak since it was done when he is a victim	
					$killer->{deaths_in_a_row} = 0;
					
					&__EndKillStreak($victim);

					&::RecordEvent(
						"Frags", 0,
						$killer->{playerid},
						$victim->{playerid},
						$weapon,
						$headshot,
						$k_role,
						$v_role,
						$x,
						$y,
						$z,
						$vx,
						$vy,
						$vz
					);

					if ($k_role ne "")
					{
						my $query = "
							UPDATE
								hlstats_Roles
							SET
								kills=kills+1
							WHERE 
								game=?
								AND code=?
							";
						$::g_queryqueue->enqueue('role_update_kills');
						$::g_queryqueue->enqueue($query);
						$::g_queryqueue->enqueue([$server->{game}, $k_role]);
					}

					if ($v_role ne "")
					{
						my $query = "
							UPDATE
								hlstats_Roles
							SET
								deaths=deaths+1
							WHERE 
								game=?
								AND code=?
							";
						$::g_queryqueue->enqueue('role_update_deaths');
						$::g_queryqueue->enqueue($query);
						$::g_queryqueue->enqueue([$server->{game}, $v_role]);
					}
					
					if ($headshot)
					{
						$::g_queryqueue->enqueue('weapon_update_plyr_cnt_hs');
						$::g_queryqueue->enqueue("INSERT INTO hlstats_Weapons_Counts (playerId, game, code, kills, headshots) VALUES (?,?,?,1,1) ON DUPLICATE KEY UPDATE kills=kills+1, headshots=headshots+1");
					}
					else
					{
						$::g_queryqueue->enqueue('weapon_update_plyr_cnt');
						$::g_queryqueue->enqueue("INSERT INTO hlstats_Weapons_Counts (playerId, game, code, kills, headshots) VALUES (?,?,?,1,0) ON DUPLICATE KEY UPDATE kills=kills+1");
					}
					$::g_queryqueue->enqueue([$killer->{playerid}, $server->{game}, $weapon]);
					
					$killer->increment('total_kills');
				}
				else
				{
					$desc = "FEIGN DEATH: ";
				}
				
				my $killerskill = $killer->{skill};
				my $victimskill = $victim->{skill};
				
				if ($playgame == L4D())
				{
					$killerskill = &__CalcL4DSkill(
						$killer->{skill}, 
						$weapon, 
						$server->{difficulty}
					);
				}
				else
				{
					($killerskill, $victimskill) = &__CalcSkill(
						$server->{skill_mode},
						$killer->{skill}, $killer->{total_kills},
						$victim->{skill}, $victim->{total_kills},
						$weapon,
						$killer->{team}
					);
				}
				
				my $k_name    = $killer->{name};
				my $k_skill   = $killerskill - $killer->{skill};
				my $v_name    = $victim->{name};
				my $v_skill   = $victimskill - $victim->{skill};
				
				if (!$::g_stdin && $server->{broadcasting_events} == 1)
				{
					my $killer_add_text = "";
					if ($killer->{total_kills} < $::g_player_minkills)
					{
						$killer_add_text = " [".$killer->{total_kills}."/".$::g_player_minkills."]";
					}
					my $victim_add_text = "";
					if ($victim->{total_kills} < $::g_player_minkills)
					{
						$victim_add_text = " [".$victim->{total_kills}."/".$::g_player_minkills."]";
					}
					my $v_skill_text = "";
					if ($k_skill != ((-1) * $v_skill))
					{
						$v_skill_text = " [".$v_skill."]";
					}
					
					my $k_fuserid  = $server->FormatUserId($k_userid);
					my $v_fuserid  = $server->FormatUserId($v_userid);
					my $colorparam = $server->{format_color};
					my $msg = "";
					
					if ($playgame == L4D())
					{
						$msg = sprintf("%s (%s)%s got %s points for killing %s", $k_name, &::FormatNumber($killerskill), $killer_add_text, $k_skill, $v_name);
					}
					else
					{
						$msg = sprintf("%s (%s)%s got %s points%s for killing %s (%s)%s", $k_name, &::FormatNumber($killerskill), $killer_add_text, $k_skill, $v_skill_text, $v_name, &::FormatNumber($victimskill), $victim_add_text);
					}
					my @rcmds;
					if (!$killer->IsReallyBot() && $killer->{display_events} == 1)
					{
						my $cmd_str = sprintf("%s %s%s %s", $rcmd, $k_fuserid, $colorparam, $server->EscapeRconArg($msg));
						push(@rcmds, $cmd_str);
						if ($::g_player_minkills > 20 && (($killer->{total_kills} < ($::g_player_minkills / 4)) || (($killer->{total_kills} < $::g_player_minkills) && (($killer->{total_kills} % 5) == 0))))
						{
							$cmd_str = sprintf("%s %s %s", $rcmd, $k_fuserid, $server->EscapeRconArg("You need ".&::FormatNumber($::g_player_minkills-$killer->{total_kills})." kills to get regular points"));
							push(@rcmds, $cmd_str);
							
						}
					}  
					if (!$isfake && !$victim->IsReallyBot() && $victim->{display_events} == 1 && $playgame != L4D())
					{
						push(@rcmds, sprintf("%s %s%s %s", $rcmd, $v_fuserid, $colorparam, $server->EscapeRconArg($msg)));
					}
					if (scalar(@rcmds))
					{
						$server->DoRconMulti(\@rcmds);
					}
				}  
				if ($isfake == 0)
				{
					$killer->set('skill', $killerskill);
					$victim->set('skill', $victimskill);
					
					$killer->increment('session_skill', $k_skill);
					$killer->increment('kills');
					$killer->increment('session_kills');
					$server->increment('kills');
					$server->increment('total_kills');
					
					if ($headshot == 1)
					{
						$killer->increment('headshots');
						$killer->increment('session_headshots');
						$server->increment('headshots');
						$server->increment('total_headshots');
						
						if ($headshotFromAction == 0)
						{
							&EvPlayerAction(
								$killer->{userid},
								$killer->{uniqueid},
								"headshot",
								$x,
								$y,
								$z,
								$properties
							);
						}
						
						my $query = "
							INSERT INTO hlstats_Maps_Counts
								(game, map, kills, headshots)
							VALUES
								(?, ?, 1, 1)
							ON DUPLICATE KEY
								UPDATE kills=kills+1, headshots=headshots+1
						";
						$::g_db->DoCachedQuery("event_update_map_hs", $query, [$server->{game}, $server->get_map()]);
					}
					else   #not headshot
					{
						my $query = "
							INSERT INTO hlstats_Maps_Counts
								(game, map, kills)
							VALUES
								(?, ?, 1)
							ON DUPLICATE KEY
								UPDATE kills=kills+1
						";
						my @vals = ($server->{game}, $server->get_map());
						$::g_db->DoCachedQuery("event_update_map", $query, [$server->{game}, $server->get_map()]);
					}
					$victim->increment('deaths');
					$victim->increment('session_deaths');
					$victim->increment('session_skill', $v_skill);

					&__UpdateWeaponKills($weapon, $headshot);
					
					if ($playgame == L4D())
					{
						if ($victim->{team} eq "Infected" && $v_role ne "" && $v_role ne "infected")
						{
							&EvPlayerAction(
								$k_userid,
								$k_uniqueid,
								"killed_".lc($v_role),
								$x,
								$y,
								$z,
								$properties
							);
						}
						elsif ($victim->{team} eq "Survivor")
						{
							&EvPlayerPlayerAction(
								$k_userid,
								$k_uniqueid,
								$v_userid,
								$v_uniqueid,
								"killed_survivor",
								$x,
								$y,
								$z,
								$vx,
								$vy,
								$vz,
								$properties
							);
						}
					}
				}
			}
			else
			{
				# print "was TK";
				if ($weapon eq "dod_bomb_target")
				{
					$desc = "IGNORED BOMBED TEAMKILL DODS ";
					return $desc . $killerstr . " killed " . $victimstr . " with \"".$weapon."\"";
				}
		      
				# Teamkill
				&::RecordEvent(
					"Teamkills", 0,
					$killer->{playerid},
					$victim->{playerid},
					$weapon,
					$x,
					$y,
					$z,
					$vx,
					$vy,
					$vz
				);
				
				my $tk_penalty = (-1) * $server->{tk_penalty};

				$killer->increment('skill', $tk_penalty);
				$killer->increment('session_skill', $tk_penalty);
				
				if (!$::g_stdin && $server->{broadcasting_events} == 1)
				{
					my $colorparam = $server->{format_color};
					my $msg = sprintf("%s lost %s points (%s) for team-killing", $killer->{name}, $tk_penalty, &::FormatNumber($killer->{skill}));
					
					my @rcmds;
					# Killer message
					if ($killer->IsReallyBot == 0 && $killer->{display_events} == 1 && $k_userid > 0)
					{
						my $cmd_str = sprintf("%s %s%s %s", $rcmd, $server->FormatUserId($k_userid), $colorparam, $server->EscapeRconArg($msg));
						push (@rcmds, $cmd_str);
					}
					if ($victim->{is_bot} == 0 && $victim->{display_events} == 1 && $v_userid > 0)
					{
						my $cmd_str = sprintf("%s %s%s %s", $rcmd, $server->FormatUserId($v_userid), $colorparam, $server->EscapeRconArg($msg));
						push (@rcmds, $cmd_str);
					}
					if (scalar(@rcmds) > 0)
					{
						$server->DoRconMulti(\@rcmds);
					}
				}
				&__UpdateWeaponKills($weapon, $headshot);
				
				$desc = "TEAMKILL: ";
			}
		}
		if ($isfake == 0)
		{
			$killer->increment('map_kills');
			if ($headshot == 1)
			{
				$killer->increment('map_headshots');
			}
			$killer->updateDB();
			$victim->increment('map_deaths');
			$victim->set('is_dead', 1);
			if ($victim->{auto_type} eq "kill")
			{
				&EvChat("say",
					$v_userid,
					$v_uniqueid,
					$victim->{auto_command}
				);
				$victim->updateDB();
			}
		}
	}
	else
	{
		$desc = "(IGNORED) NOPLAYERINFO: ";
	}
	
	# reset next kill headshot flag
	$server->{nextkillheadshot} = 0;

	return $desc . $killerstr . " killed " . $victimstr . " with \"".$weapon."\"";
}

sub __UpdateWeaponKills
{
	my ($weapon, $headshot) = @_;
	
	if ($headshot == 1)
	{
		my $query = "
			UPDATE
				hlstats_Weapons
			SET	
				kills = kills + 1,
				headshots = headshots +1
			WHERE
				game = ?
				AND code = ?
			";
		my @vals = ($::g_servers{$::s_addr}->{game}, $weapon);
		$::g_db->DoCachedQuery("event_update_weapon_hs", $query, \@vals);
	}
	else
	{
		my $query = "
			UPDATE
				hlstats_Weapons
			SET	
				kills = kills + 1
			WHERE
				game = ?
				AND code = ?
			";
		my @vals = ($::g_servers{$::s_addr}->{game}, $weapon);
		$::g_db->DoCachedQuery("event_update_weapon", $query, \@vals);
	}
	
	return;
}


#
# 010. Player-Player Actions
#

sub EvPlayerPlayerAction
{
	my ($playerId, $playerUniqueId, $victimId, $victimUniqueId, $action, $x, $y, $z, $vx, $vy, $vz, $properties) = @_;
	my $rcmd = $::g_servers{$::s_addr}->{broadcasting_command};
	
	my $desc = "";
	my $player = &::LookupPlayer($::s_addr, $playerId, $playerUniqueId);
	my $victim = &::LookupPlayer($::s_addr, $victimId, $victimUniqueId);
	my $playerstr = &::GetPlayerInfoString($player, $playerId);
	my $victimstr = &::GetPlayerInfoString($victim, $victimId);
	if ($playerId == $victimId)
	{
		$desc = "(IGNORED) PLAYER SAME AS VICTIM: ";
	}
	elsif ($::g_servers{$::s_addr}->{num_trackable_players} < $::g_servers{$::s_addr}->{minplayers})
	{
		$desc = "(IGNORED) NOTMINPLAYERS: ";
	}
	elsif ($::g_servers{$::s_addr}->CheckBonusRound())
	{
		$desc = "(IGNORED) BonusRound: ";
	}
	elsif ($player && $victim)
	{
		if (($::g_servers{$::s_addr}->{ignore_bots} == 1) && (($player->{is_bot} == 1) || ($victim->{is_bot} == 1)))
		{
			$desc = "(IGNORED) BOT: ";
		}
		else
		{
			if ($::g_servers{$::s_addr}->{play_game} == TF() && $action eq "medic_death")
			{
				#do heal points
				
				if (defined($properties->{ubercharge}) && $properties->{ubercharge} == 1)
				{
					EvPlayerAction(
						$playerId,
						$playerUniqueId,
						"killed_charged_medic",
						$x,
						$y,
						$z,
						$properties
					);
					EvPlayerPlayerAction(
						$playerId,
						$playerUniqueId,
						$victimId,
						$victimUniqueId,
						"killed_charged_medic",
						$x,
						$y,
						$z,
						$vx,
						$vy,
						$vz,
						$properties
					);
				}
			}
			
			my $map = $::g_servers{$::s_addr}->get_map();
			if (defined($::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$map."_$action"}) && $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$map."_$action"}{ppaction})
			{
				EvPlayerPlayerAction(
						$playerId,
						$playerUniqueId,
						$victimId,
						$victimUniqueId,
						$map."_$action",
						$x,
						$y,
						$z,
						$vx,
						$vy,
						$vz,
						$properties
					);
			}
			if (defined($::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}) && $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{ppaction})
			{
				my $actionname = $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{descr};
				my $actionid = $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{id};
				my $reward_player = $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{reward_player};
				my $reward_team = $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{reward_team};
				my $team = $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{team};
				my $coords;
				
				if (defined($properties->{assister_position}))
				{
					$coords = $properties->{assister_position};
					($x,$y,$z) = split(/ /,$coords);
				}
				elsif (defined($properties->{position}))
				{
					$coords = $properties->{position};
					($x,$y,$z) = split(/ /,$coords);
				}
				elsif (defined($properties->{attacker_position}))
				{
					$coords = $properties->{attacker_position};
					($x,$y,$z) = split(/ /,$coords);
				}
				
				if (defined($properties->{victim_position}))
				{
					$coords = $properties->{victim_position};
					($vx,$vy,$vz) = split(/ /,$coords);
				}
				
				&::RecordEvent(
					"PlayerPlayerActions", 0,
					$player->{playerid},
					$victim->{playerid},
					$actionid,
					$reward_player,
					$x,
					$y,
					$z,
					$vx,
					$vy,
					$vz
				);
				
				my $query = "
					UPDATE
						hlstats_Actions
					SET
						count=count+1 
					WHERE
						game = ?
						AND code = ?
				";
				my @vals = ($::g_servers{$::s_addr}->{game}, $action);
				$::g_db->DoCachedQuery("event_update_action", $query, \@vals);
				
				if ($reward_player != 0)
				{
					my $victimreward = $reward_player * -1;
					$player->increment("skill", $reward_player, 1);
					$player->increment("session_skill", $reward_player, 1);
					$victim->increment("skill", $victimreward, 1);
					$victim->increment("session_skill", $victimreward, 1);
					
					if ($::g_servers{$::s_addr}->{broadcasting_events} == 1)
					{
						if ($::g_servers{$::s_addr}->{broadcasting_player_actions} == 1)
						{
							my $verb = "";
							if ($reward_player < 0)
							{
								$verb = "lost";
							}
							else
							{
								$verb = "got";
							}
							my $colorparam = $::g_servers{$::s_addr}->{format_color};
							my $coloraction = $::g_servers{$::s_addr}->{format_action};
							my $colorend = $::g_servers{$::s_addr}->{format_actionend};
							my $p_name    = $player->{name};
							my $p_skill   = $player->{skill};
							my $v_name    = $victim->{name};
							my $v_skill   = $victim->{skill};
							my $msg = sprintf("%s %s %s points (%s) for %s%s%s against %s (%s)",$p_name,$verb,abs($reward_player), &::FormatNumber($p_skill),$coloraction,$actionname,$colorend, $v_name, &::FormatNumber($v_skill));
							my @rcmds;
							if (($player->{is_bot} == 0) && ($player->{display_events} == 1) && ($player->{userid} > 0))
							{
								my $p_userid  = $::g_servers{$::s_addr}->FormatUserId($player->{userid});
								my $cmd_str = sprintf("%s %s%s %s",$rcmd, $p_userid, $colorparam, $::g_servers{$::s_addr}->EscapeRconArg($msg));
								push(@rcmds, $cmd_str);
							}
							if (($victim->{is_bot} == 0) && ($victim->{display_events} == 1) && ($victim->{userid} > 0))
							{
								my $v_userid  = $::g_servers{$::s_addr}->FormatUserId($victim->{userid});
								my $cmd_str = sprintf("%s %s%s %s", $rcmd, $v_userid, $colorparam, $::g_servers{$::s_addr}->EscapeRconArg($msg));
								push(@rcmds, $cmd_str);
							}
							if (@rcmds)
							{
								$::g_servers{$::s_addr}->DoRconMulti(\@rcmds);
							}
						}
					}
				}
				if ($team && $reward_team != 0)
				{
					&__RewardTeam($team, $reward_team, $actionid, $actionname, $action);
				}
				
			}
			else
			{
				$desc = "(IGNORED) ";
			}
		}
	}
	else
	{
		$desc = "(IGNORED) NOPLAYERINFO: ";
	}

	return $desc . $playerstr . " triggered \"".$action."\" against " . $victimstr;
}


#
# E011. Player Objectives/Actions
#

sub EvPlayerAction
{
	my ($playerId, $playerUniqueId, $action, $x, $y, $z, $properties) = @_;
	my $rcmd = $::g_servers{$::s_addr}->{broadcasting_command};
	my $desc = "";
	my $player = &::LookupPlayer($::s_addr, $playerId, $playerUniqueId);
	my $playerstr = &::GetPlayerInfoString($player, $playerId);
	my $coords;
	
	if ($::g_servers{$::s_addr}->{num_trackable_players} < $::g_servers{$::s_addr}->{minplayers})
	{
		$desc = "(IGNORED) NOTMINPLAYERS: ";
	}
	elsif ($::g_servers{$::s_addr}->CheckBonusRound())
	{
		$desc = "(IGNORED) BonusRound: ";
	}
	elsif ($player)
	{
		if (($::g_servers{$::s_addr}->{ignore_bots} == 1) && ($player->{is_bot} == 1))
		{
			$desc = "(IGNORED) BOT: ";
			if ($action eq "Got_The_Bomb")
			{
				$player->set("has_bomb", "1", 1);
			}
			elsif ($action eq "Dropped_The_Bomb")
			{
				$player->set("has_bomb", "0", 1);
			}
			$player->updateDB();
		}
		else
		{
			if ($::g_servers{$::s_addr}->{play_game} == TF())
			{
				my $objectstring = "";
				if (defined($properties->{object}))
				{
					$objectstring = "_".lc($properties->{object});
					$objectstring =~ tr/ /_/;
				}
				my $eventstring = "";
				if (defined($properties->{event}))
				{
					$eventstring = "_".lc($properties->{event});
					$eventstring =~ tr/ /_/;
				}
				my $ownerstring = "";
				if (defined($properties->{objectowner}))
				{
					my $owner = $properties->{objectowner};
					if ($owner =~ /.+?<STEAM_[0-9]+:([0-9]+:[0-9]+)>.*/)
					{
						$owner = $1;
						if ($owner eq $player->{uniqueid})
						{
							$ownerstring = "owner_";
						}
					}
				}
				$action = $ownerstring.$action.$objectstring.$eventstring;
				
				if ($action eq "builtobject_obj_sentrygun")
				{
					$player->{last_sg_build}=$::ev_remotetime;
				}
				elsif ($action eq "builtobject_obj_dispenser")
				{
					$player->{last_disp_build}=$::ev_remotetime;
				}
				elsif ($action eq "builtobject_obj_teleporter_entrance")
				{
					$player->{last_entrance_build}=$::ev_remotetime;
				}
				elsif ($action eq "builtobject_obj_teleporter_exit")
				{
					$player->{last_exit_build}=$::ev_remotetime;
				}
				elsif ($action eq "flagevent_defended")
				{
					if ($player->{team} eq "Red")
					{
						$::g_servers{$::s_addr}->{lastredflagdefend} = $::ev_remotetime;
					}
					else
					{
						$::g_servers{$::s_addr}->{lastblueflagdefend} = $::ev_remotetime;
					}
				}
				elsif ($action eq "flagevent_dropped")
				{
					if ($player->{team} eq "Red" && ($::ev_remotetime - $::g_servers{$::s_addr}->{lastblueflagdefend}) <= 1)
					{
						$::g_servers{$::s_addr}->{lastblueflagdefend} = 0;
						$action="flagevent_dropped_death";
					}
					elsif ($player->{team} eq "Blue" && ($::ev_remotetime - $::g_servers{$::s_addr}->{lastredflagdefend}) <= 1)
					{
						$::g_servers{$::s_addr}->{lastredflagdefend} = 0;
						$action="flagevent_dropped_death";
					}
				}
				elsif ($action eq "player_extinguished")
				{
					$action = $player->{role}."_extinguish";
				}
				elsif ($action eq "kill assist" && $player->{role} eq "medic")
				{
					$action = "kill_assist_medic";
				}
				else
				{
					if (($action eq "owner_killedobject_obj_sentrygun" && ($::ev_remotetime - $player->{last_sg_build}) > 120) ||
						($action eq "owner_killedobject_obj_dispenser" && ($::ev_remotetime - $player->{last_disp_build}) > 120) ||
						($action eq "owner_killedobject_obj_teleporter_entrance" && ($::ev_remotetime - $player->{last_entrance_build}) > 120) ||
						($action eq "owner_killedobject_obj_teleporter_exit" && ($::ev_remotetime - $player->{last_exit_build}) > 120)
						)
					{
						return "(IGNORED) OBJECT MOVED: $playerstr triggered \"$action\"";
					}
				}
			}
			elsif ($::g_servers{$::s_addr}->{play_game} == TFC())
			{
				if ($action eq "Sentry_Built_Level_1")
				{
					$player->{last_sg_build}=$::ev_remotetime;
				}
				elsif ($action eq "Built_Dispenser")
				{
					$player->{last_disp_build}=$::ev_remotetime;
				}
				elsif ($action eq "Teleporter_Entrance_Finished")
				{
					$player->{last_entrance_build}=$::ev_remotetime;
				}
				elsif ($action eq "Teleporter_Exit_Finished")
				{
					$player->{last_exit_build}=$::ev_remotetime;
				}
				else
				{
					if (($action eq "Sentry_Dismantle" && ($::ev_remotetime - $player->{last_sg_build}) > 120) ||
						($action eq "Dispenser_Dismantle" && ($::ev_remotetime - $player->{last_disp_build}) > 120) ||
						($action eq "Teleporter_Entrance_Dismantle" && ($::ev_remotetime - $player->{last_entrance_build}) > 120) ||
						($action eq "Teleporter_Exit_Dismantle" && ($::ev_remotetime - $player->{last_exit_build}) > 120))
					{
						return "(IGNORED) OBJECT MOVED: " . $playerstr . " triggered \"$action\"";
					}
				}
			}
			elsif ($::g_servers{$::s_addr}->{play_game} == FF())
			{
				if ($action eq "build_sentrygun")
				{
					$player->{last_sg_build}=$::ev_remotetime;
				}
				elsif ($action eq "build_dispenser")
				{
					$player->{last_disp_build}=$::ev_remotetime;
				}
				else
				{
					if (($action eq "sentry_dismantled" && ($::ev_remotetime - $player->{last_sg_build}) > 120) ||
						($action eq "dispenser_dismantled" && ($::ev_remotetime - $player->{last_disp_build}) > 120))
					{
						return "(IGNORED) OBJECT MOVED: " . $playerstr . " triggered \"$action\"";
					}
				}
			}
			elsif ($::g_servers{$::s_addr}->{play_game} == NS())
			{
				my $typestring = "";
				if (defined($properties->{type})) {
					$typestring = "_".lc($properties->{type});
					$typestring =~ tr/ /_/;
				}
				$action .= $typestring;
			}
			
			if (defined($properties->{position}))
			{
				$coords = $properties->{position};
				($x,$y,$z) = split(/ /,$coords);
			}
			elsif (defined($properties->{assister_position}))
			{
				$coords = $properties->{assister_position};
				($x,$y,$z) = split(/ /,$coords);
			}
			elsif (defined($properties->{attacker_position}))
			{
				$coords = $properties->{attacker_position};
				($x,$y,$z) = split(/ /,$coords);
			}
			
			if ($action eq "headshot")
			{
				$::g_servers{$::s_addr}->{nextkillheadshot} = $player->{playerid}
			}
			elsif ($action eq "Got_The_Bomb")
			{
				$player->set("has_bomb", "1", 1);
			}
			elsif ($action eq "Dropped_The_Bomb")
			{
				$player->set("has_bomb", "0", 1);
			}

			my $map = $::g_servers{$::s_addr}->get_map();
			if (defined($::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$map."_$action"}) && $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$map."_$action"}{paction})
			{
				&EvPlayerAction(
						$playerId,
						$playerUniqueId,
						$map."_$action",
						$x,
						$y,
						$z,
						$properties
					);
			}
			if (defined($::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}) && $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{paction})
			{
				my $actionname = $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{descr};
				my $actionid = $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{id};
				my $reward_player = $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{reward_player};
				my $reward_team = $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{reward_team};
				my $team = $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{team};
				
				&::RecordEvent(
					"PlayerActions", 0,
					$player->{playerid},
					$actionid,
					$reward_player,
					$x,
					$y,
					$z
				);
				my $query = "
					UPDATE
						hlstats_Actions
					SET
						count=count+1 
					WHERE
						game = ?
						AND code = ?
				";
				my @vals = ($::g_servers{$::s_addr}->{game}, $action);
				$::g_db->DoCachedQuery("event_update_action", $query, \@vals);
				$player->increment("skill", $reward_player);
				$player->increment("session_skill", $reward_player);
				my $p_name = $player->{name};
				my $p_skill = $player->{skill};
				
				
				if ($reward_player != 0
					&& $::g_servers{$::s_addr}->{broadcasting_events} == 1
					&& $::g_servers{$::s_addr}->{broadcasting_player_actions} == 1
					)
				{
					my $p_userid  = $::g_servers{$::s_addr}->FormatUserId($player->{userid});
					if (($player->{is_bot} == 0) && ($player->{display_events} == 1) && ($player->{userid} > 0))
					{
						my $colorparam = $::g_servers{$::s_addr}->{format_color};
						my $coloraction = $::g_servers{$::s_addr}->{format_action};
						my $verb = "got";
						if ($reward_player < 0)
						{
							$verb = "lost";
						}
						my $msg = sprintf("%s %s %s points (%s) for %s%s", $p_name, $verb, abs($reward_player), &::FormatNumber($p_skill), $coloraction, $actionname);
						my $cmd_str = sprintf("%s %s%s %s",$rcmd,$p_userid,$colorparam,$::g_servers{$::s_addr}->EscapeRconArg($msg));
						$::g_servers{$::s_addr}->DoRcon($cmd_str);
					}
				} 
				$player->updateDB();
				
				if ($reward_team != 0 && $action ne "pointcaptured")
				{
					if (!$team)
					{
						$team = $player->{team};
					}
					&__RewardTeam($team, $reward_team, $actionid, $actionname, $action);
				}
			}
			else
			{
				$desc = "(IGNORED) ";
			}
		}
	}
	else
	{
		$desc = "(IGNORED) NOPLAYERINFO: ";
	}
	
	return $desc . $playerstr . " triggered \"$action\"";
}


#
# 012. Team Objectives/Actions
#

sub EvTeamAction
{
	my ($team, $action) = @_;
	my $rcmd = $::g_servers{$::s_addr}->{broadcasting_command};
	my $desc = "";
	if ($::g_servers{$::s_addr}->{num_trackable_players} < $::g_servers{$::s_addr}->{minplayers}) {
		$desc = "(IGNORED) NOTMINPLAYERS: ";

# Team events, such as Round_Win can still occur during Bonus Round		
#	} elsif (checkBonusRound()) {
#		$desc = "(IGNORED) BonusRound: ";

	} else {
		my $map = $::g_servers{$::s_addr}->get_map();
		if ((defined($::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}) && $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{taction}) || (defined($::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$map."_$action"}) && $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$map."_$action"}{taction})) {
			my $actionname = $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{descr};
			my $actionid = $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{id};
			my $reward_team = $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{reward_team};
			my $actionteam = $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{team};
			if ($actionteam eq "") {
				$actionteam = $team;
			}
			#print "T: ".$actionid." - ".$actionname." - ".$actionteam." - ".$reward_player." - ".$reward_team." - ".$team."\n";
			my $query = "
					UPDATE
						hlstats_Actions
					SET
						count=count+1 
					WHERE
						game = ?
						AND code = ?
				";
			my @vals = ($::g_servers{$::s_addr}->{game}, $action);
			$::g_db->DoCachedQuery("event_update_action", $query, \@vals);
			
			if ($::g_servers{$::s_addr}->{round_status} == 0 && $reward_team != 0)
			{
				__RewardTeam($actionteam, $reward_team, $actionid, $actionname, $action);
			}
		}
		else
		{
			$desc = "(IGNORED) ";
		}
	}
	if ($::g_servers{$::s_addr}->{round_status} == 0) {
		if (($action eq "CTs_Win")  || ($action eq "Bomb_Defused")) {
			$::g_servers{$::s_addr}->increment("round_status");
			$::g_servers{$::s_addr}->increment("ct_wins");
			$::g_servers{$::s_addr}->increment("map_ct_wins");
			$::g_servers{$::s_addr}->add_round_winner("ct");
			if ($action eq "Bomb_Defused") {
				$::g_servers{$::s_addr}->increment("bombs_defused");
			}  
		} elsif (($action eq "Terrorists_Win") || ($action eq "Target_Bombed")) {
			$::g_servers{$::s_addr}->increment("round_status");
			$::g_servers{$::s_addr}->increment("ts_wins");
			$::g_servers{$::s_addr}->increment("map_ts_wins");
			$::g_servers{$::s_addr}->add_round_winner("ts");
			if ($action eq "Target_Bombed") {
				$::g_servers{$::s_addr}->increment("bombs_planted");
			}  
		}
	}
	$::g_servers{$::s_addr}->updateDB();
	return $desc . "Team \"$team\" triggered \"$action\"";
}

#
# 013. World Objectives/Actions
#

sub EvWorldAction
{
	my ($action) = @_;
	my $rcmd = $::g_servers{$::s_addr}->{broadcasting_command};
	my $desc = "";
	my $act_players = $::g_servers{$::s_addr}->{num_trackable_players};
	my $min_players = $::g_servers{$::s_addr}->{minplayers};
	
	if ($act_players < $min_players) {
		$desc = "(IGNORED) NOTMINPLAYERS: ";
		if ($action eq "Round_Start") {
			$::g_servers{$::s_addr}->MessageAll(sprintf("HLstatsX:CE disabled! Need at least %s active players (%s/%s)", $min_players, $act_players, $min_players),0,1);
		}
	} else {
		my $map = $::g_servers{$::s_addr}->get_map();
		if ((defined($::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}) && $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{waction}) || (defined($::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$map."_$action"}) && $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$map."_$action"}{waction})) {
			my $actionname = $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{descr};
			my $actionid = $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{id};
			my $reward_team = $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{reward_team};
			my $team = $::g_games{$::g_servers{$::s_addr}->{game}}{actions}{$action}{team};
			my $query = "
				UPDATE
					hlstats_Actions
				SET	
					count=count+1 
				WHERE
					game=?
					AND code IN (?, ?)
				";
			$::g_queryqueue->enqueue('action_update_count');
			$::g_queryqueue->enqueue($query);
			$::g_queryqueue->enqueue([$::g_servers{$::s_addr}->{game}, $map."_$action", $action]);
			
			if ($team && $reward_team != 0) {
				__RewardTeam($team, $reward_team, $actionid, $actionname);
			}
		} else {
			$desc = "(IGNORED) ";
		}
	}
	if ($action eq "Round_End" || $action eq "Round_Win" || $action eq "Mini_Round_Win")
	{
		if ($action eq "Round_End")
		{
			$::g_servers{$::s_addr}->analyze_teams();
		}
		
		if (($::g_servers{$::s_addr}->{lastdisabledbonus}+5) < $::ev_remotetime && $::g_servers{$::s_addr}->{bonusroundignore} > 0)
		{
			$::g_servers{$::s_addr}->{bonusroundtime_ts} = $::ev_remotetime;
			$::g_servers{$::s_addr}->{lastdisabledbonus} = $::ev_remotetime;
			$::g_servers{$::s_addr}->{bonusroundtime_state} = 1;
			if ($act_players >= $min_players) {
				$::g_servers{$::s_addr}->MessageAll("Round Over - All actions/frags are ignored by HLstatsX:CE until the next round starts",0,1);
			}
		}

		while (my($pl, $player) = each(%::g_players) ) {
			if ($player->{connect_time} == 0) {
				$player->set("connect_time", time());
			}
		
			__EndKillStreak($player);
			
			if ($player->{auto_type} eq "end")
			{
				&EvChat("say",
					$player->{userid},
					$player->{uniqueid},
					$player->{auto_command}
				);
			}
			$player->updateDB();
		}
	} 

	
	if ($action eq "Round_Start" || $action eq "Mini_Round_Start")
	{
		$::g_servers{$::s_addr}->{bonusroundtime_state} = 0;
		if ($action eq "Round_Start")
		{
			$::g_servers{$::s_addr}->{round_status} = 0;
			$::g_servers{$::s_addr}->{ba_player_switch} = 0;
		}
		
		while (my($pl, $player) = each(%::g_players))
		{
			if ($player->{connect_time} == 0)
			{
				$player->set("connect_time", time());
			}  
			if ($action eq "Round_Start")
			{
				$player->set("is_dead", "0", 1);
				if ($player->{auto_type} eq "start")
				{
					&EvChat("say",
						$player->{userid},
						$player->{uniqueid},
						$player->{auto_command}
					);
				}
			}
			$player->updateDB();
		}
	}
	if ($action eq "Game_Commencing")
	{
		$::g_servers{$::s_addr}->{round_status} = 0;
		$::g_servers{$::s_addr}->{map_started} = time();
		$::g_servers{$::s_addr}->{map_rounds} = 0;
		$::g_servers{$::s_addr}->{map_ct_wins} = 0;
		$::g_servers{$::s_addr}->{map_ts_wins} = 0;
	}
	$::g_servers{$::s_addr}->updateDB();
	return $desc . "World triggered \"$action\" ($act_players/$min_players)";
}


#
# E014. Chat
#

sub EvChat
{
	my ($msg_type, $playerId, $playerUniqueId, $message) = @_;
	
	my $player = &::LookupPlayer($::s_addr, $playerId, $playerUniqueId);
	my $playerstr = &::GetPlayerInfoString($player, $playerId);
	
	if (($player) && ($player->{is_bot} == 0))
	{
		$player->updateDB();
		my $server = $::g_servers{$::s_addr};
		my $p_userid = $server->FormatUserId($player->{userid});
		my $messagelen = length($message);
		
		if ($::g_global_chat > 0 || $::g_log_chat > 0)
		{
			my $hlx_command = 0;
			my $cmd = $message;
			if (($cmd =~ /^\/?skill$/i) || ($cmd =~ /^\/?rank$/i) || ($cmd =~ /^\/?points$/i) || ($cmd =~ /^\/?place$/i) ||
				($cmd =~ /^\/?kdratio$/i) || ($cmd =~ /^\/?kdeath$/i) || ($cmd =~ /^\/?kpd$/i) ||
				($cmd =~ /^\/?session$/i) || ($cmd =~ /^\/?session_data$/i) ||
				($cmd =~ /^\/?top\d{1,2}?$/i) ||
				($cmd =~ /^\/?statsme$/i) ||
				($cmd =~ /^\/?next$/i) ||
				($cmd =~ /^\/?knife$/i) || ($cmd =~ /^\/?usp$/i)       || ($cmd =~ /^\/?glock$/i)     || ($cmd =~ /^\/?deagle$/i)  || 
				($cmd =~ /^\/?p228$/i)  || ($cmd =~ /^\/?m3$/i)        || ($cmd =~ /^\/?xm1014$/i)    || ($cmd =~ /^\/?mp5navy$/i)     ||
				($cmd =~ /^\/?tmp$/i)   || ($cmd =~ /^\/?p90$/i)       || ($cmd =~ /^\/?m4a1$/i)      || ($cmd =~ /^\/?ak47$/i)    ||
				($cmd =~ /^\/?sg552$/i) || ($cmd =~ /^\/?scout$/i)     || ($cmd =~ /^\/?awp$/i)       || ($cmd =~ /^\/?g3sg1$/i)   ||
				($cmd =~ /^\/?m249$/i)  || ($cmd =~ /^\/?hegrenade$/i) || ($cmd =~ /^\/?flashbang$/i) || ($cmd =~ /^\/?elite$/i)   ||
				($cmd =~ /^\/?aug$/i)   || ($cmd =~ /^\/?mac10$/i)     || ($cmd =~ /^\/?fiveseven$/i) || ($cmd =~ /^\/?ump45$/i)   ||
				($cmd =~ /^\/?sg550$/i) || ($cmd =~ /^\/?famas$/i)     || ($cmd =~ /^\/?galil$/i) ||
				($cmd =~ /^\/?maps$/i) || ($cmd =~ /^\/?map_stats$/i) || ($cmd =~ /^\/?map$/i) ||
				($cmd =~ /^\/?kill$/i) || ($cmd =~ /^\/?kills$/i) || ($cmd =~ /^\/?player_kills$/i) ||
				($cmd =~ /^\/?weapon$/i) || ($cmd =~ /^\/?weapons$/i) || ($cmd =~ /^\/?weapon_usage$/i) ||
				($cmd =~ /^\/?action$/i) || ($cmd =~ /^\/?actions$/i) || ($cmd =~ /^\/?hlx_menu$/i) ||
				($cmd =~ /^\/?status$/i) || ($cmd =~ /^\/?load$/i) || ($cmd =~ /^\/?pro$/i) || ($cmd =~ /^\/?servers$/i) ||
				($cmd =~ /^\/?clans$/i) || ($cmd =~ /^\/?cheaters$/i) || ($cmd =~ /^\/?bans$/i) || ($cmd =~ /^\/?statsme$/i) ||
				($cmd =~ /^\/?help$/i) || ($cmd =~ /^\/?timeleft$/i) || ($cmd =~ /^\/?nextmap$/i) || ($cmd =~ /^\/?thetime$/i) ||
				($cmd =~ /^\/?hlx_display/i) || ($cmd =~ /^\/?hlx_teams/i) || 
				($cmd =~ /^\/?hlx_set/i) || ($cmd =~ /^\/?hlx_chat/i) || ($cmd =~ /^\/?hlx_auto/i))
			{
				
				$hlx_command++;
			}

			if (($messagelen > 3) && ($messagelen < 15)) # filter buy scripts
			{
				if (($cmd =~ /ak47/i) || ($cmd =~ /ak/i) || ($cmd =~ /m4/i) || ($cmd =~ /m4a1/i) ||
					($cmd =~ /deagle/i) || ($cmd =~ /famas/i) || ($cmd =~ /galil/i) ||
					($cmd =~ /scout/i) || ($cmd =~ /awp/i) || ($cmd =~ /awm/i) ||
					($cmd =~ /aug/i) || ($cmd =~ /m249/i) || ($cmd =~ /para/i) ||
					($cmd =~ /sig/i) || ($cmd =~ /tmp/i) || ($cmd =~ /ak47/i) ||
					($cmd =~ /grenade/i) || ($cmd =~ /usp/i) || ($cmd =~ /glock/i))
				{
					
					$hlx_command++;
				}
			}

			if ($::g_log_chat > 0)
			{
				my $log = 1;
				if ($::g_log_chat_admins == 0)
				{
					my $steamid = $player->{uniqueid};
					if ($server->is_admin($steamid) == 1)
					{
						$log = 0;
					}
				}
				
				if (($hlx_command == 0) && ($log == 1))
				{
					my $saytype = 1;
					if ($msg_type eq "say_team")
					{
						$saytype++;
					}
					&::RecordEvent(
						"Chat", 
						0,
						$player->{playerid},
						$saytype,
						$message
					);
				}
			}

			if ($::g_global_chat > 0 && $hlx_command == 0)
			{
				my $p_name = $player->{name};
				my $dead = "";
				if ($player->{is_dead} == 1)
				{
					$dead = "*DEAD* ";
				}
				my $b_message = $dead.$p_name." (".$server->{name}."): ".$message;
				send_global_chat($b_message);
			}
		}

		if ($message =~ /^\/?hlx_set ([^ ]+) (.+)$/i)
		{
			my $set_field = lc($1);
			my $set_value = $2;
			
			if ($set_field eq "name" || $set_field eq "realname")
			{
				&updatePlayerProfile($player, "fullName", $set_value);
			}
			elsif ($set_field eq "email" || $set_field eq "e-mail")
			{
				&updatePlayerProfile($player, "email", $set_value);
			}
			elsif ($set_field eq "homepage" || $set_field eq "url")
			{
				&updatePlayerProfile($player, "homepage", $set_value);
			}
			elsif ($set_field eq "icq" || $set_field eq "uin")
			{
				&updatePlayerProfile($player, "icq", $set_value);
			}
		}
		elsif ($message =~ /^\/?hlx_hideranking$/i)
		{
			my $result = $::g_db->DoQuery("
				SELECT
					hideranking
				FROM
					hlstats_Players
				WHERE
					playerId = " . $player->{playerid}
			);
			my ($hideranking) = $result->fetchrow_array;
			$result->finish;
			
			my $hidedesc = "";
			
			if ($hideranking == 0)
			{
				$hideranking = 1;
				$hidedesc = "HIDDEN from";
			}
			else
			{
				$hideranking = 0;
				$hidedesc = "VISIBLE on";
			}
			
			$::g_queryqueue->enqueue('player_update_hiderank');
			$::g_queryqueue->enqueue("UPDATE hlstats_Players SET hideranking=? WHERE playerId=?");
			$::g_queryqueue->enqueue([$hideranking, $player->{playerid}]);
			
			if ($server->{player_events} == 1 && $player->{display_events} == 1)
			{
				my $playerName = &abbreviate($player->{name});
				my $rcmd = $server->{player_command};
				my $cmd_str = $rcmd." $p_userid ".$server->EscapeRconArg("'$playerName' is now $hidedesc the rankings");
				$server->DoRcon($cmd_str);
			}
		}
		
		if (($server->{player_events} == 1) && (($message =~ /^\/?hlx_auto ([^ ]+) ([^ ]+)$/i) || ($message =~ /^\/?hlx_auto_cmd ([^ ]+) ([^ ]+)$/i)))
		{
			my $type = lc($1);
			my $cmd  = lc($2);
			
			if (($type =~ /^start$/i) || ($type =~ /^end$/i) || ($type =~ /^kill$/i))
			{
				if (($cmd =~ /^\/?skill$/i) || ($cmd =~ /^\/?rank$/i) || ($cmd =~ /^\/?points$/i) || ($cmd =~ /^\/?place$/i) ||
					($cmd =~ /^\/?kdratio$/i) || ($cmd =~ /^\/?kdeath$/i) || ($cmd =~ /^\/?kpd$/i) ||
					($cmd =~ /^\/?session$/i) || ($cmd =~ /^\/?session_data$/i) ||
					($cmd =~ /^\/?top\d{1,2}?$/i) ||
					($cmd =~ /^\/?statsme$/i) ||
					($cmd =~ /^\/?next$/i) ||
					($cmd =~ /^\/?knife$/i) || ($cmd =~ /^\/?usp$/i)       || ($cmd =~ /^\/?glock$/i)     || ($cmd =~ /^\/?deagle$/i)  || 
					($cmd =~ /^\/?p228$/i)  || ($cmd =~ /^\/?m3$/i)        || ($cmd =~ /^\/?xm1014$/i)    || ($cmd =~ /^\/?mp5navy$/i)     ||
					($cmd =~ /^\/?tmp$/i)   || ($cmd =~ /^\/?p90$/i)       || ($cmd =~ /^\/?m4a1$/i)      || ($cmd =~ /^\/?ak47$/i)    ||
					($cmd =~ /^\/?sg552$/i) || ($cmd =~ /^\/?scout$/i)     || ($cmd =~ /^\/?awp$/i)       || ($cmd =~ /^\/?g3sg1$/i)   ||
					($cmd =~ /^\/?m249$/i)  || ($cmd =~ /^\/?hegrenade$/i) || ($cmd =~ /^\/?flashbang$/i) || ($cmd =~ /^\/?elite$/i)   ||
					($cmd =~ /^\/?aug$/i)   || ($cmd =~ /^\/?mac10$/i)     || ($cmd =~ /^\/?fiveseven$/i) || ($cmd =~ /^\/?ump45$/i)   ||
					($cmd =~ /^\/?sg550$/i) || ($cmd =~ /^\/?famas$/i)     || ($cmd =~ /^\/?galil$/i) ||
					($cmd =~ /^\/?maps$/i) || ($cmd =~ /^\/?map_stats$/i) || ($cmd =~ /^\/?map$/i) ||
					($cmd =~ /^\/?kill$/i) || ($cmd =~ /^\/?kills$/i) || ($cmd =~ /^\/?player_kills$/i) ||
					($cmd =~ /^\/?weapon$/i) || ($cmd =~ /^\/?weapons$/i) || ($cmd =~ /^\/?weapon_usage$/i) ||
					($cmd =~ /^\/?action$/i) || ($cmd =~ /^\/?actions$/i))
				{
					
					$player->{auto_type} = $type;
					$player->{auto_command} = $cmd;
					$player->{auto_time} = 0;
					$player->{auto_time_count} = 0;
					if ($server->{player_events} == 1)
					{
						if ($player->{display_events} == 1)
						{
							my $rcmd = $server->{player_command};
							my $cmd_str = $rcmd." $p_userid ".$server->EscapeRconArg("Set auto command to ".$player->{auto_command}." on ".$player->{auto_type}."!");
							$server->DoRcon($cmd_str);
						}
					}
				}
			}
		}
		if ($message =~ /^\/?hlx_auto clear$/i)
		{
			$player->{auto_type}    = "";
			$player->{auto_command} = "";
			if ($server->{player_events} == 1)
			{
				if ($player->{display_events} == 1)
				{
					my $rcmd = $server->{player_command};
					my $cmd_str = sprintf("%s %s %s", $rcmd, $p_userid, $server->EscapeRconArg("Auto command is disabled!"));
					$server->DoRcon($cmd_str);
				}  
			}
		}

		### Begin switching team balance
		elsif (($server->{player_events} == 1) && ($message =~ /^\/?hlx_teams([ ][0-9])?$/i))
		{
			my $steamid  = $player->{uniqueid};
			my $mode = -1;
			if ($1 eq " 0" || $1 eq " 1")
			{
				$mode = $1;
				$mode =~ s/^ //;
			}
			if ($mode > -1 && $server->is_admin($steamid) == 1)
			{
				if ($mode == 0)
				{
					$server->{ba_enabled} = 0;
					my $admin_msg = "AUTO-TEAM BALANCER disabled";
					my $cmd_str = "";
					if ($server->{player_admin_command} ne "")
					{
						$cmd_str = $server->{player_admin_command}." ".$server->EscapeRconArg($admin_msg);
					}
					elsif ($player->{display_events} == 1)
					{
						my $rcmd = $server->{player_command};
						$cmd_str = $rcmd." $p_userid ".$server->EscapeRconArg($admin_msg);
					}
					$server->DoRcon($cmd_str);
				}
				elsif ($mode == 1)
				{
					my $cmd_str = "";
					$server->{ba_enabled} = 1;
					my $admin_msg = "AUTO-TEAM BALANCER enabled";
					if ($server->{player_admin_command} ne "")
					{
						$cmd_str = $server->{player_admin_command}." ".$server->EscapeRconArg($admin_msg);
					}
					else
					{
						if ($player->{display_events} == 1)
						{
							my $rcmd = $server->{player_command};
							$cmd_str = $rcmd." $p_userid ".$server->EscapeRconArg($admin_msg);
						}
					}
					$server->DoRcon($cmd_str);
				}
			}
		}

		### Disabling hlx output
		elsif ($server->{player_events} == 1 && $message =~ /^\/?hlx_display\s?([01])$/i)
		{
			my $mode = $1;
			my $msg = "";
			
			if ($mode == 0)
			{
				$msg = "All console events are disabled!";
			}
			else
			{
				$msg = "All console events are enabled!";
			}
			$player->set("display_events", $mode);
			&updatePlayerProfile($player, "displayEvents", $mode);
			my $rcmd = $server->{player_command};
			my $cmd_str = $rcmd." $p_userid ".$server->EscapeRconArg($msg);
			$server->DoRcon($cmd_str);
		}

		### Disabling hlx global chat output
		elsif ($server->{player_events} == 1 && $message =~ /^\/?hlx_chat\s?([01])$/i)
		{
			my $mode = $1;
			my $msg = "";
			
			if ($mode == 0)
			{
				$msg = "Global chat output is disabled!";
			}
			else
			{
				$msg = "Global chat output is enabled!";
			}
			$player->set("display_chat", $mode);
			my $rcmd = $server->{player_command};
			my $cmd_str = $rcmd." $p_userid ".$server->EscapeRconArg($msg);
			$server->DoRcon($cmd_str);
		}

		### Skill Addon
		elsif ($server->{player_events} == 1 && ($message =~ /^\/?skill([ ][0-9]+)?$/i || $message =~ /^\/?rank([ ][0-9]+)?$/i || $message =~ /^\/?points([ ][0-9]+)?$/i || $message =~ /^\/?place([ ][0-9]+)?$/i))
		{
			my $error = 0;
			if ($1)
			{
				my $userid = $1;
				$userid =~ s/^ //;
				my $found = 0;
				while (my($pl, $s_player) = each(%::g_players) )
				{
					if ($userid == $s_player->{userid})
					{
						$player = $s_player;
						$found++;
					}
				}
				if ($found == 0)
				{
					$error++;
				}
			}
			my $playerName = $player->{name};
			my ($skill, $ranknumber, $totalplayers) = get_player_rank($player);
			my $cmd_str = "";
			if ($ranknumber == 0)
			{
				$ranknumber = "(HIDDEN)";
			}

			if ($error == 0)
			{
				if ($message !~ /^\/?place([ ][0-9]+)?$/i)
				{
					my $rcmd = $server->{player_command_osd};
					
					if ($rcmd ne "")
					{
						my ($skill, $kills, $deaths, $kd, $suicides, $headshots, $hpk, $acc, $connection_time, $fav_weapon, $fav_weapon_kills, $fav_weapon_acc, $s_fav_weapon, $s_fav_weapon_kills, $s_fav_weapon_acc) = get_player_data($player, 0);
						my $osd_string = get_menu_text($player, $skill, $kills, $deaths, $kd, $suicides, $headshots, $hpk, $acc, $connection_time, $fav_weapon, $fav_weapon_kills, $fav_weapon_acc, $s_fav_weapon, $s_fav_weapon_kills, $s_fav_weapon_acc, $ranknumber, $totalplayers);
						$cmd_str = sprintf("%s \"15\" %s %s", $rcmd, $p_userid, $server->EscapeRconArg($osd_string));
					}
					else  # rank, fallback for no osd
					{
						$rcmd = $server->{player_command};
						my $msg = "";
						if ($::g_ranktype eq "kills")
						{
							my $kills = $player->{total_kills};
							$msg = sprintf("%s is on rank %d of %d with %d kills!", $playerName, $ranknumber, $totalplayers, $kills);
						}
						else
						{
							$msg = sprintf("%s is on rank %d of %d with %d points!", $playerName, $ranknumber, $totalplayers, $skill);
						}
						$cmd_str = sprintf("%s %s %s", $rcmd, $p_userid, $server->EscapeRconArg($msg));
					}  
				}
				elsif ($::g_servers{$::s_addr}->{"public_commands"} == 1)  # place
				{
					if ($::g_ranktype eq "kills")
					{
						my $kills = $player->{total_kills};
						$cmd_str = "";
						$server->MessageAll(sprintf("%s is on rank %d of %d with %d kills!", $playerName, $ranknumber, $totalplayers, $kills));
					}
					else
					{
						$cmd_str = "";
						$server->MessageAll(sprintf("%s is on rank %d of %d with %d points!", $playerName, $ranknumber, $totalplayers, $skill));
					}
				}
			}
			else
			{
				my $rcmd = $server->{player_command};
				if ($player->{display_events} == 1)
				{
					$cmd_str = "$rcmd $p_userid ".$server->EscapeRconArg("No player found with this userid. Type status in console to get players userid!");
				}  
			}
			if ($cmd_str ne "")
			{
				$server->DoRcon($cmd_str);
			}
		}
		### End of Skill Addon

		### Begin of Kill-Death Ratio
		elsif ($server->{player_events} == 1 && ($message =~ /^\/?kdratio([ ][0-9]+)?$/i || $message =~ /^\/?kdeath([ ][0-9]+)?$/i || $message =~ /^\/?kpd([ ][0-9]+)?$/i))
		{
			my $userid = 0;
			my $found = 0;
			my $cmd_str = "";
			if (!$1)
			{
				$found++;
			}
			else
			{
				$userid = $1;
				$userid =~ s/^ //;
				while (my($pl, $s_player) = each(%::g_players) )
				{
					if ($userid == $s_player->{userid})
					{
						$player = $s_player;
						$found++;
					}
				}
			}

			if ($found > 0 )
			{
				my ($skill, $kills, $deaths, $kd, $suicides, $headshots, $hpk, $acc, $connection_time, $fav_weapon, $fav_weapon_kills, $fav_weapon_acc, $s_fav_weapon, $s_fav_weapon_kills, $s_fav_weapon_acc, $ranknumber, $totalplayers) = get_player_data($player, 1);
				my $playerName = $player->{name};

				my $accstring = "";
				if ($acc ne "0.0")
				{
					$accstring = $acc."% accuracy,";
				}

				if ($message !~ /^\/?kdeath([ ][0-9]+)?$/i)
				{
					if ($server->{player_command_osd} ne "")
					{
						my $osd_string = get_menu_text($player, $skill, $kills, $deaths, $kd, $suicides, $headshots, $hpk, $acc, $connection_time, $fav_weapon, $fav_weapon_kills, $fav_weapon_acc, $s_fav_weapon, $s_fav_weapon_kills, $s_fav_weapon_acc, $ranknumber, $totalplayers);
						$osd_string = $server->EscapeRconArg($osd_string);
						$cmd_str = sprintf("%s \"10\" %s %s", $server->{"player_command_osd"}, $p_userid, $osd_string);
					}
					else
					{  
						if ($player->{display_events} == 1)
						{
							$cmd_str = $server->{player_command}." ".$p_userid." ".$server->EscapeRconArg(sprintf("%s has %d:%d frags, %d headshots (%s%%),%s and a KD-Radio of %s", $playerName, $kills, $deaths, $headshots, $hpk, $accstring, $kd));
						}  
					}
				}
				else
				{
					if ($server->{public_commands} == 1)
					{
						$cmd_str = "";
						$server->MessageAll(sprintf("%s has %d:%d frags, %d headshots (%s%%),%s and a KD-Ratio of %s", $playerName, $kills, $deaths, $headshots, $hpk, $accstring, $kd));
					}
					else
					{
						$cmd_str = $server->{player_command}." ".$p_userid." ".$server->EscapeRconArg(sprintf("%s has %d:%d frags, %d headshots (%s%%),%s and a KD-Ratio of %s", $playerName, $kills, $deaths, $headshots, $hpk, $accstring, $kd));
					}
				}
			}
			elsif ($player->{display_events} == 1)
			{
				$cmd_str = $server->{player_command}." ".$p_userid." ".$server->EscapeRconArg("No player found with this userid. Type status in console to get players userid!");
			}
			if ($cmd_str ne "")
			{
				$server->DoRcon($cmd_str);
			}

		}
		### End of Kill-Death Ratio

		### Begin of Session stats
		elsif ($server->{player_events} == 1 && ($message =~ /^\/?session([ ][0-9]+)?$/i || $message =~ /^\/?session_data([ ][0-9]+)?$/i))
		{
			my $error = 0;
			if ($1)
			{
				my $userid = $1;
				$userid =~ s/^ //;
				my $found = 0;
				while (my($pl, $s_player) = each(%::g_players) )
				{
					if ($userid == $s_player->{userid})
					{
						$player = $s_player;
						$found++;
					}
				}
				if ($found == 0)
				{
					$error++;
				}
			}
			my $playerName = $player->{name};
			my $kills      = $player->{session_kills};
			my $deaths     = $player->{session_deaths};
			my $headshots  = $player->{session_headshots};
			my $suicides   = $player->{session_suicides};
			my $skill      = $player->{session_skill};
			my $shots      = $player->{session_shots};
			my $hits       = $player->{session_hits};
			my $kdstring = "";
			my $cmd_str = "";
			my $kd = "";
			my $acc = "";
			my $hpk = "";
			
			if ($deaths > 0)
			{
				$kd = sprintf("%.3f", $kills/$deaths);
				$kdstring = sprintf(" (%.2f%%)", $kills/$deaths)
			}
			else
			{
				$kd = sprintf("%.3f", $kills);
			}
			if ($kills > 0)
			{
				$hpk = sprintf("%.0f", (100/$kills) * $headshots);
			}
			else
			{
				$hpk = sprintf("%.0f", $kills);
			}
			if ($shots > 0)
			{
				$acc = sprintf("%.1f", (100/$shots) * $hits);
			}
			else
			{
				$acc = sprintf("%.1f", $shots);
			}
			my $accstring = "";
			if ($acc ne "0.0")
			{
				$accstring = $acc." accuracy,";
			}
			
			if ($error == 0)
			{
				my $pointstr="";
				if ($::g_ranktype ne "kills")
				{
					$pointstr = sprintf(" and a skill change of %d points", $skill);
				}
				my $msg = sprintf("%s has %d:%d frags%s, %d headshots (%s%%),%s%s", $playerName, $kills, $deaths, $kdstring, $headshots, $hpk, $accstring, $pointstr);
				if ($message !~ /^\/?session_data([ ][0-9]+)?$/i)
				{
					if ($server->{player_command_osd} ne "")
					{
						my ($se_skill, $se_kills, $se_deaths, $se_kd, $se_suicides, $se_headshots, $se_hpk, $se_acc, $se_connection_time, $se_fav_weapon, $se_fav_weapon_kills, $se_fav_weapon_acc, $se_s_fav_weapon, $se_s_fav_weapon_kills, $se_s_fav_weapon_acc, $se_ranknumber, $se_totalplayers) = get_player_data($player, 1);
						my $osd_string = get_menu_text($player, $se_skill, $se_kills, $se_deaths, $se_kd, $se_suicides, $se_headshots, $se_hpk, $se_acc, $se_connection_time, $se_fav_weapon, $se_fav_weapon_kills, $se_fav_weapon_acc, $se_s_fav_weapon, $se_s_fav_weapon_kills, $se_s_fav_weapon_acc, $se_ranknumber, $se_totalplayers);
						$osd_string = $server->EscapeRconArg($osd_string);
						$cmd_str = sprintf("%s \"10\" %s %s", $server->{player_command_osd}, $p_userid, $osd_string);
					}
					else
					{
						if ($player->{display_events} == 1)
						{
							$cmd_str = sprintf("%s %s %s", $server->{player_command}, $p_userid, $server->EscapeRconArg($msg));
						}  
					}  
				}
				else
				{
					if ($server->{public_commands} == 1)
					{
						$cmd_str = "";
						$server->MessageAll($msg);
					}
					else
					{
						$cmd_str = sprintf("%s %s %s", $server->{player_command}, $p_userid, $server->EscapeRconArg($msg));
					}
				}
			}
			else
			{
				if ($player->{display_events} == 1)
				{
					$cmd_str = $server->{player_command}." ".$p_userid." ".$server->EscapeRconArg("No player found with this userid. Type status in console to get players userid!");
				}
			}
			if ($cmd_str ne "")
			{
				$server->DoRcon($cmd_str);
			}
		}
		### End of Session stats

		### Begin of next Addon
		elsif ($message =~ /^\/?next$/i)
		{
			if ($server->{player_command_osd} ne "")
			{
				my $playerName = $player->{name};
				my ($ranknumber, $totalplayers, $osd_message) = get_next_ranks($player);
				my $cmd = $server->EscapeRconArg($osd_message);
				$cmd = sprintf("%s \"10\" %s %s", $server->{player_command_osd}, $p_userid, $cmd);
				$server->DoRcon($cmd);
			}
		} 

		### Begin of Top-Players Addon
		elsif ($message =~ /^\/?top\d{1,2}?$/i)
		{
			my $limit = 10;
			$message =~ /top(\d*)/i;
			if ($1 > 12)
			{
				$limit = 12;
			}
			else
			{
				$limit = $1;
			}
			if ($server->{player_command_osd} ne "")
			{
				my $result = $::g_db->DoQuery("
					SELECT
						$::g_ranktype, lastName, kpd
					FROM
						hlstats_Players
					WHERE
						game=".$::g_db->Quote($player->{game})."
						AND hideranking = 0        
						AND kills >= 1
					ORDER BY
						$::g_ranktype DESC, kpd DESC
					LIMIT 0, ".$limit);
					
				my $rankword = "";
				if ($::g_ranktype eq "kills")
				{
					$rankword = " kills";
				}
				
				my $osd_message = "->1 - Top Players\\n";
				my $i           = 0;
				my $last_base  = "";
				while (my ($base, $lastName) = $result->fetchrow_array)
				{
					$i++;
					if (length($lastName) > 20)
					{
						$lastName = substr($lastName, 0, 17)."...";
					}
					if ($last_base eq "")
					{
						$osd_message .= sprintf("   %02d  %s%s       -      %s", $i, &::FormatNumber($base), $rankword, $lastName)."\\n";
						$last_base   =  $base;
					}
					else
					{
						$osd_message .= sprintf("   %02d  %s%s  -%04d  %s", $i, &::FormatNumber($base), $rankword, ($last_base-$base), $lastName)."\\n";
					}
				}
				$result->finish;
				my $cmd = $server->EscapeRconArg($osd_message);
				$cmd = sprintf("%s \"15\" %s %s", $server->{player_command_osd}, $p_userid, $cmd);
				$server->DoRcon($cmd);

			}
			elsif ($server->{use_browser} > 0)
			{
				my $url = $server->{ingame_url};
				my $game = $server->{game};
				my $fullurl = $server->EscapeRconArg(sprintf("%s/ingame.php?game=%s&mode=players", $url, $game));
				my $browsecmd = $server->{browse_command};
				my $cmd = "";
				if ($server->{mod} eq "BEETLE")
				{
					$cmd = sprintf("%s %s say %s %s", $::g_servers{$::s_addr}->{exec_command}, $p_userid, $browsecmd, $fullurl);
				}
				else
				{
					$cmd = sprintf("%s %s %s", $browsecmd, $p_userid, $fullurl);
				}
				$::g_servers{$::s_addr}->DoRcon($cmd);
			} 
		}
		### End of Top10 Addon

		### The rest of these require the ingame browser. There is currently no fallback
		elsif ($::g_servers{$::s_addr}->{use_browser} > 0)
		{
			### Begin of statsme Addon
			if ($message =~ /^\/?statsme$/i)
			{
				my $p_playerid = $player->{playerid};
				my $url        = $::g_servers{$::s_addr}->{ingame_url};
				my $game       = $::g_servers{$::s_addr}->{game};
				my $fullurl   = $::g_servers{$::s_addr}->EscapeRconArg(sprintf("%s/ingame.php?game=%s&mode=statsme&player=%s", $url, $game, $p_playerid));
				my $browsecmd = $::g_servers{$::s_addr}->{browse_command};
				my $cmd = "";
				if ($::g_servers{$::s_addr}->{mod} eq "BEETLE")
				{
					$cmd = sprintf("%s %s say %s %s", $::g_servers{$::s_addr}->{exec_command}, $p_userid, $browsecmd, $fullurl);
				}
				else
				{
					$cmd = sprintf("%s %s %s", $browsecmd, $p_userid, $fullurl);
				}
				$::g_servers{$::s_addr}->DoRcon($cmd);
			}
			### End of statsme Addon

			### Begin Player-Weapons Addon
			elsif ($message =~ /^\/?weapon$/i || $message =~ /^\/?weapons$/i)
			{
				my $p_playerid = $player->{playerid};
				my $url        = $::g_servers{$::s_addr}->{ingame_url};
				my $game       = $::g_servers{$::s_addr}->{game};
				my $fullurl = $::g_servers{$::s_addr}->EscapeRconArg(sprintf("%s/ingame.php?game=%s&mode=weapons&player=%s", $url, $game, $p_playerid));
				my $browsecmd = $::g_servers{$::s_addr}->{browse_command};
				my $cmd = "";
				if ($::g_servers{$::s_addr}->{mod} eq "BEETLE")
				{
					$cmd = sprintf("%s %s say %s %s", $::g_servers{$::s_addr}->{exec_command}, $p_userid, $browsecmd, $fullurl);
				}
				else
				{
					$cmd = sprintf("%s %s %s", $browsecmd, $p_userid, $fullurl);
				}
				$::g_servers{$::s_addr}->DoRcon($cmd); 
			}
			### End of Player-Weapons Addon

			### Begin Player-Kills Addon
			elsif (($message =~ /^\/?kill$/i) || ($message =~ /^\/?kills$/i) || ($message =~ /^\/?player_kills$/i))
			{
				my $p_playerid = $player->{playerid};
				my $url        = $::g_servers{$::s_addr}->{ingame_url};
				my $game       = $::g_servers{$::s_addr}->{game};
				my $fullurl = $::g_servers{$::s_addr}->EscapeRconArg(sprintf("%s/ingame.php?game=%s&mode=kills&player=%s", $url, $game, $p_playerid));
				my $browsecmd = $::g_servers{$::s_addr}->{browse_command};
				my $cmd = "";
				if ($::g_servers{$::s_addr}->{mod} eq "BEETLE")
				{
					$cmd = sprintf("%s %s say %s %s", $::g_servers{$::s_addr}->{exec_command}, $p_userid, $browsecmd, $fullurl);
				}
				else
				{
					$cmd = sprintf("%s %s %s", $browsecmd, $p_userid, $fullurl);
				}
				$::g_servers{$::s_addr}->DoRcon($cmd);  
			}
			### End of Player-Kills Addon

			### Begin Player-Map Performance Addon
			elsif (($message =~ /^\/?maps$/i) || ($message =~ /^\/?map_stats$/i) || ($message =~ /^\/?map$/i))
			{
				my $p_playerid = $player->{playerid};
				my $url        = $::g_servers{$::s_addr}->{ingame_url};
				my $game       = $::g_servers{$::s_addr}->{game};
				my $fullurl   = $::g_servers{$::s_addr}->EscapeRconArg(sprintf("%s/ingame.php?game=%s&mode=maps&player=%s", $url, $game, $p_playerid));
				my $browsecmd = $::g_servers{$::s_addr}->{browse_command};
				my $cmd = "";
				if ($::g_servers{$::s_addr}->{mod} eq "BEETLE")
				{
					$cmd = sprintf("%s %s say %s %s", $::g_servers{$::s_addr}->{exec_command}, $p_userid, $browsecmd, $fullurl);
				}
				else
				{
					$cmd = sprintf("%s %s %s", $browsecmd, $p_userid, $fullurl);
				}
				$::g_servers{$::s_addr}->DoRcon($cmd);  
			}
			### End of Player-Map Performance Addon

			### Begin Help Addon
			elsif (($message =~ /^\/?help$/i) || ($message =~ /^\/?cmd$/i) || ($message =~ /^\/?cmds$/i) || ($message =~ /^\/?commands$/i))
			{
				my $url        = $::g_servers{$::s_addr}->{ingame_url};
				my $game       = $::g_servers{$::s_addr}->{game};
				my $fullurl = $::g_servers{$::s_addr}->EscapeRconArg(sprintf("%s/ingame.php?game=%s&mode=help", $url, $game));
				my $browsecmd = $::g_servers{$::s_addr}->{browse_command};
				my $cmd = "";
			
				if ($::g_servers{$::s_addr}->{mod} eq "BEETLE")
				{
					$cmd = sprintf("%s %s say %s %s", $::g_servers{$::s_addr}->{exec_command}, $p_userid, $browsecmd, $fullurl);
				}
				else
				{
					$cmd = sprintf("%s %s %s", $browsecmd, $p_userid, $fullurl);
				}
				$::g_servers{$::s_addr}->DoRcon($cmd);  
			}
			### End of Help Addon
			
			### status Addon
			elsif ($message =~ /^\/?status([ ][0-9]+)?$/i)
			{
				my $url        = $::g_servers{$::s_addr}->{ingame_url};
				my $server_id  = $::g_servers{$::s_addr}->{id};
				my $game       = $::g_servers{$::s_addr}->{game};
				if ($1)
				{
					$server_id = $1;
					$server_id =~ s/^ //;
				}
				my $fullurl = $::g_servers{$::s_addr}->EscapeRconArg(sprintf("%s/ingame.php?game=%s&mode=status&server_id=%s", $url, $game, $server_id));
				my $browsecmd = $::g_servers{$::s_addr}->{browse_command};
				my $cmd = "";
				if (($::g_servers{$::s_addr}->{mod} eq "BEETLE"))
				{
					$cmd = sprintf("%s %s say %s %s" , $::g_servers{$::s_addr}->{exec_command}, $p_userid, $browsecmd, $fullurl);
				}
				else
				{
					$cmd = sprintf("%s %s %s", $browsecmd, $p_userid, $fullurl);
				}
				$::g_servers{$::s_addr}->DoRcon($cmd);
			}
			### End status Addon
			
			### load Addon
			elsif ($message =~ /^\/?load$/i)
			{
				my $url        = $::g_servers{$::s_addr}->{ingame_url};
				my $server_id  = $::g_servers{$::s_addr}->{id};
				my $game       = $::g_servers{$::s_addr}->{game};
				my $fullurl = $::g_servers{$::s_addr}->EscapeRconArg(sprintf("%s/ingame.php?mode=status&server_id=%s&mode=load", $url, $server_id));
				my $browsecmd = $::g_servers{$::s_addr}->{browse_command};
				my $cmd = "";
				if ($::g_servers{$::s_addr}->{mod} eq "BEETLE")
				{
					$cmd = sprintf("%s %s say %s %s", $::g_servers{$::s_addr}->{exec_command}, $p_userid, $browsecmd, $fullurl);
				}
				else
				{
					$cmd = sprintf("%s %s %s", $browsecmd, $p_userid, $fullurl);
				}
				$::g_servers{$::s_addr}->DoRcon($cmd);
			}

			### servers Addon
			elsif ($message =~ /^\/?servers$/i)
			{
				my $url        = $::g_servers{$::s_addr}->{ingame_url};
				my $game       = $::g_servers{$::s_addr}->{game};
				my $fullurl = $::g_servers{$::s_addr}->EscapeRconArg(sprintf("%s/ingame.php?game=%s&mode=servers", $url, $game));
				my $browsecmd = $::g_servers{$::s_addr}->{browse_command};
				my $cmd = "";
				if ($::g_servers{$::s_addr}->{mod} eq "BEETLE")
				{
					$cmd = sprintf("%s %s say %s %s", $::g_servers{$::s_addr}->{exec_command}, $p_userid, $browsecmd, $fullurl);
				}
				else
				{
					$cmd = sprintf("%s %s %s", $browsecmd, $p_userid, $fullurl);
				}
				$::g_servers{$::s_addr}->DoRcon($cmd);
			}

			### cheaters Addon
			elsif ($message =~ /^\/?cheaters$/i || $message =~ /^\/?bans$/i)
			{
				my $url        = $::g_servers{$::s_addr}->{ingame_url};
				my $game       = $::g_servers{$::s_addr}->{game};
				my $fullurl = $::g_servers{$::s_addr}->EscapeRconArg(sprintf("%s/ingame.php?game=%s&mode=bans", $url, $game));
				my $browsecmd = $::g_servers{$::s_addr}->{browse_command};
				my $cmd = "";
				if ($::g_servers{$::s_addr}->{mod} eq "BEETLE")
				{
					$cmd = sprintf("%s %s say %s %s", $::g_servers{$::s_addr}->{exec_command}, $p_userid, $browsecmd, $fullurl);
				}
				else
				{
					$cmd = sprintf("%s %s %s", $browsecmd, $p_userid, $fullurl);
				}
				$::g_servers{$::s_addr}->DoRcon($cmd);
			}

			### Actions Addon
			elsif (($message =~ /^\/?action$/i) || ($message =~ /^\/?actions$/i))
			{
				my $p_playerid = $player->{playerid};
				my $url        = $::g_servers{$::s_addr}->{ingame_url};
				my $game       = $::g_servers{$::s_addr}->{game};
				my $fullurl = $::g_servers{$::s_addr}->EscapeRconArg(sprintf("%s/ingame.php?game=%s&mode=actions&player=%s", $url, $game, $p_playerid));
				my $browsecmd = $::g_servers{$::s_addr}->{browse_command};
				my $cmd = "";
				if ($::g_servers{$::s_addr}->{mod} eq "BEETLE")
				{
					$cmd = sprintf("%s %s say %s %s", $::g_servers{$::s_addr}->{exec_command}, $p_userid, $browsecmd, $fullurl);
				}
				else
				{
					$cmd = sprintf("%s %s %s", $browsecmd, $p_userid, $fullurl);
				}
				$::g_servers{$::s_addr}->DoRcon($cmd);
			}

			### Accuracy Addon
			elsif ($message =~ /^\/?accuracy$/i)
			{
				my $p_playerid = $player->{playerid};
				my $url        = $::g_servers{$::s_addr}->{ingame_url};
				my $game       = $::g_servers{$::s_addr}->{game};
				my $fullurl = $::g_servers{$::s_addr}->EscapeRconArg(sprintf("%s/ingame.php?game=%s&mode=accuracy&player=%s", $url, $game, $p_playerid));
				my $browsecmd = $::g_servers{$::s_addr}->{browse_command};
				my $cmd = "";
				if ($::g_servers{$::s_addr}->{mod} eq "BEETLE")
				{
					$cmd = sprintf("%s %s say %s %s", $::g_servers{$::s_addr}->{exec_command}, $p_userid, $browsecmd, $fullurl);
				}
				else
				{
					$cmd = sprintf("%s %s %s", $browsecmd, $p_userid, $fullurl);
				}
				$::g_servers{$::s_addr}->DoRcon($cmd);	 
			}

			### Targets Addon
			elsif ($message =~ /^\/?targets$/i || $message =~ /^\/?target$/i)
			{
				my $p_playerid = $player->{playerid};
				my $url        = $::g_servers{$::s_addr}->{ingame_url};
				my $game       = $::g_servers{$::s_addr}->{game};
				my $fullurl = $::g_servers{$::s_addr}->EscapeRconArg(sprintf("%s/ingame.php?game=%s&mode=targets&player=%s", $url, $game, $p_playerid));
				my $browsecmd = $::g_servers{$::s_addr}->{browse_command};
				my $cmd = "";
				if ($::g_servers{$::s_addr}->{mod} eq "BEETLE")
				{
					$cmd = sprintf("%s %s say %s %s", $::g_servers{$::s_addr}->{exec_command}, $p_userid, $browsecmd, $fullurl);
				}
				else
				{
					$cmd = sprintf("%s %s %s", $browsecmd, $p_userid, $fullurl);
				}
				$::g_servers{$::s_addr}->DoRcon($cmd);
			}

			### Clans Addon
			elsif ($message =~ /^\/?clans$/i)
			{
				my $url        = $::g_servers{$::s_addr}->{ingame_url};
				my $game       = $::g_servers{$::s_addr}->{game};
				my $fullurl = $::g_servers{$::s_addr}->EscapeRconArg(sprintf("%s/ingame.php?game=%s&mode=clans", $url, $game));
				my $browsecmd = $::g_servers{$::s_addr}->{browse_command};
				my $cmd = "";
				if ($::g_servers{$::s_addr}->{mod} eq "BEETLE")
				{
					$cmd = sprintf("%s %s say %s %s", $::g_servers{$::s_addr}->{exec_command}, $p_userid, $browsecmd, $fullurl);
				}
				else
				{
					$cmd = sprintf("%s %s %s", $browsecmd, $p_userid, $fullurl);
				}
				$::g_servers{$::s_addr}->DoRcon($cmd);	
			}
		}
	} # end if player  
    

	return $playerstr . " $msg_type \"$message\"";
}


#
# 019. Map
#

sub EvChangeMap
{
	my ($type, $newmap) = @_;
	
	$::g_servers{$::s_addr}->{map} = $newmap;
	$::g_servers{$::s_addr}->clear_winner();

	if ($type eq "loading")
	{
		while (my($pl, $player) = each(%::g_players) )
		{
			if ($player->{is_bot} == 1)
			{
				$player->updateDB();
				&::RemovePlayer($::s_addr, $player->{userid}, $player->{uniqueid}, 1);
			}
			else
			{
				__EndKillStreak($player);
			}
		}
		$::g_servers{$::s_addr}->setHlxCvars();
		return "Loading map \"$newmap\"";
	}
	elsif ($type eq "started")
	{
		$::g_servers{$::s_addr}->increment("map_changes");
		$::g_servers{$::s_addr}->{map_started} = time();
		$::g_servers{$::s_addr}->{map_rounds} = 0;
		$::g_servers{$::s_addr}->{map_ct_wins} = 0;
		$::g_servers{$::s_addr}->{map_ts_wins} = 0;
		$::g_servers{$::s_addr}->{map_ct_shots} = 0;
		$::g_servers{$::s_addr}->{map_ct_hits} = 0;
		$::g_servers{$::s_addr}->{map_ts_shots} = 0;
		$::g_servers{$::s_addr}->{map_ts_hits} = 0;
		$::g_servers{$::s_addr}->updateDB();
		while (my($pl, $player) = each(%::g_players) )
		{
			$player->set("team", "");
			$player->set("map_kills", "0");
			$player->set("map_deaths", "0");
			$player->set("map_headshots", "0");
			$player->set("map_shots", "0");
			$player->set("map_hits", "0");
			$player->{trackable} = 0;
		}
		$::g_servers{$::s_addr}->updatePlayerCount();
		$::g_servers{$::s_addr}->{map} = $newmap;
		&::PrintNotice("Current map for server \"$::s_addr\" is now \"" . $newmap . "\"");
		
		return "Started map \"$newmap\"";
	}
	else
	{
		return "Map \"$newmap\": $type";
	}
}


#
# 020. Rcon
#

sub EvRcon
{
	my ($type, $command, $password, $ipAddr) = @_;
	my $desc = "";
	
	if ($::g_rcon_record)
	{
		&::RecordEvent(
			"Rcon", 0,
			$type,
			$ipAddr,
			$password,
			$command
		);
	}
	else
	{
		$desc = "(IGNORED) ";
	}
	
	return $desc . "$type Rcon from \"$ipAddr\": \"$command\"";
}


#
# 500. Admin
#

sub EvAdmin
{
	my ($type, $message, $playerName) = @_;
	
	&::RecordEvent(
		"Admin", 0,
		$type,
		$message,
		$playerName
	);
	
	return "\"$type\"".($playerName?" (\"$playerName:\")":"")." \"$message\"";
}

#
# 501. Statsme (weapon)
#

sub EvStatsme
{
	my ($playerId, $playerUniqueId, $weapon, $shots, $hits, $headshots, $damage, $kills, $deaths) = @_;
	my $desc = "";
	my $player    = &::LookupPlayer($::s_addr, $playerId, $playerUniqueId);
	my $playerstr = &::GetPlayerInfoString($player, $playerId);

	if ($::g_servers{$::s_addr}->{num_trackable_players} < $::g_servers{$::s_addr}->{minplayers})
	{
		$desc = "(IGNORED) NOTMINPLAYERS: ";
	}
	elsif ($player)
	{
		if (($::g_servers{$::s_addr}->{ignore_bots} == 1) && ($player->{is_bot} == 1))
		{
			$desc = "(IGNORED) BOT: ";
		} else {
		
			if ($::g_servers{$::s_addr}->{play_game} == FOF()
				&& $weapon eq "bow"
				)
			{
				$weapon = "arrow";
			}
			
			if ($shots>0) 
			{
				$player->increment("shots",         $shots);
				$player->increment("map_shots",     $shots);
				$player->increment("session_shots", $shots);
				$::g_servers{$::s_addr}->increment("total_shots", $shots);
			}  
			if ($hits>0)
			{
				$player->increment("hits",          $hits);
				$player->increment("map_hits",      $hits);
				$player->increment("session_hits",  $hits);
				$::g_servers{$::s_addr}->increment("total_hits", $hits);
			}  
			$player->updateDB();
               
			my $player_team = $player->{team};
			if ($player_team eq "CT")
			{
				if ($shots>0) 
				{
					$::g_servers{$::s_addr}->increment("ct_shots", $shots);
					$::g_servers{$::s_addr}->increment("map_ct_shots", $shots);
				}  
				if ($hits>0) 
				{
					$::g_servers{$::s_addr}->increment("ct_hits", $hits);
					$::g_servers{$::s_addr}->increment("map_ct_hits", $hits);
				}  
			} elsif ($player_team eq "TERRORIST") {
				if ($shots>0) 
				{
					$::g_servers{$::s_addr}->increment("ts_shots", $shots);
					$::g_servers{$::s_addr}->increment("map_ts_shots", $shots);
				}
				if ($hits>0) 
				{
					$::g_servers{$::s_addr}->increment("ts_hits", $hits);
					$::g_servers{$::s_addr}->increment("map_ts_hits", $hits);
				}  
			}
			$::g_servers{$::s_addr}->updateDB();
                
			&::RecordEvent("Statsme", 0,
				$player->{playerid},
				$weapon,
				$shots,
				$hits,
				$headshots,
				$damage,
				$kills,
				$deaths
			);
		}          
	} else
    {
		$desc = "(IGNORED) NOPLAYERINFO: ";
    }
    return $desc . $playerstr . " STATSME weaponstats (weapon \"$weapon\") (shots \"$shots\") (hits \"$hits\") (headshots \"$headshots\") (damage \"$damage\") (kills \"$kills\") (deaths \"$deaths\")";
}

#
# 502. Statsme (weapon2)
#

sub EvStatsme2
{
    my ($playerId, $playerUniqueId, $weapon, $head, $chest, $stomach, $leftarm, $rightarm, $leftleg, $rightleg) = @_;

    my $desc = "";
    my $player = &::LookupPlayer($::s_addr, $playerId, $playerUniqueId);
    my $playerstr = &::GetPlayerInfoString($player, $playerId);

	if ($::g_servers{$::s_addr}->{num_trackable_players} < $::g_servers{$::s_addr}->{minplayers})
	{
		$desc = "(IGNORED) NOTMINPLAYERS: ";
	}
	elsif ($player)
	{
		if (($::g_servers{$::s_addr}->{ignore_bots} == 1) && ($player->{is_bot} == 1))
		{
			$desc = "(IGNORED) BOT: ";
		} else {
			if ($::g_servers{$::s_addr}->{play_game} == FOF()
				&& $weapon eq "bow"
				)
			{
				$weapon = "arrow";
			}
			
			&::RecordEvent("Statsme2", 0,
				$player->{playerid},
				$weapon,
				$head,
				$chest,
				$stomach,
				$leftarm,
				$rightarm,
				$leftleg,
				$rightleg
			);
			$player->updateDB();
		}
     }
     else
     {
		$desc = "(IGNORED) NOPLAYERINFO: ";
     }
     return $desc . $playerstr . " STATSME weaponstats2 (weapon \"$weapon\") (head \"$head\") (chest \"$chest\") (stomach \"$stomach\") (leftarm \"$leftarm\") (rightarm \"$rightarm\") (leftleg \"$leftleg\") (rightleg \"$rightleg\")";
}

#
# 503. Statsme (latency)
#

sub EvStatsme_Latency
{
	my ($playerId, $playerUniqueId, $ping) = @_;

	my $desc = "";
	my $player = &::LookupPlayer($::s_addr, $playerId, $playerUniqueId);
	my $playerstr = &::GetPlayerInfoString($player, $playerId);

	if (($player) && ($player->{is_bot} == 0))
	{
		&::RecordEvent(
			"StatsmeLatency", 0,
			$player->{playerid},
			$ping
		);
	}
	else
	{
		$desc = "(IGNORED) NOPLAYERINFO: ";
	}

	return $desc . $playerstr . " STATSME average latency \"$ping\"";
}

#
# 504. Statsme (time)
#

sub EvStatsme_Time
{
	my ($playerId, $playerUniqueId, $time) = @_;

	my $desc = "";
	my $player = &::LookupPlayer($::s_addr, $playerId, $playerUniqueId);
	my $playerstr = &::GetPlayerInfoString($player, $playerId);

	if (($player) && ($player->{is_bot} == 0))
	{
		&::RecordEvent(
			"StatsmeTime", 0,
			$player->{playerid},
			$time
		);
	}
	else
	{
		$desc = "(IGNORED) NOPLAYERINFO: ";
	}

	return $desc . $playerstr . " STATSME connection time \"$time\"";
}

#
# 505. Kill Location
#

sub EvKillLoc
{
	my ($properties) = @_;
	
	if (defined($properties->{attacker_position}))
	{
		my $coords = $properties->{attacker_position};
		($::g_servers{$::s_addr}->{nextkillx}, $::g_servers{$::s_addr}->{nextkilly}, $::g_servers{$::s_addr}->{nextkillz}) = split(/ /,$coords);
	}
	
	if (defined($properties->{victim_position}))
	{
		my $coords = $properties->{victim_position};
		($::g_servers{$::s_addr}->{nextkillvicx}, $::g_servers{$::s_addr}->{nextkillvicy}, $::g_servers{$::s_addr}->{nextkillvicz}) = split(/ /,$coords);
	}

	return sprintf("KILL LOCATION x=>%s, y=>%s, z=>%s stored for next kill", $::g_servers{$::s_addr}->{nextkillx}, $::g_servers{$::s_addr}->{nextkilly}, $::g_servers{$::s_addr}->{nextkillz});
}

#
# boolean SameTeam (string team1, string team2)
#
# This should be expanded later to allow for team alliances (e.g. TFC-hunted).
#

sub __SameTeam
{
	my ($team1, $team2) = @_;
	
	if (($team1 eq $team2) && (($team1 ne "Unassigned") || ($team2 ne "Unassigned")))
	{
		return 1;
	}

	return 0;
}

# Gives members of 'team' an extra 'reward' skill points. Members of the team
# who have been inactive (no events) for more than 2 minutes are not rewarded.
#

sub __RewardTeam
{
	my ($team, $reward, $actionid, $actionname, $actioncode) = @_;
	my $rcmd = $::g_servers{$::s_addr}->{broadcasting_command};
	
	&::PrintNotice("Rewarding team \"$team\" with \"$reward\" skill for action \"$actionid\" ...");
	my @userlist = ();
	foreach my $player (values(%::g_players))
	{
		my $player_team      = $player->{team};
		my $player_timestamp = $player->{timestamp};
		if ($::g_servers{$::s_addr}->{ignore_bots} == 0 || !$player->IsReallyBot())
		{
			if (($::ev_unixtime - $player_timestamp < 180) && ($player_team eq $team))
			{
				if ($::g_debug > 2)
				{
					&::PrintNotice("Rewarding " . $player->getInfoString() . " with \"$reward\" skill for action \"$actionid\"");
				}
				
				&::RecordEvent(
					"TeamBonuses", 0,
					$player->{playerid},
					$actionid,
					$reward
					);
				$player->increment("skill", $reward, 1);
				$player->increment("session_skill", $reward, 1);
				$player->updateDB();
			}
			if ($player->{is_bot} == 0 && $player->{userid} > 0 && $player->{display_events} == 1)
			{
				push(@userlist, $player->{userid});
			}    
		}
	}
	if (($::g_servers{$::s_addr}->{broadcasting_events} == 1) && ($::g_servers{$::s_addr}->{broadcasting_player_actions} == 1))
	{
		my $coloraction = $::g_servers{$::s_addr}->{format_action};
		my $verb = "got";
		if ($reward < 0)
		{
			$verb = "lost";
		}
		my $msg = sprintf("%s %s %s points for %s%s", $team, $verb, abs($reward), $coloraction, $actionname);
		$::g_servers{$::s_addr}->MessageMany($msg, 0, \@userlist);
	}
	
	return;
}

#
# array calcSkill (int skill_mode, int killerSkill, int killerKills, int victimSkill, int victimKills, string weapon)
#
# Returns an array, where the first index contains the killer's new skill, and
# the second index contains the victim's new skill. 
#

sub __CalcSkill
{
	my ($skill_mode, $killerSkill, $killerKills, $victimSkill, $victimKills, $weapon, $killerTeam) = @_;
	
	# ignored bots never do a "comeback"
	return ($killerSkill, $victimSkill) if ($killerSkill < 1);
	return ($killerSkill, $victimSkill) if ($victimSkill < 1);
	
	if ($::g_debug > 2)
	{
		&::PrintNotice("Begin calcSkill: killerSkill=$killerSkill");
		&::PrintNotice("Begin calcSkill: victimSkill=$victimSkill");
	}

	my $modifier = 1.00;
	# Look up the weapon's skill modifier
	if (defined($::g_games{$::g_servers{$::s_addr}->{game}}{weapons}{$weapon}))
	{
		$modifier = $::g_games{$::g_servers{$::s_addr}->{game}}{weapons}{$weapon}{modifier};
	}

	# Calculate the new skills
	
	my $killerSkillChange = 0;
	if ($::g_skill_ratio_cap > 0)
	{
		# SkillRatioCap, from *XYZ*SaYnt
		#
		# dgh...we want to cap the ratio between the victimkill and killerskill.  For example, if the number 1 player
		# kills a newbie, he gets 1000/5000 * 5 * 1 = 1 points.  If gets killed by the newbie, he gets 5000/1000 * 5 *1
		# = -25 points.   Not exactly fair.  To fix this, I'm going to cap the ratio to 1/2 and 2/1.
		# these numbers are designed such that an excellent player will have to get about a 2:1 ratio against noobs to
		# hold steady in points.
		my $lowratio = 0.7;
		my $highratio = 1.0 / $lowratio;
		my $ratio = ($victimSkill / $killerSkill);
		if ($ratio < $lowratio) { $ratio = $lowratio; }
		if ($ratio > $highratio) { $ratio = $highratio; }
		$killerSkillChange = $ratio * 5 * $modifier;
	}
	else
	{
		$killerSkillChange = ($victimSkill / $killerSkill) * 5 * $modifier;
	}

	if ($killerSkillChange > $::g_skill_maxchange)
	{
		&::PrintNotice("Capping killer skill change of $killerSkillChange to $::g_skill_maxchange") if ($::g_debug > 2);
		$killerSkillChange = $::g_skill_maxchange;
	}
	
	my $victimSkillChange = $killerSkillChange;

	if ($skill_mode == 1)
	{
		$victimSkillChange = $killerSkillChange * 0.75;
	}
	elsif ($skill_mode == 2)
	{
		$victimSkillChange = $killerSkillChange * 0.5;
	}
	elsif ($skill_mode == 3)
	{
		$victimSkillChange = $killerSkillChange * 0.25;
	}
	elsif ($skill_mode == 4)
	{
		$victimSkillChange = 0;
	}
	elsif ($skill_mode == 5)
	{
		#Zombie Panic: Source only
		#Method suggested by heimer. Survivor's lose half of killer's gain when dying, but Zombie's only lose a quarter. 
		if ($killerTeam eq "Undead")
		{
			$victimSkillChange = $killerSkillChange * 0.5;
		}
		elsif ($killerTeam eq "Survivor")
		{
			$victimSkillChange = $killerSkillChange * 0.25;
		}
	}
	
	if ($victimSkillChange > $::g_skill_maxchange)
	{
		&::PrintNotice("Capping victim skill change of $victimSkillChange to $::g_skill_maxchange") if ($::g_debug > 2);
		$victimSkillChange = $::g_skill_maxchange;
	}
	
	if ($::g_skill_maxchange >= $::g_skill_minchange)
	{
		if ($killerSkillChange < $::g_skill_minchange)
		{
			&::PrintNotice("Capping killer skill change of $killerSkillChange to $::g_skill_minchange") if ($::g_debug > 2);
			$killerSkillChange = $::g_skill_minchange;
		} 
	
		if (($victimSkillChange < $::g_skill_minchange) && ($skill_mode != 4))
		{
			::PrintNotice("Capping victim skill change of $victimSkillChange to $::g_skill_minchange") if ($::g_debug > 2);
			$victimSkillChange = $::g_skill_minchange;
		}
	}
	if (($killerKills < $::g_player_minkills ) || ($victimKills < $::g_player_minkills ))
	{
		$killerSkillChange = $::g_skill_minchange;
		if ($skill_mode != 4)
		{
			$victimSkillChange = $::g_skill_minchange;
		}
		else
		{
			$victimSkillChange = 0;
		}  
	}
	
	$killerSkill += $killerSkillChange;
	$victimSkill -= $victimSkillChange;
	
	# we want int not float
	$killerSkill = sprintf("%d", $killerSkill + 0.5);
	$victimSkill = sprintf("%d", $victimSkill + 0.5);
	
	if ($::g_debug > 2)
	{
		&::PrintNotice("End calcSkill: killerSkill=$killerSkill");
		&::PrintNotice("End calcSkill: victimSkill=$victimSkill");
	}

	return ($killerSkill, $victimSkill);
}

sub calcL4DSkill
{
	my ($killerSkill, $weapon, $difficulty) = @_;
	
	# ignored bots never do a "comeback"
	#return ($killerSkill, $victimSkill) if ($killerSkill < 1);
	#return ($killerSkill, $victimSkill)	if ($victimSkill < 1);
	
	if ($::g_debug > 2)
	{
		&::PrintNotice("Begin calcSkill: killerSkill=$killerSkill");
		# not used on l4d
		#PrintNotice("Begin calcSkill: victimSkill=$victimSkill");
	}

	my $modifier = 1.00;
	# Look up the weapon's skill modifier
	if (defined($::g_games{$::g_servers{$::s_addr}->{game}}{weapons}{$::weapon}))
	{
		$modifier = $::g_games{$::g_servers{$::s_addr}->{game}}{weapons}{$::weapon}{modifier};
	}
	
	# Calculate the new skills
	
	my $diffweight = 0.5;
	if ($difficulty > 0)
	{
		$diffweight = $difficulty / 2;
	}
	
	my $killerSkillChange = $modifier * $diffweight;

	if ($killerSkillChange > $::g_skill_maxchange)
	{
		&::PrintNotice("Capping killer skill change of $killerSkillChange to $::g_skill_maxchange") if ($::g_debug > 2);
		$killerSkillChange = $::g_skill_maxchange;
	}

	if ($::g_skill_maxchange >= $::g_skill_minchange && $killerSkillChange < $::g_skill_minchange)
	{
		&::PrintNotice("Capping killer skill change of $killerSkillChange to $::g_skill_minchange") if ($::g_debug > 2);
		$killerSkillChange = $::g_skill_minchange;
	}
	
	$killerSkill += $killerSkillChange;
	# we want int not float
	$killerSkill = sprintf("%d", $killerSkill + 0.5);
	
	if ($::g_debug > 2)
	{
		&::PrintNotice("End calcSkill: killerSkill=$killerSkill");
	}
	
	return $killerSkill;
}

sub __CheckMinPlayerRank
{
	my ($player, $player_rank) = @_;
	my $server = $::g_servers{$::s_addr};
	
	my $min_players_rank = $server->{min_players_rank};
	
	if (($min_players_rank > 0 || $player_rank == 0) && $player_rank > $min_players_rank)
	{
		my $steamid = $player->{uniqueid};
		my $p_steamid = $player->{plain_uniqueid};
		if ($server->is_admin($steamid) == 0)
		{
			if ($server->{game_engine} == 1)
			{
				$server->DoRcon("kick #".$player->{userid}." Not a Top $min_players_rank-Player");
			}
			else
			{
				$server->DoRcon("kickid ".$player->{userid}." Not a Top $min_players_rank-Player");
			}
		}
	}
	
	return;
}

1;
