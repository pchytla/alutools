#!/opt/local/bin/perl -w
use strict;
use warnings;
use JSON;
use Net::CIDR;
my $topology;
my $default_netmask="255.255.255.254";
my %miasta;

sub graphml_head() {
   print <<__EOF__;
<?xml version="1.0" encoding="UTF-8"?>
<graphml xmlns="http://graphml.graphdrawing.org/xmlns"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation="http://graphml.graphdrawing.org/xmlns
        http://graphml.graphdrawing.org/xmlns/1.0/graphml.xsd">
__EOF__
}


sub get_type() {
	my $t=shift;
	return defined($t)?$t:"OTHER";
}

sub get_remote_netmask() {
	my $h1=shift;
	my $h2=shift;
	my $ip=shift;
	foreach my $k (keys(%{$topology->{'nodes'}->{$h2}})) {
		next if (ref($topology->{'nodes'}->{$h2}->{$k}) ne 'HASH');
		if ($topology->{'nodes'}->{$h2}->{$k}->{'neighbor'} eq $h1) {
			my @cidr= ( Net::CIDR::addrandmask2cidr($topology->{'nodes'}->{$h2}->{$k}->{'IP'},$topology->{'nodes'}->{$h2}->{$k}->{'Netmask'}) );
			if (Net::CIDR::cidrlookup($ip,@cidr)) {
				return $topology->{'nodes'}->{$h2}->{$k}->{'Netmask'};
			}
		}
		
	}

	return $default_netmask;
}

sub get_attr() {
	my $h1=shift;
	my $h2=shift;
	my $attr=shift;
	my %r;
	foreach my $k (keys(%{$topology->{'nodes'}->{$h1}})) {
		next if (ref($topology->{'nodes'}->{$h1}->{$k}) ne 'HASH');
		next if ($topology->{'nodes'}->{$h1}->{$k}->{'neighbor'} ne $h2);
		my $netmask=defined($topology->{'nodes'}->{$h1}->{$k}->{'Netmask'})?$topology->{'nodes'}->{$h1}->{$k}->{'Netmask'}:&get_remote_netmask($h1,$topology->{'nodes'}->{$h1}->{$k}->{'neighbor'},$topology->{'nodes'}->{$h1}->{$k}->{'IP'});
		my $cidr=Net::CIDR::addrandmask2cidr($topology->{'nodes'}->{$h1}->{$k}->{'IP'},$netmask);
		
		if ( $attr eq 'Interface') {
			push(@{$r{$cidr}},$k);
			next;
		}

		if ( $attr ne 'Netmask' ) {
			push(@{$r{$cidr}},$topology->{'nodes'}->{$h1}->{$k}->{$attr});
		} else {
			push(@{$r{$cidr}},$netmask);
		}
	}

	foreach my $k (keys(%{$topology->{'nodes'}->{$h2}})) {
		next if (ref($topology->{'nodes'}->{$h2}->{$k}) ne 'HASH');
		next if ($topology->{'nodes'}->{$h2}->{$k}->{'neighbor'} ne $h1);
		my $netmask=defined($topology->{'nodes'}->{$h2}->{$k}->{'Netmask'})?$topology->{'nodes'}->{$h2}->{$k}->{'Netmask'}:&get_remote_netmask($h2,$topology->{'nodes'}->{$h2}->{$k}->{'neighbor'},$topology->{'nodes'}->{$h2}->{$k}->{'IP'});
		my $cidr=Net::CIDR::addrandmask2cidr($topology->{'nodes'}->{$h2}->{$k}->{'IP'},$netmask);
		if ( $attr eq 'Interface') {
			push(@{$r{$cidr}},$k);
			next;
		}
		if ( $attr ne 'Netmask' ) {
			push(@{$r{$cidr}},$topology->{'nodes'}->{$h2}->{$k}->{$attr});
		} else {
			push(@{$r{$cidr}},$netmask);
		}

	}

	return \%r;
}

my $json=JSON->new();
my $jsonstr="";
open(FILE,"<".$ARGV[0]);
while (<FILE>) {
	$jsonstr.=$_;
}
close(FILE);

$topology=$json->decode($jsonstr);

graphml_head();

print <<__EOF__;
  <key id="sysdescr" for="node" attr.name="sysdescr" attr.type="string">
    <default></default>
  </key>
  <key id="ips" for="edge" attr.name="ips" attr.type="string">
    <default></default>
  </key>
  <key id="netmask" for="edge" attr.name="netmask" attr.type="string">
    <default></default>
  </key>
  <key id="interfaces" for="edge" attr.name="interfaces" attr.type="string">
    <default></default>
  </key>
  <key id="alutypes" for="edge" attr.name="alutypes" attr.type="string">
    <default></default>
  </key>
  <key id="ports" for="edge" attr.name="ports" attr.type="string">
    <default></default>
  </key>
  <key id="isislevel" for="edge" attr.name="isislevel" attr.type="string">
    <default></default>
  </key>
  <key id="interfacemetrics" for="edge" attr.name="interfacemetrics" attr.type="string">
    <default></default>
  </key>
  <key id="color" for="edge" attr.name="color" attr.type="string">
    <default>yellow</default>
   </key>
  <key id="color" for="node" attr.name="color" attr.type="string">
    <default>yellow</default>
   </key>
  <key id="label" for="edge" attr.name="label" attr.type="string">
    <default>yellow</default>
   </key>
  <key id="label" for="node" attr.name="label" attr.type="string">
    <default>yellow</default>
   </key>
<graph id="ISIS" edgedefault="undirected">
__EOF__

foreach my $n (keys(%{$topology->{'nodes'}})) {
	my $sys=exists($topology->{'nodes'}->{$n}->{'sysdescr'})?$topology->{'nodes'}->{$n}->{'sysdescr'}:"";
	my $color=exists($topology->{'nodes'}->{$n}->{'noresponse'})?"<data key=\"color\"> red </data>":"";
print <<__EOF__;
   <node id="$n">
	<data key="sysdescr"> $sys </data>
	<data key="label"> $n </data>
	$color
    </node>
__EOF__
}

foreach my $h1 (keys(%{$topology->{'edges'}})) {
        foreach my $h2 (keys(%{$topology->{'edges'}->{$h1}})) {
		my $ips=&get_attr($h1,$h2,'IP');
		my $netmask=&get_attr($h1,$h2,'Netmask');
		my $interfaces=&get_attr($h1,$h2,'Interface');
		my $level=&get_attr($h1,$h2,'Level');
		my $port=&get_attr($h1,$h2,'Port');
		my $AluType=&get_attr($h1,$h2,'AluType');
		my $metric=&get_attr($h1,$h2,'metric');

	foreach my $net (keys(%{$interfaces})) {
		my $interfacesstr=join(' ',@{$interfaces->{$net}});
		my $color="";
		if ($interfacesstr=~m/hundge-/) { 
			$color="red";
		}
		if ($interfacesstr=~m/lag-/) {
			$color="blue";
		}
		if ($interfacesstr=~m/ge-[0-9\/ ]+ge-/) { 
			$color="carnationpink";
		}
	print '<edge id="'.$h1."-".$h2."-".$net.'" source="'.$h1.'" target="'.$h2.'">'."\n";
	print '<data key="label">'.join('-',@{$interfaces->{$net}}).'</data>'."\n";
	print '<data key="ips">'.join(' ',@{$ips->{$net}}).'</data>'."\n";
	print '<data key="netmask">'.join(' ',@{$netmask->{$net}}).'</data>'."\n";
	print '<data key="interfaces">'.join(' ',@{$interfaces->{$net}}).'</data>'."\n";
	print '<data key="alutypes">'.join(' ',@{$AluType->{$net}}).'</data>'."\n";
	print '<data key="ports">'.join(' ',@{$port->{$net}}).'</data>'."\n";
	print '<data key="interfacemetrics">'.join(' ',@{$metric->{$net}}).'</data>'."\n";
	print '<data key="isislevel">'.join(' ',@{$level->{$net}}).'</data>'."\n";
	print '<data key="color">' .$color.' </data>'."\n" if ($color ne "" );
	print "</edge>\n";
	}
		}
}

print "</graph>\n</graphml>\n";


