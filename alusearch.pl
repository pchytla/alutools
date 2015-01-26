#!/opt/local/bin/perl -w
#
use Getopt::Long;
use Net::SNMP qw( :snmp :asn1 );
use POSIX qw( :math_h );
use File::Basename;

$|=1;

use constant IFDESCR => '.1.3.6.1.2.1.2.2.1.2';
use constant IFNAME => '.1.3.6.1.2.1.31.1.1.1.1';
use constant IFALIAS => '.1.3.6.1.2.1.31.1.1.1.18';
use constant SAPLIST => '.1.3.6.1.4.1.6527.3.1.2.4.3.2.1.15';
use constant SERVTYPE => '.1.3.6.1.4.1.6527.3.1.2.4.2.2.1.3';
use constant SERVLONGNAME => '.1.3.6.1.4.1.6527.3.1.2.4.2.2.1.6';
use constant SERVNAME => '.1.3.6.1.4.1.6527.3.1.2.4.2.2.1.29';

my $hostnamearg;
my $communityarg;
my $routerfile;
my $matcharg;
my $match;
my $help;
my $version;
my $outfile;

my @servtype = (
                        'unknown' , #(0) Unknown service type
                        'epipe'   , #(1) Ethernet pipe
                        'p3pipe'  , #(2) POS pipe
                        'tls'     , #(3) Virtual private LAN service
                        'vprn'   , #(4) Virtual private routed network
                        'ies'     , #(5) Internet enhanced service
                        'mirror'  , #(6) Mirror service
                        'apipe'   , #(7) ATM pipe service
                        'fpipe'   , #(8) FR pipe service
                        'ipipe'   , #(9) IP interworking pipe service
                        'cpipe'   , #(10) Circuit Emulation pipe service
		);


my %int;
my $hint=\%int;

my %intports;
my $hintports=\%intports;

my @psslist;
my $hpsslist=\@psslist;

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

sub add_service()
{
	my ($h,$srvid,$srvlong,$srvshort,$srvtype)  = @_;

	if (defined($srvlong->{$srvid})) {
		$h->{$srvid}->{'servicelongname'}=$srvlong->{$srvid};
	}

	if (defined($srvshort->{$srvid})) {
		$h->{$srvid}->{'serviceshortname'}=$srvshort->{$srvid};
	}

	if (defined($srvtype->{$srvid})) {
		$h->{$srvid}->{'servicetype'}=$servtype[$srvtype->{$srvid}];
	}
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

die("Wrong args") unless GetOptions( 'hostname|h=s' => \$hostnamearg, 'community|C=s' => \$communityarg, 'routerfile|r=s' => \$routerfile, 'version|V' => \$version, 'match|m=s' => \$matcharg );
if( $help ) {
   print "Options:
   --hostname|h -- Scan single hostname
   --communiy|C -- SNMP Community
   --routerfile|r - Scan routers from file Format 'hostname;community'
   --match|m - - Match regular expression in Alcatel Service-Name  / Service description / port description
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

if (!defined($matcharg)) { 
	$match = qr/.+/;
} else {
	$match = qr/$matcharg/;
}


if (!defined($routerfile)) {
	$routerfile="/tmp/".basename($0).".$$";
	&write_out($routerfile,"$hostnamearg;$communityarg");
}

if (!open(FD,"<".$routerfile)) {
	print "Problem with file $routerfile can't open\n";
	exit(1);
}

while (<FD>) {
	%int=();
	%intports=();
	@psslist=();

	if (m/^(\S+);(\S+)\s*$/) {
		$hostname=$1;
		$community=$2;
		print STDERR $hostname."\n";
	} else {
		print STDERR "Wrong Line : ".$_;
		next;
	}
	&write_out("./".$hostname.".ports","Host;Port;ifDescr");
	&write_out("./".$hostname.".svc","Host;srvid;sap;port;servicetype;servicelongname;serviceshortname");

	my $sess=&snmp_session($hostname,$community,'snmpv2c');
	my $ifdescr=&removebase(&my_walk($sess,IFDESCR),IFDESCR);
	my $ifname=&removebase(&my_walk($sess,IFNAME),IFNAME);
	my $ifalias=&removebase(&my_walk($sess,IFALIAS),IFALIAS);
	my $servlongname=&removebase(&my_walk($sess,SERVLONGNAME),SERVLONGNAME);
	my $servname=&removebase(&my_walk($sess,SERVNAME),SERVNAME);
	my $servtype=&removebase(&my_walk($sess,SERVTYPE),SERVTYPE);
	my $saplist=&removebase(&my_walk($sess,SAPLIST),SAPLIST);
	my $s;
	
	#porty
	foreach $s (keys(%{$ifname})) {
		next unless ($ifdescr->{$s}=~m/$match/);
		$portid=$ifname->{$s};
		$hintports->{$portid}=$ifdescr->{$s};
		push(@psslist,$portid);
	}
	
	#serwisy
	foreach $s (keys(%{$servlongname})) {
		next unless ($servlongname->{$s}=~m/$match/);
		&add_service($hint,$s,$servlongname,$servname,$servtype);
	}
	#$serwisy
	foreach $s (keys(%{$servname})) {
		next unless ($servname->{$s}=~m/$match/);
		&add_service($hint,$s,$servlongname,$servname,$servtype);
	}
	
	##sap-y
	foreach $s (keys(%{$saplist})) {
		my @saps=split(/\./,$s);
		my $port;
	
		if (defined($ifname->{$saps[1]})) {
			$port=$ifname->{$saps[1]};
		} else {
			print STDERR $hostname." : ERR: Brak mapowania IF-NAME dla ".$saps[1]."\n";
			next;
		}
	
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
	
		if ( &in_array($hpsslist,$port)) {
			push(@{$hint->{$saps[0]}->{'sap'}},$sap) unless (&in_array($hint->{$saps[0]}->{'sap'},$sap));
			&add_service($hint,$saps[0],$servlongname,$servname,$servtype);
		}
		
		if (exists($hint->{$saps[0]})) {
			push(@{$hint->{$saps[0]}->{'sap'}},$sap) unless (&in_array($hint->{$saps[0]}->{'sap'},$sap));
		}
	}
	


	foreach my $p (keys(%{$hintports})) {
		&write_out("./".$hostname.".ports", $hostname.";".$p.";".$hintports->{$p});
	}

	foreach my $h (keys(%{$hint})) {
		$servicetype=defined($hint->{$h}->{'servicetype'})?$hint->{$h}->{'servicetype'}:'';
		$servicelongname=defined($hint->{$h}->{'servicelongname'})?$hint->{$h}->{'servicelongname'}:'';
		$serviceshortname=defined($hint->{$h}->{'serviceshortname'})?$hint->{$h}->{'serviceshortname'}:'';
		if (defined($hint->{$h}->{'sap'})) {
			$saplist=join(',',@{$hint->{$h}->{'sap'}});
		} else {
			$saplist="";
		}
	
		&write_out("./".$hostname.".svc", $hostname.";".$h.";".$saplist.";".$servicetype.";".$servicelongname.";".$serviceshortname);
	}
	$sess->close;
}

close(FD);
if (defined($hostnamearg)) {
	unlink($routerfile);
}
exit 0;
