#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;


## we delete all files we don't need in this directory. Be careful in case users try running it somewhere else, outside this dir.
chdir $FindBin::Bin or die "error, cannot cd to $FindBin::Bin";



my @files_to_keep = qw (cleanme.pl 
                        README
                        reads.left.fq.gz
                        reads.right.fq.gz
                        runMe.sh
                        __indiv_ex_sample_derived
                        run_abundance_estimation_procedure.sh
                        __test_runMe.singleFQ.sh
                        __test_runMe_with_jaccard_clip.sh
                        __run_abundance_estimation_include_antisense.sh
                        __runMe_using_Grid.sh
                        __runMe_no_cleanup.sh
                        __runMe_as_DS.sh
                        __test_Trinity_using_LSF_at_Broad.sh

__run_read_normalization_fastq.sh
__run_read_normalization_pairs_together_fastq.sh
__run_read_normalization_fasta.sh
__run_read_normalization_pairs_together_fasta.sh
__run_read_normalization_single.sh
__runMe_no_reduce.sh
__runMe_w_monitoring.sh
longReads.fa
__runMe_include_long_reads.sh

__runMe_no_bowtie.sh
                        );


my %keep = map { + $_ => 1 } @files_to_keep;


`rm -rf trinity_out_dir/` if (-d "trinity_out_dir");
`rm -rf bowtie_out/` if (-d "bowtie_out");
`rm -rf RSEM.stat` if (-d "RSEM.stat");
`rm -rf trinity_single_outdir` if (-d "trinity_single_outdir");
`rm -rf bowtie_single_outdir` if (-d "bowtie_single_outdir");

`rm -rf normalized_reads_test`;
`rm -rf collectl`;

foreach my $file (<*>) {
	
	if (! $keep{$file}) {
		print STDERR "-removing file: $file\n";
		unlink($file);
	}
}


exit(0);
