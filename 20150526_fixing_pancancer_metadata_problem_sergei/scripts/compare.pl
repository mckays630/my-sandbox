#!/usr/bin/perl
use common::sense;

open FILES, "find broken -name '*.xml' |";
while (my $broken = <FILES>) {
    chomp $broken;
    (my $fixed = $broken) =~ s/broken/fixed/;
    print "$broken\tNOT FIXED\n" and next unless -e $fixed;
    my $diff = `diff $broken $fixed`;
    $diff ? 
	print "$broken\tUPDATED\n" :
	print "$broken\tNO DIFFERENCE\n";
}
