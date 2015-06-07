use strict;
use JSON;
use Data::Dumper;

$|++;

if (!-e "donor_p_150526020206.jsonl.gz") { system("wget http://pancancer.info/gnos_metadata/2015-05-26_02-02-06_UTC/donor_p_150526020206.jsonl.gz"); }

# map platform unit to read group, should be one-to-one
my $pu_to_rg = {};

# parse out the info from the BAM headers
my @files = glob("data/*/*.txt");
foreach my $file (@files) {

  print "PROCESSING FILE: $file\n";

  open IN, "<$file" or die;
  while(<IN>) {
    chomp;
    if (/^\@RG/) {
      my @a = split /\t/;

      $a[9] =~ /PU:(\S+)/;

      my $pu = $1;

      #print "PU: $pu\n";

      $a[1] =~ /ID:(\S+)/;
      my $rg = $1;

      #print "RG: $rg\n";

      die "NON UNIQUE PLATFORM UNIT TO READGROUP! $pu $rg" if ($pu_to_rg->{$pu} ne "");

      $pu_to_rg->{$pu} = $rg;
    }
  }
  close IN;
}

####print Dumper $pu_to_rg;


# now iterate over the index and make corrections where needed
# also track the number needing changes and the number finally changed


open IN, "gunzip -c donor_p_150526020206.jsonl.gz | " or die "Can't open donor_p_150526020206.jsonl.gz";

while (<IN>) {

  my $jd = decode_json($_);

  #print Dumper $jd->{normal_specimen}{alignment}{qc_metrics};

  # does this one need repairs???
  my $seen = {};
  my $broken = 0;
  foreach my $qc_entry (@{$jd->{normal_specimen}{alignment}{qc_metrics}}) {
    #print "QC ENTRY: ".Dumper $qc_entry;
    if ($seen->{$qc_entry->{read_group_id}}) {
      $broken = 1;
    }
    $seen->{$qc_entry->{read_group_id}} = 1;
  }

  #print Dumper($seen);

  print "IS THIS BROKEN: $broken\n" if ($broken);

  print "NOT BROKEN: $broken\n" if (!$broken);



# if (/ce799e7b-30e7-44a5-a185-3e50d5e059ef/) {
#    my $jd = decode_json ($_);
#    print Dumper $jd;
#
#    print Dumper $jd->{normal_specimen}{alignment}{qc_metrics};
#  }


}

close IN;
