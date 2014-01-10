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

package HLstats_DB;

use strict;
use warnings;
use Carp;

#
# Constructor
#

sub new
{
	my ($class_name, $host, $name, $user, $pass) = @_;
	
	my $self = {};
	bless($self, $class_name);
	
	# Initialise Properties
	$self->{conn}        = undef;
	$self->{stmt_cache}  = ();
	$self->{host}        = $host;
	$self->{name}        = $name;
	$self->{user}        = $user;
	$self->{pass}        = $pass;

	$self->__Connect();

	&::PrintNotice("Created new database object");
	return $self;
}


#
# __connect
#
# Connects to the database, clears cached queries, and sets UTF-8
#

sub __Connect
{
	my ($self) = @_;
	
	my $connString = "DBI:mysql:".$self->{name}.":".$self->{host};
	$self->{conn} = DBI->connect($connString, $self->{user}, $self->{pass})
		or die "Unable to connect to database: $DBI::errstr\n";
	
	$self->{conn}->{AutoCommit}           = 1;
	$self->{conn}->{mysql_auto_reconnect} = 1;
	$self->{conn}->{mysql_enable_utf8}    = 1;
	
	$self->{conn}->do("SET NAMES 'utf8'");
	&::PrintEvent("MYSQL", "Connecting to MySQL database '".$self->{name}."' on '".$self->{host}."' as user '".$self->{user}."' ... connected ok", 1);
	$self->{stmt_cache} = ();
	
	return;
}


#
# result DoQuery (string query)
#
# Executes the SQL query 'query' and returns the result identifier.
#

sub DoQuery
{
	my ($self, $query, $callref) = @_;
	
	my $result = $self->{conn}->prepare($query) or croak("Unable to prepare query:\n$query\n$DBI::errstr\n$callref");
	$result->execute or croak("Unable to execute query:\n$query\n$DBI::errstr\n$callref");
	
	return $result;
}


#
# DoFastQuery (string query)
#
# Executes the SQL query 'query', disregarding any result
#

sub DoFastQuery
{
	my ($self, $query) = @_;
	$self->{conn}->do($query);
	
	return;
}


#
# DoCachedQuery (string queryId, query, bindArgs)
#
# Executes the SQL query 'query', caching it if it is not already cached
#

sub DoCachedQuery
{
	my ($self, $queryId, $query, $bindArgs) = @_;
	
	my $sth = $self->{stmt_cache}{$queryId};
	if (!$sth)
	{
		$self->{stmt_cache}{$queryId} = $self->{conn}->prepare($query) or croak("Unable to prepare query ($queryId):\n$query\n$DBI::errstr");
		$sth = $self->{stmt_cache}{$queryId};
		#::PrintEvent("HLSTATSX", "Prepared a statement ($query_id) for the first time.", 1);
	}
	$sth->execute(@{$bindArgs}) or croak("Unable to execute query ($queryId):\n$query\n$DBI::errstr");
	
	return $sth;
}


#
# string Quote (string strToQuote)
#
# Escapes dangerous characters in a variable, making it suitable for use in an
# SQL query. Returns the escaped version pre-quoted.
#

sub Quote
{
	my ($self, $toQuote) = @_;
	return $self->{conn}->quote($toQuote);
}


#
# int GetInsertId
#
# Returns the id of the last inserted row
#

sub GetInsertId
{
	my ($self) = @_;
	
	return $self->{conn}->{mysql_insertid};
}

1;
