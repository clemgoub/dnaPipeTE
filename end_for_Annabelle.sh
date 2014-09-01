echo 'Paring blast3 output...'
date +"%T"

cat $2/blast_out/reads_vs_Trinity.fasta.blast.out | sort -k1,1 -k12,12nr -k11,11n | sort -u -k1,1 > $2/blast_out/sorted.reads_vs_Trinity.fasta.blast.out

cat $2/blast_out/sorted.reads_vs_Trinity.fasta.blast.out | awk '{print $2"\t"$3}' | sed 's/_/\t/g' > Reads_to_components_Rtable.txt

echo 'Parsing done'
date +"%T"

echo "Computing reads to contigs (not components) with their annotations"

#extrait les reads qui hit sur les components (blast3) et garde read | comp_c_seq | %id
cat $2/blast_out/sorted.reads_vs_Trinity.fasta.blast.out | awk '{print $1 "\t"$2"\t"$3}' > $2/reads_to_component
#les ordonne par component
cat $2/reads_to_component | sort -k2,2 > $2/reads_to_component.sorted
cat $2/Annotation/one_RM_hit_per_Trinity_contigs | sort -k1,1 | awk '{ print $1 "\t" $3 "\t" $4}' | awk '/LINE/ { print $0 "\tLINE"; next} /LTR/ {print $0 "\tLTR"; next} /SINE/ {print $0 "\tSINE"; next} /ClassII/ {print $0 "\tClassII"; next} {print $0 "\tOther"}' > $2/annotations

join -a1 -12 -21 $2/reads_to_component.sorted $2/annotations > rtc_annoted

Rscript annotation.R


mv reads.per.component_annoted $2/blast_out/
mv rtc_annoted $2/blast_out/

echo 'Done, results in: "blast_out/reads.per.component_annoted"'
#Drawing graphs 

echo 'Drawing graphs...'
cp $2/blast_reads.counts .
cp $2/Counts.txt .
Rscript graph.R
Rscript pieChart.R
echo 'Done'

rm single.fa.read_count
mv Reads_to_components_Rtable.txt $2/
mv Reads_to_components.* $2/
mv TEs_piechart.* $2/
mv reads_per_component_sorted.txt $2/

echo ''
echo 'finishing time: '
date +"%T"
echo''
echo '########################'
echo '#   see you soon !!!   #'
echo '########################'