use strict;

# time perl bam_diff.pl a5cb1934-6319-4efb-936c-4addb07d1edd/2bfc449b254c099120610cc3d80091d3.sam /glusterfs/data/ICGC2/seqware_results/scratch/oozie-9e82b8b3-142a-4ef5-a437-53c8e6a0b410/data/merged_output.sam

my ($in1, $in2, $max) = @ARGV;

my $d = {};

my $use_max = 0;
my $curr_max = 0;
if ($max > 0) { $use_max = 1; $curr_max = $max; }

open IN1, "<$in1" or die;
open IN2, "<$in2" or die;

while(<IN1>) {

        $curr_max--;

        my @a = split /\s+/;
        # check the pcr dup flag and clear, we don't worry about this one
        if ($a[1] & 1024) { $a[1] = $a[1] - 1024; }

        $d->{$a[0]}{$a[1]}{$a[2]}{$a[3]}{$a[5]}++;

        if ($d->{$a[0]}{$a[1]}{$a[2]}{$a[3]}{$a[5]} >= 2) { delete($d->{$a[0]}{$a[1]}); }

        if (scalar(keys %{$d->{$a[0]}}) == 0) { delete($d->{$a[0]}); }

        my $_ = <IN2>;
        @a = split /\s+/;
        # check the pcr dup flag and clear, we don't worry about this one
        if ($a[1] & 1024) { $a[1] = $a[1] - 1024; }

        $d->{$a[0]}{$a[1]}{$a[2]}{$a[3]}{$a[5]}++;

        if ($d->{$a[0]}{$a[1]}{$a[2]}{$a[3]}{$a[5]} >= 2) { delete($d->{$a[0]}{$a[1]}); }

        if (scalar(keys %{$d->{$a[0]}}) == 0) { delete($d->{$a[0]}); }

        if ($use_max) { last if ($curr_max <= 0); }

}

foreach my $name (keys %{$d}) {
        foreach my $flag (keys %{$d->{$name}}) {
                foreach my $chr (keys %{$d->{$name}{$flag}}) {
                        foreach my $pos (keys %{$d->{$name}{$flag}{$chr}}) {
                                foreach my $cigar (keys %{$d->{$name}{$flag}{$chr}{$pos}}) {
                                        print "$name\t$flag\t$chr\t$pos\t".$d->{$name}{$flag}{$chr}{$pos}."\n";
                                }
                        }
                }
        }
}


close IN1;
close IN2;
