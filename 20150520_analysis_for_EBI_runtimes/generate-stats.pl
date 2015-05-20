use strict;
use JSON;
use Data::Dumper;

my $project_code = shift;

# get the data file
if (!-e "donor_p_150520020206.jsonl") {
  die if (system("wget http://pancancer.info/gnos_metadata/2015-05-20_02-02-06_UTC/donor_p_150520020206.jsonl.gz"));
  die if (system("gunzip donor_p_150520020206.jsonl.gz"));
}

open IN, "<donor_p_150520020206.jsonl" or die;

print "TYPE\tMERGE_TIME\tBWA_TIME\tDOWN_TIME\n";

while(<IN>) {
  chomp;
  my $json = decode_json($_);

  next if ($json->{dcc_project_code} ne $project_code);

  #print Dumper $json;

  if (defined ($json->{normal_specimen}{alignment}{timing_metrics})) {

    my $norm_merge_timing_seconds = 0;
    my $norm_bwa_timing_seconds = 0;
    my $norm_download_timing_seconds = 0;

    foreach my $hash (@{$json->{normal_specimen}{alignment}{timing_metrics}}) {
      #print Dumper $hash;
      $norm_merge_timing_seconds = $hash->{metrics}{merge_timing_seconds};
      if ($hash->{metrics}{bwa_timing_seconds} > $norm_bwa_timing_seconds) { $norm_bwa_timing_seconds = $hash->{metrics}{bwa_timing_seconds}; }
      $norm_download_timing_seconds = $hash->{metrics}{bwa_timing_seconds};
    }

    print "NORM\t$norm_merge_timing_seconds\t$norm_bwa_timing_seconds\t$norm_download_timing_seconds\n";

  }

  #if (defined ($json->{aligned_tumor_specimens}) ) {

    foreach my $tumor (@{$json->{aligned_tumor_specimens}}) {

      my $tumor_merge_timing_seconds = 0;
      my $tumor_bwa_timing_seconds = 0;
      my $tumor_download_timing_seconds = 0;

      #print Dumper($tumor);

      foreach my $hash (@{$tumor->{alignment}{timing_metrics}}) {
        #print Dumper $hash;
        $tumor_merge_timing_seconds = $hash->{metrics}{merge_timing_seconds};
        if ($hash->{metrics}{bwa_timing_seconds} > $tumor_bwa_timing_seconds) { $tumor_bwa_timing_seconds = $hash->{metrics}{bwa_timing_seconds}; }
        $tumor_download_timing_seconds = $hash->{metrics}{bwa_timing_seconds};
      }

      print "TUMOR\t$tumor_merge_timing_seconds\t$tumor_bwa_timing_seconds\t$tumor_download_timing_seconds\n";

    }

#  }

}

close IN;
