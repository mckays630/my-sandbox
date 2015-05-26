use strict;
use JSON;
use Data::Dumper;

if (!-e "donor_p_150526020206.jsonl.gz") { system("wget http://pancancer.info/gnos_metadata/2015-05-26_02-02-06_UTC/donor_p_150526020206.jsonl.gz"); }

open IN, "gunzip -c donor_p_150526020206.jsonl.gz | " or die "Can't open donor_p_150526020206.jsonl.gz";

while (<IN>) {
  my $jd = decode_json ($_);
  print Dumper $jd;
  die;
}

close IN;
