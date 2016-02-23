#!/bin/bash

if [ ! -e reads.left.fq ] && [ -e reads.left.fq.gz ]; then
    gunzip -c reads.left.fq.gz > reads.left.fq
fi

if [ ! -e reads.left.fa ]; then
    ../../util/fastQ_to_fastA.pl -I reads.left.fq > reads.left.fa
fi


../../util/normalize_by_kmer_coverage.pl --seqType fa --single reads.left.fa  --JM 1G --max_cov 2 --output normalized_reads_test

