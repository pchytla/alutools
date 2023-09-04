#!/usr/bin/perl -w
#
## Copyright (C) 2014 Piotr Chytla <pch@packetconsulting.pl>
##
## This program is free software; you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation; either version 2 of the License, or
## (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program; if not, write to the Free Software
## Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
#

use Getopt::Long;
use Net::SNMP qw( :snmp :asn1 );
use Time::HiRes qw( gettimeofday tv_interval );
use POSIX qw( :math_h );
use File::Basename;
use AluPorts;
use AluSVC;
use AluSAP;
use AluSDP qw( %sdptypes ) ;
use Mysnmp qw ( snmp_session my_walk my_bulk_walk );
use Utils qw( in_array conv32vlantodot convdotto32bit convsapnameto32bit conv32bittosapname portencap );
$|=1;

use constant VERSION => '0.1';

use constant IFDESCR => '.1.3.6.1.2.1.2.2.1.2';
use constant IFNAME => '.1.3.6.1.2.1.31.1.1.1.1';
use constant IFTYPE => '.1.3.6.1.2.1.2.2.1.3';
use constant IFALIAS => '.1.3.6.1.2.1.31.1.1.1.18';
use constant SAPLIST => '.1.3.6.1.4.1.6527.3.1.2.4.3.2.1.15';
use constant SERVTYPE => '.1.3.6.1.4.1.6527.3.1.2.4.2.2.1.3';
use constant SERVLONGNAME => '.1.3.6.1.4.1.6527.3.1.2.4.2.2.1.6';
use constant SERVNAME => '.1.3.6.1.4.1.6527.3.1.2.4.2.2.1.29';
use constant SDPLIST => '.1.3.6.1.4.1.6527.3.1.2.4.4.4.1.33';
use constant SDPBINDTYPE => '.1.3.6.1.4.1.6527.3.1.2.4.4.4.1.10';

my @ifoids = (  IFNAME,
		 IFDESCR,
		IFTYPE,
		IFALIAS 
		);

my @srvoids = ( SERVLONGNAME,
		SERVNAME,
		SERVTYPE,
		SAPLIST,
		SDPLIST,
		SDPBINDTYPE,
		);

my $hostnamearg;
my $communityarg;
my $routerfile;
my $match;
my $bulk;
my $help;
my $version;
my $outfile;
my $disableports;
my $disableservices;
my $t0=[gettimeofday()];

#undef - no response
# 0 - not Alu/TiMOS
# 1 - ALU/TiMOS
#
sub alu_check() {
	my $s=shift;

	my $r=$s->get_request( -varbindlist => [ '.1.3.6.1.2.1.1.1.0' ] );
	if (!defined($r)) {
		return undef;
	}

	if ($r->{'.1.3.6.1.2.1.1.1.0'} =~ m/TiMOS/) {	
		return 1;
	}

	return 0;
}

sub removebase() {
	my $href=shift;
	my $base=shift;
	my $r={};

	if (exists($href->{$base})) {
		return $href->{$base};
	}

	foreach my $x (keys(%{$href})) {
		my $n=$x;
		$n=~s/$base\.//;
		$r->{$n}=$href->{$x};
		delete $r->{$x};
	}

	return $r;
}


sub write_services() 
{
		my $hostnae=shift;
		my $svc=shift;
		return if (defined($disableservices));
	
		open(FDOUT,">$hostname".".svc") || die "Can't open $hostname".".svc - $!";

       		print FDOUT "srvid;servicetype;sap;sdp;servicelongname;serviceshortname\n";
		foreach my $s (sort { $a->get_id() <=> $b->get_id() } @{$svc}) {
				if ($s->csv()=~m/$match/) {
				print FDOUT $s->csv()."\n";
				}
		}

		close(FDOUT);
}

sub write_ports()
{
	my $hostname=shift;
	my $ports=shift;

	return if (defined($disableports));

	open(FDOUT,">$hostname".".ports") || die "Can't open $hostname".".ports - $!";

	print FDOUT "Port;ifDescr;ifAlias;Type\n";
       	foreach my $p (sort { $a->get_id() <=> $b->get_id() } @{&AluPorts::get_ethphys_ifaces($ports)}) {
			if ($p->csv()=~m/$match/) {
			print FDOUT $p->csv()."\n";
			}
	}

	close(FDOUT);
}

die("Wrong args") unless GetOptions( 'hostname|n=s' => \$hostnamearg, 
					'community|C=s' => \$communityarg, 
					'routerfile|r=s' => \$routerfile, 
					'version|V' => \$version, 
					'match|m=s' => \$match ,
					'bulk|b' => \$bulk ,
					'disable-ports|p' => \$disableports ,
					'disable-services|s' => \$disableservices ,
					'help|h' => \$help ,
				);
if( $help ) {
   print "Options:
   --hostname|n - Scan single hostname
   --communiy|C - SNMP Community
   --routerfile|r - Scan routers from file Format 'hostname;community'
   --match|m - Regular expression to Match
   --bulk|b - Use Bulk
   --disable-ports|p - Disable searching in ports ( default enabled )
   --disable-services|s - Disable searching in services (default enabled)
   --help|h - This help'
   --version|V - Version
";
   exit(0);
}


if (defined($version)) { 
	print "$0 version ".VERSION."\n";
	exit(0);
}

if (!defined($match)) {
	$match = qr/.*/;
}


if (!defined($routerfile) && !defined($hostnamearg)) {
	print "routefile or hostname must be set\n";
	exit(1);
}

if (defined($hostnamearg) && !defined($communityarg)) {
	print "Community must be set\n";
	exit(1);
}

if (!defined($routerfile)) {
	$routerfile="/tmp/".basename($0).".$$";
	open(FDOUT,">$routerfile") || die "Can't open file $routerfile $!";
	print FDOUT "$hostnamearg;$communityarg\n";
	close(FDOUT);
}

if (!open(FD,"<".$routerfile)) {
	print "Problem with file $routerfile can't open\n";
	exit(1);
}

if (defined($disableports)) {
	%svcoids=( 'IFNAME' => IFNAME );
}

if (defined($disableservices)) {
	%svcoids=();
}

my @ports;
my @svc;

while (<FD>) {
	if (m/^(\S+);(\S+)\s*$/) {
		$hostname=$1;
		$community=$2;
		print STDERR $hostname."\n";
	} else {
		print STDERR "Wrong Line : ".$_;
		next;
	}

	my $servlongname = {};
	my $servname = {};
	my $servtype = {};
	my $saplist = {};
	my $sdplist = {};
	my $sdpbindtype = {};
	my $ifdescr = {} ; 
	my $ifname= {}; 
	my $iftype= {} ; 
	my $ifalias= {} ;


	my $sess=&snmp_session($hostname,$community,'snmpv2c',0);
	my $alu=&alu_check($sess);

	if (!defined($alu)) {
		print "ERROR: no response from host!!!\n";
		next;
	}

	if (!$alu) {
		print "WARNING: $hostname is not TiMOS ( Alcatel-Lucent OS) !!!\n"
	}

	if (defined($bulk)) {
		$sess->close();
	}
	
	my $ifall;
	my $srvall;

	if (!defined($bulk)) {
	foreach my $oid (@ifoids) {
		$ifall->{$oid}=&removebase(&my_walk($sess,$oid),$oid);
	}
	} else {
		undef $sess;
		$sess=&snmp_session($hostname,$community,'snmpv2c',1);
                $ifall=&my_bulk_walk($sess, \@ifoids);
	}

	if (!defined($bulk)) {
	foreach my $oid (@srvoids) {
		$srvall->{$oid}=&removebase(&my_walk($sess,$oid),$oid);
	}
	} else {
		undef $sess;
		$sess=&snmp_session($hostname,$community,'snmpv2c',1);
                $srvall=&my_bulk_walk($sess, \@srvoids);
	}

        $ifname=&removebase($ifall,IFNAME);
        $ifdescr=&removebase($ifall,IFDESCR);
        $ifalias=&removebase($ifall,IFALIAS);
        $iftype=&removebase($ifall,IFTYPE);

	$servlongname=&removebase($srvall,SERVLONGNAME);
	$servname=&removebase($srvall,SERVNAME);
	$servtype=&removebase($srvall,SERVTYPE);
	$saplist=&removebase($srvall,SAPLIST);
	$sdplist=&removebase($srvall,SDPLIST);
	$sdpbindtype=&removebase($srvall,SDPBINDTYPE);

	my $s;
	#porty
	foreach $s (keys(%{$ifname})) {
		push(@ports,new AluPorts($s,$iftype->{$s},$ifdescr->{$s},$ifname->{$s},$ifalias->{$s}));
	}
	
	#services / long name
	foreach $s (keys(%{$servlongname})) {
		my $n=&AluSVC::find_svc(\@svc,$s);
		next if(defined($n));
		push(@svc,new AluSVC($s,$servtype->{$s},$servlongname->{$s},$servname->{$s})) ;
	}
	# short name
	foreach $s (keys(%{$servname})) {
		my $n=&AluSVC::find_svc(\@svc,$s);
		next if(defined($n));
		push(@svc,new AluSVC($s,$servtype->{$s},$servlongname->{$s},$servname->{$s}));
	}

#	##sap-y
	foreach $s (keys(%{$saplist})) {
		my @saps=split(/\./,$s);
		my $port;
	
		$port=$ifname->{$saps[1]};
		my $vlan=&conv32vlantodot($saps[2]);
		my $sap=&portencap($port,$vlan);

		foreach my $c (@svc) {
			next if ($c->get_id()!=$saps[0]);
			$c->add_sap($sap);
		}

	}

#### spoke/mesh-sdp
	foreach $s (keys(%{$sdplist})) {
		my $type='unknown';
		my @sdp=split(/\./,$s);
		my $sdpid=pow(2,24)*$sdp[1]+pow(2,16)*$sdp[2]+pow(2,8)*$sdp[3]+$sdp[4];
		my $vcid=pow(2,24)*$sdp[5]+pow(2,16)*$sdp[6]+pow(2,8)*$sdp[7]+$sdp[8];
		if (exists($sdpbindtype->{$s})) {
			$type=$sdptypes{$sdpbindtype->{$s}};
		} 

		foreach my $c (@svc) {
			next if ($c->get_id()!=$sdp[0]);
			$c->add_sdp($sdpid.":".$vcid,$type);
		}
	}
	$sess->close;
	
	&write_ports($hostname,\@ports);
	&write_services($hostname,\@svc);

}

close(FD);
if (defined($hostnamearg)) {
	unlink($routerfile);
}

print $0." Work time ".sprintf("%f",tv_interval($t0))." sec\n";
exit 0;
