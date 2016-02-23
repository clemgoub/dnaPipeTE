#!/bin/bash

if [ ! -e reads.left.fq ] && [ -e reads.left.fq.gz ]; then
    gunzip -c reads.left.fq.gz > reads.left.fq
fi

if [ ! -e reads.left.fa ]; then
    ../../util/fastQ_to_fastA.pl -I reads.left.fq > reads.left.fa
fi


if [ ! -e reads.right.fq ] && [ -e reads.right.fq.gz ]; then
    gunzip -c reads.right.fq.gz > reads.right.fq
fi

if [ ! -e reads.right.fa ]; then
    ../../util/fastQ_to_fastA.pl -I reads.right.fq > reads.right.fa
fi


../../util/normalize_by_kmer_coverage.pl --seqType fa --left reads.left.fa --right reads.right.fa --SS_lib_type RF --JM 1G --max_cov 2 --output normalized_reads_test

