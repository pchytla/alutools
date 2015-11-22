package AluSVC;
use strict;
use AluSAP;
use AluSDP;
require Exporter;

our @ISA = qw(Exporter);

our @EXPORT_OK = qw ( 
	find_svc
);

our @EXPORT = qw(
);


our @servtype = (
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
			'intVpls' , #(11) VPLS Service for internal purposes only
                );

sub new {
	my $class = shift;
	my $self = { 
			'id' => undef,
			'sap' => undef,
			'sdp' => undef,
			'type' => undef,
			'servicelongname' => undef,
			'serviceshortname' => undef,
			};
	$self->{'id'} = shift;
	$self->{'type'} = shift || 0;
	$self->{'type'} = $servtype[$self->{'type'}];
	$self->{'servicelongname'} = shift;
	$self->{'serviceshortname'} = shift;
	$self->{'sap'} = new AluSAP();
	$self->{'sdp'} = new AluSDP();
	return bless $self ,$class;
}

sub set_servicename_long {
	my $self = shift;
	my $name = shift;
	$self->{'servicelongname'}=$name;

}

sub set_servicename_short {
	my $self = shift;
	my $name = shift;
	$self->{'serviceshortname'}=$name;

}

sub get_shortname {
	my $self = shift;
	return defined($self->{'serviceshortname'})?$self->{'serviceshortname'}:"";
}

sub get_longname {
	my $self = shift;
	return defined($self->{'servicelongname'})?$self->{'servicelongname'}:"";
}


sub get_id {
	my $self = shift;
	return $self->{'id'};
}

sub add_sap {
	my $self = shift;
	my $sap = shift;
	return $self->{'sap'}->add_sap($sap);
}


sub add_sdp {
	my $self = shift;
	my $sdp = shift;
	my $type = shift;
	return $self->{'sdp'}->add_sdp($sdp,$type);
}

sub get_all_sdp {
	my $self = shift;
	return $self->{'sdp'}->get_all_sdp();
}

sub csv {
	my $self = shift;
	return $self->{'id'}.";".$self->{'type'}.";".$self->{'sap'}->csv().";".$self->{'sdp'}->csv().";".$self->get_longname().";".$self->get_shortname().";";
}

#
#  Returns :
#	undef - not found in array       
# 	0..X - found
#
sub find_svc() {
	my $arr = shift;
	my $id = shift;

	die("find_svc() argument \$arr not ARRAY ref") if (ref($arr) ne 'ARRAY');

	for (my $i=0;$i<scalar(@{$arr});$i++) {
		return $i if ($arr->[$i]->get_id()==$id);
	}

	return undef;
}

1;
