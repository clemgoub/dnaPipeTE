#!/bin/sh 

if [ -e Trinity.fasta.gz ] && [ ! -e Trinity.fasta ]
then
    gunzip -c Trinity.fasta.gz > Trinity.fasta
fi


../../trinity-plugins/transdecoder/transcripts_to_best_scoring_ORFs.pl -t Trinity.fasta 

echo
echo 
echo See best_candidates.\*  for candidate ORFs
echo



