#!/usr/bin/perl -w
#
## Copyright (C) 2015 Piotr Chytla <pch@packetconsulting.pl>
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
use Socket;
use POSIX qw( :math_h strftime );
use File::Basename;
use Math::Trig qw( :pi :radial deg2rad );
use Utils qw( in_array conv32vlantodot portencap );
use AluPorts qw( get_aluporttype );
use JSON;
use Net::SNMP qw( :snmp :asn1 oid_base_match snmp_dispatcher oid_lex_sort );
sub fix() { return shift; };
$|=1;

use constant VERSION => '0.7';

use constant MAX_ISIS_METRIC => 16777215;
use constant vRtrID=>1;
use constant isisSysInstance=>0;
#        If multi-topology is not supported for the route then the value of
#         tmnxIsisRouteMtId should be 0."
use constant tmnxIsisRouteMtId=>0;
#OIDS
use constant IFDESCR => '.1.3.6.1.2.1.2.2.1.2';
use constant IFNAME => '.1.3.6.1.2.1.31.1.1.1.1';
use constant IFTYPE => '.1.3.6.1.2.1.2.2.1.3';
use constant ipAdEntNetMask => '1.3.6.1.2.1.4.20.1.3';
use constant ipNetToMediaType => '1.3.6.1.2.1.4.22.1.4';
#ISIS-MIB
use constant isisISAdjNeighSysID => '.1.3.6.1.3.37.1.5.1.1.5';  
#TIMETRA-ISIS-NG-MIB
use constant tmnxIsisISAdjNeighborIP => '.1.3.6.1.4.1.6527.3.1.2.88.3.1.1.3.1';
use constant tmnxIsisHostName => '.1.3.6.1.4.1.6527.3.1.2.88.1.4.1.2';
use constant tmnxIsisRouteMetric => '.1.3.6.1.4.1.6527.3.1.2.88.1.5.1.9';
use constant tmnxIsisIfLevelOperMetric => '.1.3.6.1.4.1.6527.3.1.2.88.2.2.1.10';
use constant tmnxIsisISAdjCircLevel => '.1.3.6.1.4.1.6527.3.1.2.88.3.1.1.2.1';
#Physical port / encap
use constant vRtrIfName => '.1.3.6.1.4.1.6527.3.1.2.3.4.1.4';
use constant vRtrIfType => '.1.3.6.1.4.1.6527.3.1.2.3.4.1.3';
use constant vRtrIfPortID => '.1.3.6.1.4.1.6527.3.1.2.3.4.1.5';
use constant vRtrIfEncapValue => '.1.3.6.1.4.1.6527.3.1.2.3.4.1.7';
use constant vRtrIfServiceId => '.1.3.6.1.4.1.6527.3.1.2.3.4.1.37';

my %vRtrIsisISAdjCircLevel = (
         1 => 'level1',
         2 => 'level2',
         3 => 'level1L2',
         4 => 'unknown',
       );

my %ipNetToMediaType =  (
                1 =>'other',
                2 => 'invalid',     
                3 => 'dynamic' ,
                4 => 'static',
            );

my %tmnxIsisRouteDestType = ( 
                     'unknown'=>0,
                     'ipv4'=>1,
                     'ipv6'=>2,
                     'ipv4z'=>3,
                     'ipv6z'=>4,
                     'dns'=>16,
                 );

#community.txt
my %alucommunity = ( );

my $help;
my $outfile;
my $nobulk;
my $single;
my $metricsort=1;
my $metric;
my $geosort;
my $geofile;
my %geocords;
my $hostnamereg;
my $output="network.json";
##
my @all; 
my @cur_hosts; 
my $topology= { 'edges' => {} , 'nodes' => { }  };
#
my $tt=0;
my $starthostname;
my $startip;

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
			print STDERR "ERR: Connection error  $hostname\n";
			return "ERR_NORESP";
	}
	return $snmpsession;
}

#
# return:
#	ALU_SAS - TIMOS-B - Alcatel 7210 SAS-M/X switch
#	ALU_RTR -  TIMOS-C Alcatel 77XX SR router
#	ALU_OTHER 
#	NONALU 
#	undef 
   
sub alu_check() {
	my $s=shift;
	my $sysdescr=shift;

	if (exists($topology->{'nodes'}->{$s->{'_hostname'}}->{'sysdescr'})) {
			$$sysdescr=$topology->{'nodes'}->{$s->{'_hostname'}}->{'sysdescr'};
			return $topology->{'nodes'}->{$s->{'_hostname'}}->{'type'};
	}

	my $r=$s->get_request( -varbindlist => [ '.1.3.6.1.2.1.1.1.0' ] );
	if (!defined($r)) {
		return undef;
	}

	$$sysdescr=$r->{'.1.3.6.1.2.1.1.1.0'};
	$$sysdescr=~s/[\n\r]/ /g;

	if ($r->{'.1.3.6.1.2.1.1.1.0'} =~ m/TiMOS-C/i) {	
		return 'ALU_RTR';
	}

	if ($r->{'.1.3.6.1.2.1.1.1.0'} =~ m/TiMOS-B/i) {	
		return 'ALU_SAS';
	}
	
	if ($r->{'.1.3.6.1.2.1.1.1.0'} =~ m/TiMOS/i) {	
		return 'ALU_OTHER';
	}

	return 'NONALU';
}

sub find_community() {
	my $hostname=shift;
	my $community=shift;

	if (exists($alucommunity{$hostname})) {
			return $alucommunity{$hostname};
	}

	foreach my $p (keys(%alucommunity)) {
		if ($hostname =~ m/$p/ )  { 
				return $alucommunity{$p};
		}
	}

	return $community;
}

#tmnxIsisRouteEntry is indexed as follow ( based on TIMETRA-ISIS-NG-MIB.mib - SROS: 19.10.X)
#
#    INDEX       {
#        vRtrID,
#        isisSysInstance,
#        tmnxIsisRouteMtId,
#        tmnxIsisRouteDestType,
#        tmnxIsisRouteDest,
#        tmnxIsisRoutePrefixLength,
#        tmnxIsisRouteNexthopIPType,
#        tmnxIsisRouteNexthopIP
#    }

sub buildv4_IsisRouteMetric_OID() {
	my $metricoid=shift;
	my $ip=shift;
	my $prefix=shift;
	my $nexthop=shift;
	my $desttype=$tmnxIsisRouteDestType{'ipv4'};
	my $destlen=4;
	#
	return $metricoid.".".vRtrID.".".isisSysInstance.".".tmnxIsisRouteMtId.".".$desttype.".".$destlen.".".$ip.".".$prefix.".".$desttype.".".$destlen.".".$nexthop;
}

#tmnxIsisHostEntry is indexed as follow ( based on TIMETRA-ISIS-NG-MIB.mib - SROS: ver 19.10.X)
#
#    INDEX       {
#        vRtrID,
#        isisSysInstance,
#        tmnxIsisHostSysID
#    }

sub build_isishostname_OID() {
	my $hostnameoid=shift;
	my $systemid=shift;
	if (ref($systemid) ne 'ARRAY') { 
		print STDERR "ERR: build_isishostname_OID : systemid is not ARRAY-REF\n";
		return undef;
	}
	my $systemidlen=scalar(@{$systemid});
	$isishostnameoid=$hostnameoid.".".vRtrID.".".isisSysInstance.".".$systemidlen.".".join('.',@{$systemid});
	return $isishostnameoid;
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
	my %ret;
	foreach my $x (keys(%{$href})) {
		if ($x=~m/^$base\.(.+)$/) { 
			my $n=$1;
			$ret{$n}=$href->{$x};
		}
	}

	return \%ret;
}


sub table_cb_bulk() {
	my ($session, $baseoid, $table) = @_;
	my $result;

       if (!defined($session->var_bind_list)) {
                printf("%s ERROR: %s\n", $session->{'_hostname'},$session->error);
		return;
        } 

       my @next=();

        foreach my $oid (oid_lex_sort(keys(%{$session->var_bind_list}))) {
	   my $b=undef;
	   for (my $i=0;$i<scalar(@{$baseoid});$i++) {
	   	if (oid_base_match($baseoid->[$i],$oid)) {
			$oid=~s/\s*$//;
           		$next[$i]=$oid;
			$b=$baseoid->[$i];
			last;
	   	}  
	   }

	  $table->{$oid} = $session->var_bind_list->{$oid} if (defined($b));
        }

	#usuwamy undefy
	my @fnext=map(defined($_)?$_:(), @next);

        if (scalar(@fnext)>0) {

           $result = $session->get_bulk_request(
              -callback       => [\&table_cb_bulk, $baseoid, $table],
              -maxrepetitions => 10,
              -varbindlist    => \@fnext
           );

           if (!defined($result)) {
              printf("%s ERROR: %s\n", $session->{'_hostname'},$session->error);
           }

        } 
}


sub my_bulk_walk() 
{
	my $hostname=shift;
	my $community=shift;
	my $baseoidref = shift;
	my %ret;

       my ($sess,$err)=Net::SNMP->session(
                                                -version    => 'snmpv2c',
                                                -hostname   => $hostname,
                                                 -nonblocking => 1,
                                                 -timeout    => 3,
                                                 -retries    => 1,
                                                 -community   => $community,
                                                );
        if ($err) {
                print "$hostname - Connection error $community Err($err)\n";
                return "ERR_NORESP";
        }

	$sess->translate(['-octetstring'=> 0x0 ]);

        my $r=$sess->get_bulk_request( -callback       => [ \&table_cb_bulk , $baseoidref, \%ret ] ,
                                     -maxrepetitions => 10,
                                     -varbindlist    => $baseoidref,
                                        );
        if (!defined($r)) {
                print "$hostname -> ".$sess->error."\n";
                return "ERR_NORESP";
        }

	$sess->snmp_dispatcher();

	$sess->close();
	return \%ret;
}

sub write_data() {
	my $json=JSON->new();
	$json->pretty();
	open(FILE,">".$output);
	print FILE $json->encode($topology);
	close(FILE);

}

sub sig_handler {
	print "QUITing ...\n";
	&write_data();
	exit(0);
}

sub route_metric {
	my $h=shift;
	return 0 if ($h eq $starthostname);
	return exists($topology->{'nodes'}->{$h}->{'metric'})?$topology->{'nodes'}->{$h}->{'metric'}:MAX_ISIS_METRIC-1;
}

sub push_to_queue() {
	my $n=shift;

	if (!&in_array(\@all,$n)) {
		push(@cur_hosts,$n);
		push(@all,$n);
	}

}

#shortest distance over the earth’s surface – using the ‘Haversine’ formula.
#source stackoverlow
#
sub getDistanceFromLatLonInKm() {
  my $lat1=shift;
  my $lon1=shift;
  my $lat2=shift;
  my $lon2=shift;

  my $R = 6371; # Radius of the earth in km
  my $dLat = deg2rad($lat2-$lat1);  
  my $dLon = deg2rad($lon2-$lon1); 
  my $a = 
    sin($dLat/2) * sin($dLat/2) +
    cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * 
    sin($dLon/2) * sin($dLon/2)
    ; 
  my $c = 2 * atan2(sqrt($a), sqrt(1-$a)); 
  return $R * $c; #Distance in km
}

sub get_geo_distance() {
	my $h1=$starthostname;
	my $h2=shift;
	$h1=~m/$hostnamereg/;
	my $kod1=$1;
	$h2=~m/$hostnamereg/;
	my $kod2=$1;
	if (!defined($kod1) || !defined(!$kod2)) {
			return MAX_ISIS_METRIC-1;
	}
	if (!exists($geocords{$kod1}) || !exists($geocords{$kod2})) {
			return MAX_ISIS_METRIC-1;
	}

	return &getDistanceFromLatLonInKm($geocords{$kod1}{'lat'},$geocords{$kod1}{'long'},$geocords{$kod2}{'lat'},$geocords{$kod2}{'long'});
}

sub edge_exists {
	my $h1=shift;
	my $h2=shift;
	return 0 unless (exists($topology->{'edges'}->{$h1}));
	return 0 unless (exists($topology->{'edges'}->{$h1}->{$h2}));
	return 1;
}


sub get_isis_route_metric() {
	my $hostname=shift;
	my $comm=shift;
	my $netmask;
	foreach my $h (@cur_hosts) {
		my $sys;
		$community=&find_community($h,$comm);
		my $sess=&snmp_session($h,$community,'snmpv2c');
		next if (!ref($sess) && $sess =~ m/ERR_/);
		my $alu=&alu_check($sess,\$sys);
		if (!defined($alu)) {
			printf ("%s ERROR: no response from host!!!\n",$h);
			$topology->{'nodes'}->{$h}->{'noresponse'}=1;
			next;
		}

		if ($alu!~m/^ALU_/) {
			print "WARNING: $h is not TiMOS ( Alcatel-Lucent OS) !!!\n";
			$topology->{'nodes'}->{$h}->{'sysdescr'}=$sys;
			$topology->{'nodes'}->{$h}->{'type'}=$alu;
			$sess->close();
			next;
		}

		$topology->{'nodes'}->{$h}->{'sysdescr'}=$sys;
		$topology->{'nodes'}->{$h}->{'type'}=$alu;

		$isisadjip=&removebase(&my_walk($sess,tmnxIsisISAdjNeighborIP),tmnxIsisISAdjNeighborIP);
		foreach my $oid (keys(%{$isisadjip})) {
			my $metricoid=&buildv4_IsisRouteMetric_OID(tmnxIsisRouteMetric,$startip,32,$isisadjip->{$oid});
			my $rtmetric=$sess->get_request( -varbindlist => [ $metricoid ] );
			next if ( $rtmetric->{$metricoid} eq 'noSuchInstance' );
			$topology->{'nodes'}->{$h}->{'metric'}=$rtmetric->{$metricoid};
			last;
		}

		$sess->close();
		undef $sess;	
	}


}


sub isis_discovery
{
	my $hostname = shift;
	my $community = shift;
	my $sysdescr;

	@cur_hosts = ();

	#node allready scanned?
	if (exists($topology->{'nodes'}->{$hostname}->{'scanned'})) {
		return;
	}

	my $sess=&snmp_session($hostname,$community,'snmpv2c');
	if (!ref($sess) && $sess =~ m/ERR_/) {
		return $sess;
	}

	my $alu=&alu_check($sess,\$sysdescr);
	if (!defined($alu)) {
		printf ("%s ERROR: no response from host!!!\n",$hostname);
		return "ERR_NORESP";
	}

	if ($alu!~m/^ALU_/) {
		print "WARNING: $hostname is not TiMOS ( Alcatel-Lucent OS) !!!\n";
		$topology->{'nodes'}->{$hostname}->{'sysdescr'}=$sysdescr;
		$topology->{'nodes'}->{$hostname}->{'type'}=$alu;
		$sess->close();
		return "ERR_NONALU";
	}

	$topology->{'nodes'}->{$hostname}->{'scanned'}=1;
	$topology->{'nodes'}->{$hostname}->{'sysdescr'}=$sysdescr;
	$topology->{'nodes'}->{$hostname}->{'type'}=$alu;

	my $isisadjip;
	my $isisadjlevel;
	my $isisadjsystemid;
	my $ifname;

	if ($nobulk) {
		$isisadjip=&removebase(&my_walk($sess,tmnxIsisISAdjNeighborIP),tmnxIsisISAdjNeighborIP);
		$isisadjlevel=&removebase(&my_walk($sess,tmnxIsisISAdjCircLevel),tmnxIsisISAdjCircLevel);
		$sess->translate(['-octetstring'=> 0x0 ]);
		$isisadjsystemid=&removebase(&my_walk($sess,isisISAdjNeighSysID),isisISAdjNeighSysID);
		$isisiflevelopermetric=&removebase(&my_walk($sess,tmnxIsisIfLevelOperMetric),tmnxIsisIfLevelOperMetric);
	} else {
		$sess->close();
		undef $sess;
		$allresults=&my_bulk_walk($hostname,$community,[ tmnxIsisISAdjNeighborIP, tmnxIsisISAdjCircLevel, isisISAdjNeighSysID , tmnxIsisIfLevelOperMetric]);
		$isisadjip=&removebase($allresults,tmnxIsisISAdjNeighborIP);
		$isisadjlevel=&removebase($allresults,tmnxIsisISAdjCircLevel);
		$isisadjsystemid=&removebase($allresults,isisISAdjNeighSysID);
		$isisiflevelopermetric=&removebase($allresults,tmnxIsisIfLevelOperMetric);
		$sess=&snmp_session($hostname,$community,'snmpv2c');
		if (!ref($sess) && $sess =~ m/ERR_/) {
			return $sess;
		}
	}

	my %isisneighname;
	print "===> (".strftime("%Y-%m-%d-%H:%M:%S",localtime(time())).") $hostname  Hosts in QUEUE: ".scalar(@all)." Metric to $starthostname : ".&$metric($hostname)."\n";

	foreach my $oid (keys(%{$isisadjip})) {
			my @systemid=unpack("CCCCCC",$isisadjsystemid->{$oid});
			my $isishostnameoid;
			my $isishostname;
			my @x=split(/\./,$oid);

			$isishostnameoid=&build_isishostname_OID(tmnxIsisHostName,\@systemid);
			$isishostname=$sess->get_request( -varbindlist => [ $isishostnameoid ]);
			if ($isishostname->{$isishostnameoid} eq 'noSuchInstance') {
				print "$hostname ($oid)  vRtrIsisHostnameEntry ( $isishostnameoid ) OID not found \n";
				next;
			}
			
			if ($sess->error() ne "") {
				print "$hostname - $isishostnameoid ".$sess->error()."\n";
				next;
			}

			$isisneighname{$oid}=&fix($isishostname->{$isishostnameoid}); 

			if (!exists($isisneighname{$oid})) {
				print $hostname." ISIS ADJ IP: ".$isisadjip->{$oid}." Level ".$vRtrIsisISAdjCircLevel{$isisadjlevel->{$oid}}." SystemName: Not found  \n";
				next;
			}

			$ifname=$sess->get_request ( -varbindlist => [ IFNAME.'.'.$x[1] ] );
			if ( $ifname->{ IFNAME.'.'.$x[1] } eq 'noSuchInstance' ) {
				print $hostname." Interface not found ".$isisneighname{$oid}." Index: ".$x[1]."\n";
                                next;
                        }

			my $name=$ifname->{ IFNAME.'.'.$x[1] };

			print $hostname." ISIS ADJ IP: ".$isisadjip->{$oid}." Level ".$vRtrIsisISAdjCircLevel{$isisadjlevel->{$oid}}." SystemName: ".$isisneighname{$oid}."\n";

			if (!exists($topology->{'nodes'}->{$isisneighname{$oid}})) {
				$topology->{'nodes'}->{$isisneighname{$oid}}={};
			}

			if (!&edge_exists($hostname,$isisneighname{$oid}) && !&edge_exists($isisneighname{$oid},$hostname))  {
				$topology->{'edges'}->{$hostname}->{$isisneighname{$oid}}={};
			}

			$topology->{'nodes'}->{$hostname}->{$name}->{'ifIndex'}=$x[1];
			$topology->{'nodes'}->{$hostname}->{$name}->{'Level'}=$vRtrIsisISAdjCircLevel{$isisadjlevel->{$oid}};
			$topology->{'nodes'}->{$hostname}->{$name}->{'neighbor'}=$isisneighname{$oid};
			$topology->{'nodes'}->{$hostname}->{$name}->{'metric'}=$isisiflevelopermetric->{$oid};
			my $arp=&removebase(&my_walk($sess,ipNetToMediaType.".".$x[1]),ipNetToMediaType.".".$x[1]);
			my @ips;
			foreach my $ip (keys(%{$arp})) {
				next if ($ipNetToMediaType{$arp->{$ip}} ne 'other');
				push(@ips,$ip);
			}

			if (scalar(@ips)>1) {
				print $hostname." Multi IP on ISIS Interface ".$name." not supported :".join(' ',@ips)."\n";
				&push_to_queue($isisneighname{$oid});
				next;
			}


			$topology->{'nodes'}->{$hostname}->{$name}->{'IP'}=$ips[0];
			$netmask=$sess->get_request ( -varbindlist => [ ipAdEntNetMask.'.'.$ips[0] ] );
			if ( $netmask->{ ipAdEntNetMask.'.'.$ips[0] } eq 'noSuchInstance' ) {
				print $hostname." Interface ".$name." Index ".$x[1]." IP: ".$ips[0]." Netmask not found\n";
				&push_to_queue($isisneighname{$oid});
				next;
			}

			$topology->{'nodes'}->{$hostname}->{$name}->{'Netmask'}=$netmask->{ ipAdEntNetMask.'.'.$ips[0] };



			my $vrtrifname=$sess->get_request( -varbindlist => [ vRtrIfName.'.1.'.$x[1] ] );
			if ( $vrtrifname->{ vRtrIfName.'.1.'.$x[1] } eq 'noSuchInstanse' ) { 
				print $hostname." Index ".$x[1]." Failed to get vRtrIfName\n";
				&push_to_queue($isisneighname{$oid});
				next;
			}

			if ( $vrtrifname->{ vRtrIfName.'.1.'.$x[1] } ne $name ) { 
				print $hostname." Interface ".$name." not the same ".$vrtrifname->{ vRtrIfName.'.'.$x[1] }."\n";
				&push_to_queue($isisneighname{$oid});
				next;
			}

			my $vrtriftype=$sess->get_request( -varbindlist => [ vRtrIfType.'.1.'.$x[1] ] );
			if ( $vrtriftype->{ vRtrIfType.'.1.'.$x[1] } eq 'noSuchInstanse' ) { 
				print $hostname." Index ".$x[1]." Failed to get vRtrIfType\n";
				&push_to_queue($isisneighname{$oid});
				next;
			}

			my $vrtrifportid = $sess->get_request( -varbindlist => [ vRtrIfPortID.'.1.'.$x[1] ] );
			if ( $vrtrifportid->{ vRtrIfPortID.'.1.'.$x[1] } eq 'noSuchInstanse' ) { 
				print $hostname." Index ".$x[1]." Failed to get vRtrIfPortID\n";
				&push_to_queue($isisneighname{$oid});
				next;
			}
			my $ifportid=$vrtrifportid->{ vRtrIfPortID.'.1.'.$x[1] };

			my $vrtrifencapvalue = $sess->get_request( -varbindlist => [ vRtrIfEncapValue.'.1.'.$x[1] ] );
			if ( $vrtrifencapvalue->{ vRtrIfEncapValue.'.1.'.$x[1] } eq 'noSuchInstanse' ) { 
				print $hostname." Index ".$x[1]." Failed to get vRtrIfEncapValue\n";
				&push_to_queue($isisneighname{$oid});
				next;
			}

                        $ifname=$sess->get_request ( -varbindlist => [ IFNAME.'.'.$ifportid ] );
                        if ( $ifname->{ IFNAME.'.'.$ifportid }  eq 'noSuchInstance' ) {
                                print $hostname." Interface not found ".$isisneighname{$oid}." Index: ".$ifportid."\n";
				&push_to_queue($isisneighname{$oid});
                                next;
                        }

                        my $physiface=$ifname->{ IFNAME.'.'.$ifportid };

			my $vrtrifsvcid = $sess->get_request( -varbindlist => [ vRtrIfServiceId.'.1.'.$x[1] ] );
			if ( $vrtrifsvcid->{ vRtrIfServiceId.'.1.'.$x[1] } eq 'noSuchInstanse' ) { 
				print $hostname." Index ".$x[1]." Failed to get vRtrIfServiceId\n";
				&push_to_queue($isisneighname{$oid});
				next;
			}

			if ( $vrtriftype->{ vRtrIfType.'.1.'.$x[1] } ne '1' ) {  
				$topology->{'nodes'}->{$hostname}->{$name}->{'SAP'}=&portencap($physiface,&conv32vlantodot($vrtrifencapvalue->{ vRtrIfEncapValue.'.1.'.$x[1] }));
				$topology->{'nodes'}->{$hostname}->{$name}->{'svcid'}=$vrtrifsvcid-> { vRtrIfServiceId.'.1.'.$x[1] };
				$topology->{'nodes'}->{$hostname}->{$name}->{'AluType'}=&get_aluporttype($vrtriftype->{ vRtrIfType.'.1.'.$x[1] });
			} else {
				$topology->{'nodes'}->{$hostname}->{$name}->{'Port'}=&portencap($physiface,$vrtrifencapvalue->{ vRtrIfEncapValue.'.1.'.$x[1] });
				$topology->{'nodes'}->{$hostname}->{$name}->{'AluType'}=&get_aluporttype($vrtriftype->{ vRtrIfType.'.1.'.$x[1] });
			}

			&push_to_queue($isisneighname{$oid});
	}

	$sess->close();
	undef $sess;

}


#MAIN
die("Wrong args") unless GetOptions( 'hostname|n=s' => \$hostname, 
					'community|C=s' => \$community,
					'output|O=s' => \$output,
					'single|s' => \$single,
					'nobulk|b' => \$nobulk,
					'metric|m' => \$metricsort,
					'geo|g'	 => \$geosort,
				        'geofile|f=s' => \$geofile,
					'help|h' => \$help ,
				);
if( $help ) {
   print "
$0 - Intermediate System to Intermediate System (IS-IS) routing protoocol discovery

  Options:
   --hostname|n -- start from this node
   --communiy|C -- SNMP Community / single or match file
   --output|O -- output file (default network.json)
   --single|s -- single host
  SNMP:
   --nobulk|b -- Do no use bulk snmp
  Sorting options:
   --metric|m -- sort nodes in queue based on route table  metric to start node  (default)
   --geo|g -- sort nodes based on geographical distance between start node and nodes in queue
   --geofile|f -- geofile
  Help:
   --help|h - - This help
";
   exit(0);
}


if (!defined($hostname)) {
	print "hostname must be set\n";
	exit(1);
}

if (defined($hostname) && !defined($community)) {
	print "Community must be set\n";
	exit(1);
}

if ( -e $community ) { 
	print "Loading community from file : $community\n";
	if (!open(FILE,"<".$community)) {
		print STDERR "Can't open $community..".$!."\n";
		exit(1);
	}
	while (<FILE>) {
		next if (m/^#/);
		chomp;
		my @arr=split(/;/);
		$alucommunity{$arr[0]}=$arr[1] unless (exists($alucommunity{$arr[0]}));
	}
	close(FILE);
}

#init default method
$metric=\&route_metric;

if ($geosort) {
	$metric=\&get_geo_distance;
	if (!defined($geofile)) {
		print STDERR "Geofile parameter missing\n";
		exit(1);
	}
	if (!open(FILE,"<$geofile")) {
		print STDERR "Can't open $geofile..".$!."\n";
		exit(1);
	}
	while (<FILE>) {
		next if (m/^#/);
		s/ //g;
		my @x=split(':'); 
		if ($x[0] eq 'REGEX') {
			chomp($x[1]);
			$hostnamereg = $x[1];
			last;
		}	
	}

	while (<FILE>) {
		next if (m/^#/);
		my @x=split(';');
		if (!exists($geocords{$x[0]})) {
			$geocords{$x[0]}{'long'}=$x[1];
			$geocords{$x[0]}{'lat'}=$x[2];
		}
	}
	close(FILE);
	print "Read ".scalar(keys(%geocords))." geolocation data\n";
}



$starthostname=$hostname;
@startarr = gethostbyname($hostname) ;
@startarr = map { inet_ntoa($_) } @startarr[4 .. $#startarr];
$startip=$startarr[0];

$SIG{'INT'}=\&sig_handler;
$SIG{'QUIT'}=\&sig_handler;

push(@all,$hostname);

while (1)
{
	if (scalar(@all)==0) {
		last;
	}

	$h=pop(@all);

	$ncomm=&find_community($h,$community);

	my $err=&isis_discovery($h,$ncomm);
        if (defined($err)) {

        if ( $err eq "ERR_NORESP" ) {
		$topology->{'nodes'}->{$h}->{'noresponse'}=1;
        	}

       if ( $err eq "ERR_NONALU" ) {
		$topology->{'nodes'}->{$h}->{'nonalu'}=1;
       		}
	}
	last if ( $single ) ;
	&get_isis_route_metric($h,$community) if (!$geosort);
	@nall=sort {  &$metric($b) <=> &$metric($a) }   @all;
	@all=@nall;
}

&write_data();
exit(0);
