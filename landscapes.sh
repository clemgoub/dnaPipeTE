#!/bin/bash

#sort le blast sur tous les contigs par nom de contig pour pouvoir faire le join avec les annotations
cat ../blast_out/sorted.reads_vs_Trinity.fasta.blast.out | sort -k2,2 > sorted_blast3
#annote chaque read (sorted_blast3) avec les sorties de repeat masker en gardant l'info famille type : LINE/I etc... (pour l'instant regroupe tous les classII)
join -12 -21 sorted_blast3 one_RM_hit_per_Trinity_contigs -o 1.3,2.4,2.5 | awk '/LINE/ { print $0 "\t" $3; next} /LTR/ {print $0 "\t" $3; next} /SINE/ {print $0 "\tSINE"; next} /ClassII/ {print $0 "\tClassII"; next} {print $0 "\tOther"}' | grep 'LINE\|SINE\|LTR\|ClassII' > reads_lanscape


#fais la liste des super familles sélectionnées précédement
cat reads_lanscape | awk '{print $3}' | sed 's/Unknow\//DNA\//g' | sort -u -k1,1 > sorted_families
#adjoint à cette liste les couleurs correspondantes ainsi que la classe pour les organiser dans R
join -11 -22 sorted_families list_of_RM_superclass_colors_sorted | awk '{print $1 "\t" $2 "\t\""$3"\""}' | sort -k2,2 > factors_and_colors

#compute landscape graph with R
Rscript landscapes.R