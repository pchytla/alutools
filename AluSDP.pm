package AluSDP;
use strict;
use Data::Dumper;

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT_OK = qw ( 
        %sdptypes 
	cmp_sdp 
);

our @EXPORT = qw(
);

our %sdptypes = (
                        1 => 'spoke',
                        2 => 'mesh',
                 );

sub new {
	my $class = shift;
	my $self = { 'sdplist' => { }, 
		};
	return bless $self ,$class;
}



sub add_sdp {
        my $self=shift;
        my $sdp=shift;
	my $type=shift;
	if (exists($self->{'sdplist'}->{$sdp})) {
			return 0;
	}

	$self->{'sdplist'}->{$sdp}->{'type'}=$type;
        return 1;
}

sub get_sdp {
	my $self=shift;
	my $sdp=shift;
	return $self->{'sdplist'}->{$sdp};
}

sub get_all_sdp {
	my $self=shift;
	return keys(%{$self->{'sdplist'}});
}

sub csv {
	my $self=shift;
	my $r="";
	foreach my $k (keys(%{$self->{'sdplist'}})) {
		$r.=$self->{'sdplist'}{$k}{'type'}."-sdp ".$k.","
	}
	return $r;
}

1;
