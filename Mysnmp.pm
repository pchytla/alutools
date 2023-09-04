package Mysnmp;
use strict;
use Net::SNMP qw( oid_lex_sort oid_base_match );
use Time::HiRes qw( gettimeofday tv_interval );
require Exporter;

our @ISA = qw(Exporter);

our @EXPORT_OK = qw (
	snmp_session
	my_walk
	my_bulk_walk
);

our @EXPORT = qw(
);


sub snmp_session() {
        my $hostname=shift;
        my $community=shift;
        my $ver=shift;
        my $bulk=shift;

        my %args = ( '-version'    => $ver,
                     '-hostname'   => $hostname,
                     '-timeout'    => 5,
                     '-retries'    => 3,
                     '-community'   => $community );

        $args{'-nonblocking'} = 1 if ($bulk) ;

        my ( $snmpsession, $err ) =  Net::SNMP->session(
                                                %args,
                                                );

        if ($err) {
                        print STDERR "ERR: Connection error  $hostname : $err\n";
                        return "ERR_NORESP";
        }
        return $snmpsession;
}

sub my_walk() {
        my $s=shift;
        my $oid=shift;
        my $baseoid=$oid;
        my $r;
        my $t0=[gettimeofday()];
        my $res;
        outer: while ($res=$s->get_next_request(-varbindlist => [ $oid ])) {
                my @k=keys(%{$res});
                $oid=$k[0];
                last outer unless($oid =~ m/$baseoid/);
                $r->{$oid}=$res->{$oid};
        }
        if (!defined($res)) {
                        print STDERR $s->{'_hostname'}." : ERR: OID($baseoid) ".$s->error."\n";
        }

        print STDERR $s->{'_hostname'}. "(my_walk) OID ".$oid." elapsed time : ".sprintf("%f",tv_interval($t0))." sec\n";
        return $r;
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
              -maxrepetitions => 5,
              -varbindlist    => \@fnext
           );

           if (!defined($result)) {
              printf("%s ERROR: %s\n", $session->{'_hostname'},$session->error);
           }

        }
}

sub my_bulk_walk()
{
	my $s=shift;
        my $baseoidref = shift;
        my %ret;
        my $t0=[gettimeofday()];

        $s->translate(['-octetstring'=> 0x0 ]);
        my $r=$s->get_bulk_request( -callback       => [ \&table_cb_bulk , $baseoidref, \%ret ] ,
                                     -maxrepetitions => 5,
                                     -varbindlist    => $baseoidref,
                                        );
        if (!defined($r)) {
                print $s->{'_hostname'}." -> ".$s->error."\n";
                return "ERR_NORESP";
        }

        $s->snmp_dispatcher();

        print STDERR $s->{'_hostname'}. "(my_bulk_walk) OID: [ ".join(',',@{$baseoidref})." ] elapsed time : ".sprintf("%f",tv_interval($t0))." sec\n";
        $s->close();
        return \%ret;
}

1;
