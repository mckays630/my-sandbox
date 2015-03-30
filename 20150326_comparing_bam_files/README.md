# BAM Diff

A simple diff tool that reports differences between
two BAMs.  Ignores the mark duplicates flag since tools can randomly choose
equivalents reads to mark as duplicates.

## Run Comparison

  time perl bam_diff_v2.pl /drive/bam_2.6.0/c1cbdef5-4564-4444-a4b5-d48f87beb410/2d1f4e651ad13b3a9c1d3ceceaaaa1d3.bam /drive/bam_2.6.1/1da94974-e018-4af7-a34b-de4701d324d5/ec1dbea57e3bbb155f7ea6f42cfd6b91.bam 0

## Interpret Results

So any results where the read doesn't match will appear in the log file.  Those
can be futher extracted for analysis.

  print "$name\t$flag\t$chr\t$pos\t".$d->{$name}{$flag}{$chr}{$pos}."\n";
