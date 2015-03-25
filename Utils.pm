package Utils;
use strict;

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT_OK = qw (
        in_array
	conv32vlantodot
	convdotto32bit
	convsapnameto32bit
	conv32bittosapname
	portencap
);

our @EXPORT = qw(
);


sub in_array()
{
   my ($arr,$e) = @_;
   my $str=join('',map { $_ eq $e } @{$arr});
   return 1 if ($str);
   return 0;
}

sub portencap() {
	my $port=shift;
	my $vlan=shift;
	#Null
        if ($vlan==0) {
                 return $port;
        } 
        #sap:* - dot1/qinq encap
        $vlan=~s/4095/\*/;
        #dot1q/qinq
        return $port.":".$vlan;
}

# {{

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

1;
