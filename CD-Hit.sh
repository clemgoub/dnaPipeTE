# selection of unblasted reads for CD-HIT

cat sorted.reads_vs_unannoted.blast.out | awk '{print $1}' > reads_on_NAcontig.header
cat sorted.reads_vs_annoted.blast.out | awk '{print $1}' > reads_on_annot_contig.header
cat reads_on_* > all_matching_reads.header

perl -ne 'if(/^>(\S+)/){$c=!$i{$1}}$c?print:chomp;$i{$_}=1 if @ARGV' all_matching_reads.header ../renamed.blasting_reads.fasta > unblasted_reads.fa


cd-hit-est -i unblasted_reads.fa -o unmatching_clustering -c 0.9 -G 0 -aS 0.5 -aL 0.5 -M 2000 -T 8


grep '>Cluster' -B1 unmatching_clustering.clstr | grep -v '^-' | sed 's/Cluster /Cluster_/g' | awk '{print $1}' > cluster_intermediate
cat CDHIT_reads.per.cluster | tail unmatching_clustering.clstr -n 1 | awk '{print $1}' > cluster_lastline
cat  cluster_intermediate cluster_lastline > CDHIT_reads.per.cluster
grep '>Cluster' CDHIT_reads.per.cluster | sed 's/>//g' > CDHIT_clusternames
grep -v '>Cluster' CDHIT_reads.per.cluster  > CDHIT_readsNB
paste CDHIT_clusternames CDHIT_readsNB > CDHIT_reads.per.cluster.Rtable


$BlastOut=../blast_reads.counts
#cat CDHIT_reads.per.cluster.Rtable | awk -v var=$BlastOut '($2/var)>0.0001 {print $1 "\t" $2}' | head
cat CDHIT_reads.per.cluster.Rtable | awk -v var=$BlastOut '($2/var)>0.0001 {print $1 "\t" $2}' | sort -k2,2nr > CDHIT_ths_clusters


cat CDHIT_ths_clusters | awk '{print $1}' | sed 's/_/ /g' | sed 's/$/\$/g' > ths_cluster_list
cat unmatching_clustering.clstr | grep -f ths_cluster_list -A 1 | grep '>blast' | awk '{print $3}' | sed 's/\...//g' > ths_refRead
perl -ne 'if(/^>(\S+)/){$c=$i{$1}}$c?print:chomp;$i{$_}=1 if @ARGV' ths_refRead ../renamed.blasting_reads.fasta | grep -v '>' > ths_Reads_sequence

~/Downloads/RepeatMasker/RepeatMasker -pa 4 -s -lib ~/pbil-panhome/Pipeline_RE2/RM_custom_base.fa ths_Reads.fasta


cat ths_Reads.fasta.out |  sort -k 5,5 -k 1,1nr | awk 'BEGIN {prev_query = ""} {if($5 != prev_query) {print $5"\t"$10"\t"$11}}' | grep 'blast' > ths_refRead_RM.list
cat ths_refRead_RM.list | awk '{print $1}' | sed 's/$/\$/g' > ths_refRead_RM.grep
paste CDHIT_ths_clusters ths_refRead | grep -f ths_refRead_RM.grep > ths_MATCH_RM
paste CDHIT_ths_clusters ths_refRead | grep -vf ths_refRead_RM.grep > ths_unMATCH_RM

cat ths_MATCH_RM | sort -k 3,3 > s.ths_MATCH_RM
cat ths_refRead_RM.list | sort -k 1,1 > s.ths_refRead_RM.list

paste s.ths_MATCH_RM s.ths_refRead_RM.list | awk '{print $1 "\t" $2 "\t" $5 "\t" $6}' > CD_HIT_annot_clusters
cat ths_unMATCH_RM | awk '{print $1 "\t" $2 "\tNo_Hit\tNo_Hit"}' > CD_HIT_unannot_clusters
cat CD_HIT_annot_clusters CD_HIT_unannot_clusters | sort -k2,2nr > CD_HIT_Final_RMannot_parsed
