package AluSAP;
use strict;

sub new {
	my $class = shift;
	my $self= { 'saplist' => [ ] , };
	return bless $self ,$class;
}

sub add_sap {
	my $self=shift;
	my $sap=shift;
	if ($self->{'saplist'} ~~ $sap) {
			return 0;
	}

	push(@{$self->{'saplist'}},$sap);
	return 1;
}

sub csv {
	my $self=shift;
	return join(',',@{$self->{'saplist'}});
}
1;
