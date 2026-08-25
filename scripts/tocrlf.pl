use strict; use warnings;
my $p = $ARGV[0];
open(my $i, '<:raw', $p) or die "open $p: $!";
local $/; my $b = <$i>; close $i;
$b =~ s/\r\n/\n/g;
$b =~ s/\n/\r\n/g;
open(my $o, '>:raw', $p) or die "write $p: $!";
print $o $b; close $o;
print "ok $p\n";
