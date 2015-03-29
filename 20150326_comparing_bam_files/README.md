# BAM Diff

A simple diff tool, uses SAM files for easy parsing, that reports differences between
two BAMs.  Ignores the mark duplicates flag since tools can randomly choose
equivalents reads to mark as duplicates.

## Prepare BAMs

  samtools view foo.bam chr22 > chr22.sam

## Run Comparison

  time perl bam_diff.pl chr22.1.sam chr22.2.sam > report.txt

## Interpret Results
