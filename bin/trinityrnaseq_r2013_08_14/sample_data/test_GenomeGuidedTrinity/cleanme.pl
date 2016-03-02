#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;


## we delete all files we don't need in this directory. Be careful in case users try running it somewhere else, outside this dir.
chdir $FindBin::Bin or die "error, cannot cd to $FindBin::Bin";



my @files_to_keep = qw (
SP2.chr.bam
SP2.chr.fa.gz
cleanme.pl
mm9chr17.annotation.bed.gz
mm9chr17.fasta.gz
mm9chr17.tophat.bam
SP2.annot.bed.gz
SP2.chr.SE.sam.gz
run_Schizo_TrinityGG.sh
run_Schizo_TrinityGG_jaccard_clip.sh
run_mouse_TrinityGG.sh

                        );


my %keep = map { + $_ => 1 } @files_to_keep;


foreach my $file (<*>) {
	
	if (! $keep{$file}) {
		print STDERR "-removing file: $file\n";
		unlink($file);
	}
}

`rm -rf Dir*`;


exit(0);
