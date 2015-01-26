package Utils;
use strict;

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT_OK = qw (
        in_array
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

1;
