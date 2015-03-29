use strict;

# time perl bam_diff.pl first.bam second.bam 0

my ($in1, $in2, $max) = @ARGV;

my $d = {};

my $use_max = 0;
my $curr_max = 0;
if ($max > 0) { $use_max = 1; $curr_max = $max; }

my @chrs;
for (my $i=1; $i<23; $i++) {
  push @chrs, "$i";
}
push @chrs, "X";
push @chrs, "Y";
push @chrs, "MT";

my $total_reads = 0;
my $total_mismatch = 0;

foreach my $chr (@chrs) {

  open (IN1, "samtools view $in1 $chr|") or die;
  open (IN2, "samtools view $in2 $chr|") or die;

  my $line_count = 0;

  print STDERR "CHR$chr\n";

  while(<IN1>) {

          $line_count++;
          $total_reads++;

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

          # print status
          print STDERR "." if ($line_count % 1000 == 0);

  }

  close IN1;
  close IN2;

  print STDERR "\nTOTAL READS FOR CHR$chr: $line_count\n";

  my $lines_mismatch = 0;

  open LOG, ">log_chr_$chr.log" or die;
  foreach my $name (keys %{$d}) {
          foreach my $flag (keys %{$d->{$name}}) {
                  foreach my $chr (keys %{$d->{$name}{$flag}}) {
                          foreach my $pos (keys %{$d->{$name}{$flag}{$chr}}) {
                                  foreach my $cigar (keys %{$d->{$name}{$flag}{$chr}{$pos}}) {
                                          print LOG "$name\t$flag\t$chr\t$pos\t".$d->{$name}{$flag}{$chr}{$pos}."\n";
                                          $lines_mismatch++;
                                          $total_mismatch++;
                                  }
                          }
                  }
          }
  }
  close LOG;

  print STDERR "\nTOTAL MISMATCHING READS FOR CHR$chr: $lines_mismatch\n";

}

print STDERR "\nTOTAL READS FOR ALL CHR: $total_reads\n";
print STDERR "\nTOTAL MISMATCHING READS FOR ALL CHR: $total_mismatch\n";
