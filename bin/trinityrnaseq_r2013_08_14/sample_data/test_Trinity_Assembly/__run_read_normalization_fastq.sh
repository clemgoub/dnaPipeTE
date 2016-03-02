#!/bin/bash

if [ ! -e reads.left.fq ] && [ -e reads.left.fq.gz ]; then
    gunzip -c reads.left.fq.gz > reads.left.fq
fi


if [ ! -e reads.right.fq ] && [ -e reads.right.fq.gz ]; then
    gunzip -c reads.right.fq.gz > reads.right.fq
fi

../../util/normalize_by_kmer_coverage.pl --seqType fq --left reads.left.fq --right reads.right.fq --SS_lib_type RF --JM 1G --max_cov 2 --output normalized_reads_test

