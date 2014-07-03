#!/bin/bash

#$1 = infile 1
#$2 = outfile
#$3 = cpu
#$4 = /path_to/RM_library.fasta
#$5 = second sample (infile 2)



echo '####################################'
echo '#                                  #'
echo '#         Trinity Only !!!         #'
echo '#                                  #'
echo '####################################'

echo '  _____                       _   ______            _                       ___'  
echo ' |  __ \                     | | |  ____|          | |                     |__ \' 
echo ' | |__) |___ _ __   ___  __ _| |_| |__  __  ___ __ | | ___  _ __ ___ _ __     ) |'
echo ' |  _  // _ \ \''_ \ / _ \/ _` | __|  __| \ \/ / \''_ \| |/ _ \| \''__/ _ \ \''__|   / / '
echo ' | | \ \  __/ |_) |  __/ (_| | |_| |____ >  <| |_) | | (_) | | |  __/ |     / /_ '
echo ' |_|  \_\___| .__/ \___|\__,_|\__|______/_/\_\ .__/|_|\___/|_|  \___|_|    |____|'
echo '            | |                              | |                                 '
echo '            |_|                              |_|      '





echo ''

echo 'Genomic repeats assembly/annotation/quantification pipeline using TRINITY - version 0.1'

echo ''

source conf
echo 'configuration file sourced'
mkdir $2
mkdir $2/Trinity_run1
echo ''
echo 'Let'\''s go...'

echo ''

date

echo ''

echo 'replacing reads header by integer...'
awk '/^>/{print">"(++i)}!/>/' $1 > $2/renamed.input.fasta
echo 'done'


##################TRINITY###############################
                                                       #
                                                       #
echo '###################################'
echo '### TRINITY to assemble repeats ###'
echo '###################################'
echo ''
echo '***** TRINITY iteration 1 *****'
echo ''
#export PATH=/usr/remote/jdk1.6.0_06/bin/java:$PATH

$Trinity --seqType fa --JM 10G --single $2/renamed.input.fasta --CPU $3 --min_glue 0 --output $2/Trinity_run1

echo ''
echo 'Trinity iteration 1 Done' 
date +"%T"
echo ''
echo 'Selecting reads for second Trinity iteration...'

cat $2/Trinity_run1/chrysalis/readsToComponents.out.sort | awk '{print $2; print $4}' | sed 's/>/>run1_/g' > $2/reads_run1.fasta
cat $2/reads_run1.fasta $5 > $2/reads_run2.fasta

echo 'Done'
echo ''
echo '***** TRINITY iteration 2 *****'
echo ''
$Trinity --seqType fa --JM 10G --single $2/reads_run2.fasta --CPU $3 --min_glue 0 --output $2

echo ''
echo 'Trinity iteration 2 Done' 
date +"%T"
echo ''

### rename fasta header according to old Trinity (<= 2013)
#sed -i 's/>c/>comp/g' $2/Trinity.fasta


echo 'renaming Trinity output...'
### rename Trinity contigs header to remove long parts with [ ]
cat $2/Trinity.fasta | awk '{print $1}' > Trinity.fasta
rm $2/Trinity.fasta
mv Trinity.fasta $2/
echo 'done'

###Computing statistics###
perl N50calc.pl $2/Trinity.fasta > $2/assembly.stats

echo ''
echo 'finishing time: '
date +"%T"
echo''
echo '########################'
echo '#   see you soon !!!   #'
echo '########################'






