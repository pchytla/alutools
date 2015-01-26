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
use POSIX qw( :math_h );
use File::Basename;
use AluPorts;
use AluSVC;
use AluSAP;
use AluSDP qw( %sdptypes ) ;
$|=1;

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

my $hostnamearg;
my $communityarg;
my $routerfile;
my $match = qr/.+/;
my $help;
my $version;
my $outfile;
my $ports;
my $service;


## {{

sub conv32vlantodot() {
        my ($encapvalue) = @_;
        my $cvlan=$encapvalue>>16;
        my $svlan=$encapvalue&0x0000ffff;

        if ($encapvalue<=4096) {
                return $encapvalue;
        }

        return $svlan.".".$cvlan;
}

# }}

# {{ 

sub convdotto32bit() {
        my ($vlanstr) = @_;
        my @vlan=split(/\./,$vlanstr);
        if (!defined($vlan[1])){
                push(@vlan,0);
        }
        return $vlan[1]*655535+$vlan[0];
}

# }}

# {{

sub convsapnameto32bit() {
        my ($sapstr) = @_;
        my @saparr=split(/:/,$sapstr);
        if (!defined($saparr[1])) {
                        return $saparr[0];
        }
        return $saparr[0].":".&convdotto32bit($saparr[1]);

}
# }}

# {{

sub conv32bittosapname() {
        my ($sapstr) = @_;
        my @saparr=split(/:/,$sapstr);
        if (!defined($saparr[1])) {
                        return $saparr[0];
        }
        return $saparr[0].":".&conv32vlantodot($saparr[1]);
}

# }}

sub snmp_session() {
	my $hostname=shift;
	my $community=shift;
	my $ver=shift;
	my ( $snmpsession, $err ) =  Net::SNMP->session(
                                                 -version    => $ver,
                                                 -hostname   => $hostname,
                                                 -timeout    => 5,
                                                 -retries    => 3,
                                                 -community   => $community,
                                                );

       	if ($err) { 
			print STDERR "ERR: Blad polaczenia $hostname\n";
			exit(0);
	}
	return $snmpsession;
}

sub alu_check() {
	my $s=shift;

	my $r=$s->get_request( -varbindlist => [ '.1.3.6.1.2.1.1.1.0' ] );
	if (!defined($r)) {
		return 0;
	}

	if ($r->{'.1.3.6.1.2.1.1.1.0'} =~ m/TiMOS/) {	
		return 1;
	}

	return 0;
}

sub my_walk() {
	my $s=shift;
	my $oid=shift;
	my $baseoid=$oid;
	my %r;
	my $res;
	outer: while ($res=$s->get_next_request(-varbindlist => [$oid])) {
        	my @k=keys(%{$res});
        	$oid=$k[0];
        	last outer unless($oid =~ m/$baseoid/);
		$r{$oid}=$res->{$oid};
	}
	if (!defined($res)) {
			print STDERR $s->{'_hostname'}." : ERR: OID($baseoid) ".$s->error."\n";
	}
	return \%r;
}

sub removebase() {
	my $href=shift;
	my $base=shift;

	foreach my $x (keys(%{$href})) {
		my $n=$x;
		$n=~s/$base\.//;
		$href->{$n}=$href->{$x};
		delete $href->{$x};
	}

	return $href;
}


sub in_array()
{
   my ($arr,$e) = @_;

   my $str=join('',map { $_ eq $e } @{$arr});
   return 1 if ($str);
   return 0;
}


sub write_out()
{
	my $name=shift;
	my $str=shift;

	if (!open(FDOUT,">>$name")) {
		print STDERR "Problem z utworzeniem $name\n";
		exit(0);
	}
	print FDOUT $str."\n";
	close(FDOUT);
}


die("Wrong args") unless GetOptions( 'hostname|n=s' => \$hostnamearg, 
					'community|C=s' => \$communityarg, 
					'routerfile|r=s' => \$routerfile, 
					'version|V' => \$version, 
					'match|m=s' => \$match ,
					'ports|p' => \$searchports ,
					'service|s' => \$searchports ,
					'help|h' => \$help ,
				);
if( $help ) {
   print "Options:
   --hostname|n -- Scan single hostname
   --communiy|C -- SNMP Community
   --routerfile|r - Scan routers from file Format 'hostname;community'
   --match|m - - Regular expression to Match'
   --ports|p - - Search for ports ( description )'
   --service|s - - Search for service ( servicelongname / servcieshortname )'
   --help|h - - This help'
   --version|V - Version
";
   exit(0);
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
	&write_out($routerfile,"$hostnamearg;$communityarg");
}

if (!open(FD,"<".$routerfile)) {
	print "Problem with file $routerfile can't open\n";
	exit(1);
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

	my $sess=&snmp_session($hostname,$community,'snmpv2c');
	my $alu=&alu_check($sess);

	if (!$alu) {
		print "WARNING: $hostname is not TiMOS ( Alcatel-Lucent OS) !!!"
	}

	my $ifdescr=&removebase(&my_walk($sess,IFDESCR),IFDESCR);
	my $ifname=&removebase(&my_walk($sess,IFNAME),IFNAME);
	my $iftype=&removebase(&my_walk($sess,IFTYPE),IFTYPE);
	my $ifalias=&removebase(&my_walk($sess,IFALIAS),IFALIAS);
	my $servlongname = {};
	my $servname = {};
	my $servtype = {};
	my $saplist = {};
	my $sdplist = {};
	my $sdpbindtype = {};
 
	if ($alu) {
		$servlongname=&removebase(&my_walk($sess,SERVLONGNAME),SERVLONGNAME);
		$servname=&removebase(&my_walk($sess,SERVNAME),SERVNAME);
		$servtype=&removebase(&my_walk($sess,SERVTYPE),SERVTYPE);
		$saplist=&removebase(&my_walk($sess,SAPLIST),SAPLIST);
		$sdplist=&removebase(&my_walk($sess,SDPLIST),SDPLIST);
		$sdpbindtype=&removebase(&my_walk($sess,SDPBINDTYPE),SDPBINDTYPE);
	}

	my $s;
	#porty
	foreach $s (keys(%{$ifname})) {
		next unless ($ifdescr->{$s}=~m/$match/i);
		push(@ports,new AluPorts($s,$iftype->{$s},$ifdescr->{$s},$ifname->{$s},$ifalias->{$s}));
	}

	#services / long name
	foreach $s (keys(%{$servlongname})) {
		next unless ($servlongname->{$s}=~m/$match/i);
		push(@svc,new AluSVC($s,$servtype->{$s},$servlongname->{$s},$servname->{$s}));
	}
	# short name
	foreach $s (keys(%{$servname})) {
		next unless ($servname->{$s}=~m/$match/i);
		my $n=&AluSVC::find_svc(\@svc,$s);
		push(@svc,new AluSVC($s,$servtype->{$s},$servlongname->{$s},$servname->{$s})) unless ($n);
	}
#	##sap-y
	foreach $s (keys(%{$saplist})) {
		my @saps=split(/\./,$s);
		my $port;
	
		$port=$ifname->{$saps[1]};
		my $sap;
		my $vlan=&conv32vlantodot($saps[2]);
		#Null
		if ($vlan==0) {
			$sap=$port;
		#:* gwiazdka
		} elsif ($vlan==4095) {
			$sap=$port.":*";
		} else {
		#dot1q/qinq
			$sap=$port.":".$vlan;
		}

		foreach my $c (@svc) {
			next if ($c->get_id()!=$saps[0]);
			$c->add_sap($sap);
		}

		#Check if SAP is on Phisical Interface that we 
		#added to @ports if so add all services on this port
		#
		foreach my $p (@ports) {
			next if ($p->get_id()!=$saps[1]);		
			#
			my $n=&AluSVC::find_svc(\@svc,$saps[0]);
			if (!$n) {
				push(@svc,new AluSVC($saps[0],$servtype->{$saps[0]},$servlongname->{$saps[0]},$servname->{$saps[0]}));
				$svc[scalar(@svc)-1]->add_sap($sap);
			}
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

       &write_out("./".$hostname.".ports","Port;ifDescr;ifAlias;Type");
       foreach my $p (sort { $a->get_id() <=> $b->get_id() } @{&AluPorts::get_ethphys_ifaces(\@ports)}) {
		&write_out("./".$hostname.".ports",$p->csv());
	}
       &write_out("./".$hostname.".svc","srvid;servicetype;sap;sdp;servicelongname;serviceshortname");
	foreach my $s (sort { $a->get_id() <=> $b->get_id() } @svc) {
		&write_out("./".$hostname.".svc",$s->csv());
	}

}

close(FD);
if (defined($hostnamearg)) {
	unlink($routerfile);
}
exit 0;
