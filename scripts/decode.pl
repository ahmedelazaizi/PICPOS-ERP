use strict;
use warnings;

my ($src, $out) = @ARGV;
open(my $fh, "<:encoding(UTF-8)", $src) or die "open: $!";
local $/;
my $raw = <$fh>;
close $fh;

$raw =~ /"content":"(.*)","contentType"/s or die "لم يطابق نمطُ content\n";
my $c = $1;

$c =~ s/\\u([0-9a-fA-F]{4})/chr(hex($1))/ge;
$c =~ s/\\n/\n/g;
$c =~ s/\\t/\t/g;
$c =~ s/\\r//g;
$c =~ s/\\"/"/g;
$c =~ s/\\\//\//g;
$c =~ s/\\\\/\\/g;

open(my $o, ">:encoding(UTF-8)", $out) or die "write: $!";
print $o $c;
close $o;
print "كُتب: ", length($c), " محرفاً\n";
