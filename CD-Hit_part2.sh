source conf

echo ''
echo 'Parsing CD-HIT out for RM annotation...'
date +"%T"

grep '>Cluster' -B1 $2/CD_HIT/unmatching_clustering.clstr | grep -v '^-' | sed 's/Cluster /Cluster_/g' | awk '{print $1}' > $2/CD_HIT/cluster_intermediate

tail $2/CD_HIT/unmatching_clustering.clstr -n 1 | awk '{print $1}' > $2/CD_HIT/cluster_lastline

cat  $2/CD_HIT/cluster_intermediate $2/CD_HIT/cluster_lastline > $2/CD_HIT/CDHIT_reads.per.cluster

grep '>Cluster' $2/CD_HIT/CDHIT_reads.per.cluster | sed 's/>//g' > $2/CD_HIT/CDHIT_clusternames

grep -v '>Cluster' $2/CD_HIT/CDHIT_reads.per.cluster  > $2/CD_HIT/CDHIT_readsNB

paste $2/CD_HIT/CDHIT_clusternames $2/CD_HIT/CDHIT_readsNB > $2/CD_HIT/CDHIT_reads.per.cluster.Rtable

BlastOut=$(more $2/blast_reads.counts)

#Ne garde que les clusters > 0.01%###
cat $2/CD_HIT/CDHIT_reads.per.cluster.Rtable | awk -v var=$BlastOut '($2/var)>0.0001 {print $1 "\t" $2}' | sort -k2,2nr > $2/CD_HIT/CDHIT_ths_clusters

cat $2/CD_HIT/CDHIT_ths_clusters | awk '{print $1}' | sed 's/_/ /g' | sed 's/$/\$/g' > $2/CD_HIT/ths_cluster_list

cat $2/CD_HIT/unmatching_clustering.clstr | grep -f $2/CD_HIT/ths_cluster_list -A 1 | grep '>blast' | 
awk '{print $3}' | sed 's/\...//g' | sed 's/>//g' > $2/CD_HIT/ths_refRead

perl -ne 'if(/^>(\S+)/){$c=$i{$1}}$c?print:chomp;$i{$_}=1 if @ARGV' $2/CD_HIT/ths_refRead $2/renamed.blasting_reads.fasta > $2/CD_HIT/ths_Reads.fasta

cat $2/CD_HIT/ths_Reads.fasta| grep -v '>' > $2/CD_HIT/ths_Reads_sequence

echo ''
echo 'Parsing done'
date +"%T"
echo ''
echo 'Running RepeatMasker to annotate CD-HIT clusters...'
date +"%T"

$RepeatMasker -pa $3 -s -lib $4 $2/CD_HIT/ths_Reads.fasta

echo ''
echo 'Done'
date +"%T"
echo ''
echo 'Parsing RepeatMasker outputs...'

cat $2/CD_HIT/ths_Reads.fasta.out |  sort -k 5,5 -k 1,1nr | awk 'BEGIN {prev_query = ""} {if($5 != prev_query) {print $5"\t"$10"\t"$11}}' | grep 'blast' > $2/CD_HIT/ths_refRead_RM.list
cat $2/CD_HIT/ths_refRead_RM.list | awk '{print $1}' | sed 's/$/\$/g' > $2/CD_HIT/ths_refRead_RM.grep
# Récupère les clusters annotés
paste $2/CD_HIT/CDHIT_ths_clusters $2/CD_HIT/ths_refRead | grep -f $2/CD_HIT/ths_refRead_RM.grep > $2/CD_HIT/ths_MATCH_RM
# Récupère les clusters non annotés
paste $2/CD_HIT/CDHIT_ths_clusters $2/CD_HIT/ths_refRead | grep -vf $2/CD_HIT/ths_refRead_RM.grep > $2/CD_HIT/ths_unMATCH_RM

#Mets les fichiers dans le même ordre pour coller les colones
cat $2/CD_HIT/ths_MATCH_RM | sort -k 3,3 > $2/CD_HIT/s.ths_MATCH_RM
cat $2/CD_HIT/ths_refRead_RM.list | sort -k 1,1 > $2/CD_HIT/s.ths_refRead_RM.list

paste $2/CD_HIT/s.ths_MATCH_RM $2/CD_HIT/s.ths_refRead_RM.list | awk '{print $1 "\t" $2 "\t" $5 "\t" $6}' > $2/CD_HIT/CD_HIT_annot_clusters
cat $2/CD_HIT/ths_unMATCH_RM | awk '{print $1 "\t" $2 "\tNo_Hit\tNo_Hit"}' > $2/CD_HIT/CD_HIT_unannot_clusters
cat $2/CD_HIT/CD_HIT_annot_clusters $2/CD_HIT/CD_HIT_unannot_clusters | sort -k2,2nr > $2/CD_HIT/CD_HIT_Final_RMannot_parsed

echo ''
echo 'Parsing done'
echo ''
echo '#############################################'
echo '#  Satellites / Simple Repeats search Done  #'
echo '# Found repeats and counts will be found in #'
echo '#       "CD_HIT_Final_RMannot_parsed"       #'
echo '#############################################'
date +"%T"
