#!/usr/bin/perl
use common::sense;
use JSON;
use XML::Simple;
use Data::Dumper;

$|++;

#use constant INDEX => 'donor_p_150720020205.jsonl.gz';
#use constant INDEX => 'donor_p_150818020207.jsonl.gz';
use constant INDEX => 'donor_p_150821020208.jsonl.gz';

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


open IN, "gunzip -c $index | " or die "Can't open $index";

my %bad_metadata = ();
my %still_broken = ();
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

	  my ($id)   = $url =~ m!analysisFull/(\S+)!;
	  my $fixed_path  = "qc_metadata/fixed/$repo";
	  my $broken_path = "qc_metadata/broken/$repo"; 
	  #say "$fixed_path/$xml_file";
	  #next if -e "$fixed_path/$xml_file";
	  system "mkdir -p $fixed_path";

	  # Get the parts of the XML we need to mend.  Thankfully, they are literal JSON strings.
	  my $xml = eval{XMLin("$broken_path/$xml_file")};
	  unless ($xml) {
	      say "Problem with $xml_file, skipping: $@";
	      next;
	  }

#	  $xml_file = "$repo/$xml_file";

	  my $atts = $xml->{Result}->{analysis_xml}->{ANALYSIS_SET}->{ANALYSIS}->{ANALYSIS_ATTRIBUTES}->{ANALYSIS_ATTRIBUTE};
	  my $raw_qc_metrics = tag_value($atts,'qc_metrics');
	  unless ($raw_qc_metrics) {
	      ($repo,$xml_file,$url) = get_metadata_xml($jd,1);
	      $xml = eval{XMLin("$broken_path/$xml_file")};
	      $atts = $xml->{Result}->{analysis_xml}->{ANALYSIS_SET}->{ANALYSIS}->{ANALYSIS_ATTRIBUTES}->{ANALYSIS_ATTRIBUTE};
	      my $raw_qc_metrics = tag_value($atts,'qc_metrics');
	      unless ($raw_qc_metrics) {
		  say "NO QC_METRICS\t$id\t$url";
		  $bad_metadata{$specimen}{$url}++;
		  next;
	      }
	  }
	  my $qc_metrics = eval{decode_json($raw_qc_metrics)};
	  
	  if (!$qc_metrics) {
	      say "Problem parsing JSON: $@";
	      say "RAW: ".$raw_qc_metrics;
	      $bad_metadata{$specimen}{$url}++;
	      next;
	  }
	      
	  my $rg_fixed;

	  my $num = my @qcm = @{$jd->{alignment}{qc_metrics}};
	  for (my $i = 0;$i < $num;$i++) {
	      my $qcm = $qcm[$i];
	      
	      my $qc_xml = $qc_metrics->{qc_metrics}->[$i];

	      my $pu = $qcm->{'metrics'}{'platform_unit'};
	      my $rg = $qcm->{'read_group_id'};
	      my $new_rg = $pu_to_rg->{$pu} || '';

	      if ($new_rg && $new_rg eq $rg) {
		  next;
	      }
	      
	      my $xml_pu = $qc_xml->{metrics}->{platform_unit} || "HUH?";
	      my $xml_rg = $qc_xml->{read_group_id};
	      die "XML and JSON PUs do not match $pu $xml_pu" unless $xml_pu eq $pu;
	      
	      if ($xml_rg eq $new_rg) {
		  next;
	      }

	      $donor{$pu}   = $donor;
	      $project{$pu} = $pcode;
	      
	      if ($new_rg) {
		  $fixed{$specimen}{$donor}++;
		  say join("\t",'RG_FIXED', $donor, $id, $specimen, $pu, $rg, $new_rg);
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
		  say join("\t",'RG_BROKEN',  $donor, $id, $specimen);#"$broken_path/$xml_file", $pcode, $pu, $rg, $new_rg, $specimen, $reason);
		  $still_broken{$url}++;
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
	      say "NOT OK FIXED\t$url";
	  }
	  elsif (!$still_broken{$url}) {
	      say "OK\t$url";
	  }
	  else {
	      say "NOT OK BROKEN\t$url";
	  }
      }
  }
}

close IN;


my $normal_fixed  = keys %{$fixed{NORMAL}};
my $normal_broken = keys %{$broken{NORMAL}};
my $normal_bad    = keys %{$bad_metadata{NORMAL}} || 0;
my $normal_total  = $normal_fixed + $normal_broken + $normal_bad; 

my $tumor_fixed   = keys %{$fixed{TUMOR}};
my $tumor_broken  = keys %{$broken{TUMOR}};
my $tumor_bad     = keys %{$bad_metadata{TUMOR}} || 0;
my $tumor_total   = $tumor_fixed + $tumor_broken + $tumor_bad;

my %broken_donors = (%{$broken{NORMAL}}, %{$broken{TUMOR}});
my %fixed_donors  = (%{$fixed{NORMAL}}, %{$fixed{TUMOR}});
my %bad_donors    = (%{$bad_metadata{NORMAL}}, %{$bad_metadata{TUMOR}});

my $total_fixed   = keys %fixed_donors;
my $total_broken  = keys %broken_donors;
my $total_bad     = keys %bad_donors || 0;
my $total_total   = $total_fixed + $total_broken + $total_bad;

say "DONOR SUMMARY:";
say "NORMAL: TOTAL: $normal_total BROKEN: $normal_broken FIXED: $normal_fixed BAD_METADATA: $normal_bad";
say "TUMOR:  TOTAL: $tumor_total BROKEN: $tumor_broken FIXED: $tumor_fixed BAD_METADATA: $tumor_bad";
say "TOTAL:  TOTAL: $total_total BROKEN: $total_broken FIXED: $total_fixed BAD_METADATA: $total_bad";


if (keys %bad_donors) {
    say "EMPTY METADATA:";
    say join("\n",keys %bad_donors);
}

if (keys %still_broken) {
    say "Remaining URLS for broken metadata:";
    say join("\n",keys %still_broken);
}


sub get_metadata_xml {
    my $h = shift;
    my $force = shift;

    my $url = $h->{'gnos_metadata_url'};
    my ($repo) = $url =~ m!//([^/]+)!;
    my ($id)   = $url =~ m!analysisFull/(\S+)!;
    $id or die "NO ID for $url";

    my $path = "qc_metadata/broken/$repo";
    system "mkdir -p $path";
    my $xml_file = "$path/$id.xml";

    unless ($force) {
	if (-e "timing_metadata/fixed/$repo/$id/xml" && eval{XMLin("timing_metadata/fixed/$repo/$id/xml")}) {
	    say "GRABBING TIMING METASATA FIX";
	    system "cp timing_metadata/fixed/$repo/$id.xml $path";
	}
	elsif (-e "$repo/$id.xml" && eval{XMLin("$repo/$id.xml")}) {
	    system "cp $repo/$id.xml $path";
	}
	
	return ($repo, "$id.xml", $url) if -e $xml_file && eval{XMLin($xml_file)};
    }

    say "Dowloading $xml_file...";
    my $retval = system "curl $url > $xml_file 2>/dev/null"; 

    if ($retval || ! -e $xml_file || -z $xml_file || !eval{XMLin($xml_file)}) {
	say "Problem with $url, I will retry";
	$retval = system "curl $url > $repo/$id.xml";
    }
    if ($retval || ! -e $xml_file || -z $xml_file || !eval{XMLin($xml_file)}) {
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




