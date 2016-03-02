#!/bin/bash -ve

if [ ! -e reads.left.fq ]; then
    gunzip -c ../test_Trinity_Assembly/reads.left.fq.gz > reads.left.fq
fi

if [ ! -e reads.right.fq ]; then
    gunzip -c ../test_Trinity_Assembly/reads.right.fq.gz > reads.right.fq
fi

if [ ! -e reads.right.disordered.fq ]; then
    ../../util/fastQ_to_tab.pl -I reads.right.fq | ../../util/shuffle.pl | ../../util/tab_to_fastQ.pl > reads.right.disordered.fq
fi


# just for testing purposes, use --max_cov 30 or higher for real applications.
../../util/normalize_by_kmer_coverage.pl --JM 2G --left reads.left.fq --right reads.right.disordered.fq --seqType fq --max_cov 5 --pairs_together --PE_reads_unordered 




