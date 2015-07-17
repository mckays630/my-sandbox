#!/usr/bin/perl
use common::sense;
use JSON;
use Data::Dumper;

$|++;

# global counts
my $broken_cnt = 0;
my $broken_not_fix = 0;
my $broken_fixed = 0;
my %seen_pu;


use constant INDEX => 'donor_p_150716020204.jsonl.gz';
my $index = INDEX;

if (!-e $index || -z $index) { 
    say "Downloading $index...";
    say("curl http://pancancer.info/gnos_metadata/2015-07-16_02-02-04_UTC/$index > $index 2>/dev/null"); 
}

# map platform unit to read group, should be one-to-one
my $pu_to_rg = {};
my %pu;

# parse out the info from the BAM headers
die "Where is the data folder?" unless -d 'data';
open D, "find data -name '*.txt' |";
my @files;
while (<D>) {
    chomp;
    push @files, $_;
}
close D;

my %line;
my %file;
my %bad_pu;
foreach my $file (@files) {

  #print "PROCESSING FILE: $file\n";

  open IN, "<$file" or die;
  while(<IN>) {
    chomp;
    if (/^\@RG/) {
	my @a = split /\t/;
	
	my ($pu) = /PU:(\S+)/;
	my ($rg) = /ID:(\S+)/;
	die "NO PU!" unless $pu;
	die "NO RG!" unless $rg;

	say STDERR "NON UNIQUE PLATFORM UNIT TO READGROUP! PU='$pu' RG='$rg' ARCHIVE='". $pu_to_rg->{$pu}."'" 
	if ($pu_to_rg->{$pu} && $pu_to_rg->{$pu} ne $rg) {
	    push $bad_pu{$pu}++;
	}
	else {
	    $pu_to_rg->{$pu} = $rg;
	}
	
	$pu{$pu}{rg}{$rg}++;
	push @{$line{$pu}}, $_;
	$file{$_} = $file;
    }
  }
  close IN;
}


my $total_pus = keys %pu;

for my $pu (keys %bad_pu) {
    delete $pu_to_rg->{$pu};
}


# now iterate over the index and make corrections where needed
# also track the number needing changes and the number finally changed

open OUT, "| gzip -c > output.json.gz" or die;

open IN, "gunzip -c $index | " or die "Can't open $index";

my @to_download;

while (<IN>) {

  my $jd = decode_json($_);

  die Dumper $jd;

  # does this one need repairs???
  my $seen = {};
  my $broken = 0;

  # broken flag triggered if read_group_id is duplicated.
  for my $qc_entry (@{$jd->{normal_specimen}{alignment}{qc_metrics}}) {
      $broken = $seen->{$qc_entry->{read_group_id}}++;
  }

  print "BROKEN: $broken\n" if ($broken);

  # if it's broken, need to fix the mapping and save out
  if ($broken) {
      my $donor = $jd->{donor_unique_id};
      my $pcode = $jd->{dcc_project_code};
      push @to_download, $jd->{normal_specimen};
      my $rg_fixed = 0;
      my $rg_not_fixed = 0;

      $broken_cnt++;

      for (my $i=0; $i<scalar(@{$jd->{normal_specimen}{alignment}{qc_metrics}}); $i++) {
	  my $pu = $jd->{normal_specimen}{alignment}{qc_metrics}[$i]{'metrics'}{'platform_unit'};
	  my $rg = $jd->{normal_specimen}{alignment}{qc_metrics}[$i]{'read_group_id'};

	  say "PU: $pu";
	  say "RG: $rg";
	  say "NEW RG: ".$pu_to_rg->{$pu} || "NOT FOUND";

	  if ($pu{$pu}) {
	      $pu{$pu}{donor} = $donor;
	      $pu{$pu}{dcc_project_code} = $pcode;
	  }
	  
	  if ($pu_to_rg->{$pu}) {
	      $jd->{normal_specimen}{alignment}{qc_metrics}[$i]{'read_group_id'} = $pu_to_rg->{$pu};
	      $rg_fixed = 1;
	      say join("\t",'DONOR_FIXED', $pu, $rg, $donor);
	      
	  } else {
	      $rg_not_fixed = 1;
	      say join("\t",'DONOR_BROKEN', $pu, $rg, $donor);
	  }
	  
      }
      
      # now add back to global
      $broken_fixed += $rg_fixed;
      $broken_not_fix += $rg_not_fixed;
  }
  
  # now just print everything
  print OUT encode_json($jd) . "\n";
  
}

close IN;

close OUT;

# summary
print "SUMMARY: BROKEN: $broken_cnt FIXED: $broken_fixed NOT FIXED: $broken_not_fix\n";


for my $xml (@to_download) {
    get_metadata_xml($xml);
}



sub get_metadata_xml {
    my $h = shift;
    my $url = $h->{'gnos_metadata_url'};
    my ($repo) = $url =~ m!//([^/]+)!;
    my ($id)   = $url =~ m!analysisFull/(\S+)!;
    $id or die "NO ID $url";
    system "mkdir -p $repo";
    next if -e "$repo/$id.xml" && ! -z "$repo/$id.xml";;
    my $retval = system "curl $url > $repo/$id.xml"; 
    if ($retval) {
	say "Problem with $url, I will retry";
	$retval = system "curl $url > $repo/$id.xml";
    }
    if ($retval) {
	say "OK, I give up on this one for now";
    }
}
