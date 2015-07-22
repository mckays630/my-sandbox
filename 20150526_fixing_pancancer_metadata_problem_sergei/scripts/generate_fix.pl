#!/usr/bin/perl
use common::sense;
use JSON;
use XML::Simple;
use Data::Dumper;

$|++;


use constant INDEX => 'donor_p_150720020205.jsonl.gz';

my $index = INDEX;
my ($date) = $index =~ /donor_p_(\d+)\./;
$date =~ s/(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/20$1-$2-$3\_$4-$5-$6\_UTC/;

if (!-e $index || -z $index) { 
    say "Downloading $index...";
    system("curl http://pancancer.info/gnos_metadata/$date/$index > $index 2>/dev/null"); 
}

# map platform unit to read group, should be one-to-one
my $pu_to_rg = {};
my %all_pu;
my %bad_pu;
my %donor;
my %project;
my %fixed;
my %broken;

# parse out the info from the BAM headers
die "Where is the data folder?" unless -d 'data';
open D, "find data -name '*.txt' |";
my @files;
while (<D>) {
    chomp;
    push @files, $_;
}
close D;

my %seen_file;
for my $file (@files) {
    chomp(my $fname = `basename $file`);
    say STDERR "I have already seen file $fname" and next if $seen_file{$fname}++;

    open IN, "<$file" or die;
    while(<IN>) {
	chomp;
	if (/^\@RG/) {
	    my ($pu) = /PU:(\S+)/;
	    my ($rg) = /ID:(\S+)/;
	    die "NO PU!" unless $pu;
	    die "NO RG!" unless $rg;
	    
	    $all_pu{$pu}++;
	    
	    if ($pu_to_rg->{$pu} && $pu_to_rg->{$pu} ne $rg) {
		$bad_pu{$pu}++;
	    }
	    
	    $pu_to_rg->{$pu} = $rg;
	}
    }
    close IN;
}


my $total_pus = keys %all_pu;

for my $pu (keys %bad_pu) {
    say STDERR "Deleting duplicated PU $pu";
    delete $pu_to_rg->{$pu};
}

# now iterate over the index and make corrections where needed
# also track the number needing changes and the number finally changed

open IN, "gunzip -c $index | " or die "Can't open $index";

while (<IN>) {
  my $json = decode_json($_);

  my $donor = $json->{donor_unique_id};
  my $pcode = $json->{dcc_project_code};

  my @jds = ($json->{normal_specimen});
  push @jds, @{$json->{aligned_tumor_specimens}};

  my $specimen;
  for my $jd (@jds) {
      $specimen = $specimen ? 'TUMOR' : 'NORMAL';

      my $seen = {};
      my $broken = 0;

      # broken flag triggered if read_group_id is duplicated.
      for my $qc_entry (@{$jd->{alignment}{qc_metrics}}) {
	  $broken = $seen->{$qc_entry->{read_group_id}}++;
      }
      
      # if it's broken, need to fix the mapping and save out
      if ($broken) {
	  my ($repo,$xml_file,$url) = get_metadata_xml($jd);
	  
	  my $fixed_path  = "qc_metadata/fixed/$repo";
	  my $broken_path = "qc_metadata/broken/$repo"; 
	  system "mkdir -p $fixed_path";
	  
	  # Get the parts of the XML we need to mend.  Thankfully, they are literal JSON strings.
	  my $xml = XMLin("$broken_path/$xml_file") or die $!;
	  my $atts = $xml->{Result}->{analysis_xml}->{ANALYSIS_SET}->{ANALYSIS}->{ANALYSIS_ATTRIBUTES}->{ANALYSIS_ATTRIBUTE};
	  my $raw_qc_metrics = tag_value($atts,'qc_metrics');
	  my $qc_metrics = decode_json($raw_qc_metrics);
	  
	  my $rg_fixed;

	  my $num = my @qcm = @{$jd->{alignment}{qc_metrics}};
	  for (my $i = 0;$i < $num;$i++) {
	      my $qcm = $qcm[$i];
	      
	      my $qc_xml = $qc_metrics->{qc_metrics}->[$i];
	      
	      my $pu = $qcm->{'metrics'}{'platform_unit'};
	      my $rg = $qcm->{'read_group_id'};
	      my $new_rg = $pu_to_rg->{$pu} || '';

	      next if $new_rg && $new_rg eq $rg;
	      
	      my $xml1_pu  = $qc_xml->{metrics}->{platform_unit} || "HUH?";
	      die "XML and JSON PUs do not match $pu $xml1_pu" unless $xml1_pu eq $pu;
	      
	      $donor{$pu}   = $donor;
	      $project{$pu} = $pcode;
	      
	      if ($new_rg) {
		  $fixed{$specimen}{$donor}++;
		  say join("\t",'RG_FIXED', $donor, $pcode, $pu, $rg, $new_rg, $specimen);
		  $qc_xml->{read_group_id} = $new_rg;
		  $qc_xml->{metrics}->{readgroup} = $new_rg;
		  $rg_fixed++;
	      } 
	      else {
		  my $reason;
		  if (!$all_pu{$pu}) {
		      $reason = 'NOT SEEN';
		  }
		  elsif ($bad_pu{$pu}) {
		      $reason = 'NOT-UNIQUE';
		  }
		  $broken{$specimen}{$donor}++;
		  say join("\t",'RG_BROKEN', $donor, $pcode, $pu, $rg, $new_rg, $specimen, $reason);
	      }
	  }
	  
	  if ($rg_fixed) {
	      my $fixed_qc_metrics = encode_json($qc_metrics);
	      
	      my $out_file = "$fixed_path/$xml_file";
	      my $in_file  = "$broken_path/$xml_file";
	      open INXML, $in_file or die "Could not open $in_file: $!";
	      open OUTXML, ">$out_file" or die "Could not open $out_file: $!";
	      
	      while (<INXML>) {
		  if (/qc_metrics/ && /<VALUE>/) {
		      my ($space) = /^(\s+)/;;
		      $_ = qq($space<VALUE>$fixed_qc_metrics</VALUE>\n);
		  }
		  print OUTXML $_;
	      }
	      close OUTXML;
	      close INXML;
	  }
      }
  }
}

close IN;

my $normal_fixed  = keys %{$fixed{NORMAL}};
my $normal_broken = keys %{$broken{NORMAL}};
my $normal_total  = $normal_fixed + $normal_broken; 
my $tumor_fixed   = keys %{$fixed{TUMOR}};
my $tumor_broken  = keys %{$broken{TUMOR}};
my $tumor_total   = $tumor_fixed + $tumor_broken;

my %broken_donors = (%{$broken{NORMAL}}, %{$broken{TUMOR}});
my %fixed_donors = (%{$fixed{NORMAL}}, %{$fixed{TUMOR}});

my $total_fixed   = keys %fixed_donors;
my $total_broken  = keys %broken_donors;
my $total_total   = $total_fixed + $total_broken;

say "DONOR SUMMARY:";
say "NORMAL: TOTAL: $normal_total BROKEN: $normal_broken FIXED: $normal_fixed";
say "TUMOR:  TOTAL: $tumor_total BROKEN: $tumor_broken FIXED: $tumor_fixed";
say "TOTAL:  TOTAL: $total_total BROKEN: $total_broken FIXED: $total_fixed";

say "BAD PUs:";
for my $pu (sort keys %bad_pu) {
    say join("\t",$pu,$donor{$pu}||'.',$project{$pu}||'.');
}

sub get_metadata_xml {
    my $h = shift;

    my $url = $h->{'gnos_metadata_url'};
    my ($repo) = $url =~ m!//([^/]+)!;
    my ($id)   = $url =~ m!analysisFull/(\S+)!;
    $id or die "NO ID for $url";

    my $path = "qc_metadata/broken/$repo";
    system "mkdir -p $path";
    my $xml_file = "$path/$id.xml";

    system "cp $repo/$id.xml $path" if -e "$repo/$id.xml" && ! -z "$repo/$id.xml"; 

    return ($repo, "$id.xml", $url) if -e $xml_file && ! -z $xml_file;

    say "Dowloading $xml_file...";
    my $retval = system "curl $url > $xml_file 2>/dev/null"; 

    if ($retval || ! -e $xml_file || -z $xml_file) {
	say "Problem with $url, I will retry";
	$retval = system "curl $url > $repo/$id.xml";
    }
    if ($retval || ! -e $xml_file || -z $xml_file) {
	say "OK, I give up on this one for now";
    }

    return ($repo, "$id.xml", $url);
}


sub tag_value {
    my $array = shift;
    my $tag   = shift;
    my $value = shift;

    for (@$array) {
	next unless $_->{TAG} eq $tag;
	$_->{VALUE} = $value if $value;
	return $_->{VALUE};
    }
}
