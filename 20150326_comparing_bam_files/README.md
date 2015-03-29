# BAM Diff

A simple diff tool, uses SAM files for easy parsing, that reports differences between
two BAMs.  Ignores the mark duplicates flag since tools can randomly choose
equivalents reads to mark as duplicates.

## Prepare BAMs

  samtools view foo.bam chr22 > chr22.sam

## Run Comparison

time perl bam_diff.pl /drive/bam_2.6.0/c1cbdef5-4564-4444-a4b5-d48f87beb410/temp.sam /drive/bam_2.6.1/1da94974-e018-4af7-a34b-de4701d324d5/temp.sam 0 > run_log.txt

## Interpret Results

So any results where the read doesn't match will appear in the log file.  Those
can be futher extracted for analysis.

  print "$name\t$flag\t$chr\t$pos\t".$d->{$name}{$flag}{$chr}{$pos}."\n";
