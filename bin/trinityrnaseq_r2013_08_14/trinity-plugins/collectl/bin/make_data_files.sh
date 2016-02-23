#!/bin/bash
BINDIR=`dirname ${0}`
FILE=`ls ./y*raw.gz | tail -1`

test -z "$FILE" && exit

echo "
make data files
"

echo "$PWD"
echo "$FILE"
ls -la $FILE

# This is madness. This is Sparta.
gzip -tf $FILE
while [ "$?" != "0" ]; do
   echo "collectl has not yet finished"
   sleep 1
   gzip -tf $FILE
done
ls -la $FILE 

starttime=`${BINDIR}/collectl -P -p $FILE -sZ | head -2 | tail -1 | awk '{print $1 " " $2}'`
starttime_s=`date -d "$starttime" +"%s"`

reftime=`echo $starttime | awk '{print $1 " 00:00:00"}'`
reftime_s=`date -d "$reftime" +"%s"`

offsettime=`expr $reftime_s - $starttime_s + 60`
echo "offsettime: $offsettime s"

# playback: create file with process data
echo "replay of collectl data to offset time stamps"
${BINDIR}/collectl --offsettime "$offsettime" -P -p $FILE -sZ | grep -v "sh -c" >collectZ.all 2>/dev/null

endtime=`tail -1 collectZ.all | awk '{print $1 " " $2}'`
endtime_s=`date -d "$endtime" +"%s"`

# parameters of collectl
PARA=(`zcat $FILE | head -2 | tail -1`)
for ELEM in ${PARA[@]}
do 
  LEN=${#ELEM}
  # must at least be 3 chars - e.g. "-i5"
  if [ $LEN -ge 3 ]; then
    if [ ${ELEM:0:2} = "-i" ]; then
      COLPAR=${ELEM:2}
    fi
  fi
done

# save start and stop to file which is used to generate gnuplots 
echo "date $starttime" >global.time
echo "start $reftime" >>global.time
echo "end $endtime" >>global.time
echo "runtime $(( $endtime_s - $reftime_s )) " >>global.time
echo "interval $COLPAR" >>global.time

# Quantify Graph and Butterfly execute multiple sub-binaries which are summed up here
sum_up_procs()
{
  if [ $# -eq 1 ]; then 
    SAVENAME=$1
  else
    SAVENAME=$2
  fi 
  grep "$1" collectZ.all > ${ID}.${SAVENAME}.data
  if [ -s ${ID}.${SAVENAME}.data ] ; then
	  cat ${ID}.${SAVENAME}.data | awk '
	    /^[0-9]/
	    { 
	      nfields=30;
	      if (lt && $2!=lt) 
	      {
		printf("%s %s",a[1],a[2]); 
		for (i=3; i<nfields; i++) printf(" %s",a[i]); printf("\n");
		delete a
	      }
	      a[1]=$1; a[2]=$2;
	      for (i=3; i<nfields; i++) a[i]=a[i]+$i; 
	      lt=$2 
	    }
	  ' | grep -v "${1}" > ${ID}.${SAVENAME}.sum
  fi
}

# create data file per tool by grepping for the birary names
# the name in ouputfile before the .data is used in timing csv
# the ID is used for sorting in timing csv
# "collectZ.7.Chrysalis.data" yields "Chrysalis" being listed as the seventh tool called in the run
export ID=0
echo "generating files for each tool"
((ID++)); sum_up_procs "fastool"
((ID++)); sum_up_procs "plugins/jellyfish/bin/jellyfish" jellyfish
((ID++)); sum_up_procs "Inchworm/bin/inchworm" inchworm
((ID++)); sum_up_procs "[0-9] bowtie-build " bowtie-build
((ID++)); sum_up_procs "[0-9] bowtie " bowtie
#((ID++)); sum_up_procs "util/SAM_filter_out_unmapped_reads.pl " samfilter
((ID++)); sum_up_procs "coreutils/bin/sort " sort
#((ID++)); sum_up_procs "[0-9] samtools " samtools
((ID++)); sum_up_procs "util/scaffold_iworm_contigs.pl" scaffold
((ID++)); sum_up_procs "Chrysalis/GraphFromFasta" GraphFromFasta
((ID++)); sum_up_procs "Chrysalis/ReadsToTranscripts" ReadsToTranscripts
((ID++)); sum_up_procs "Chrysalis/Chrysalis" Chrysalis
((ID++)); sum_up_procs "Inchworm/bin/ParaFly" ParaFly
((ID++)); sum_up_procs "Chrysalis/QuantifyGraph" QuantifyGraph
((ID++)); sum_up_procs "java" Butterfly
#((ID++)); sum_up_procs "Trinity.pl" Trinity

ls -la

FILES=(`ls *.sum | sort --numeric-sort`)
INT=1
for FILE in ${FILES[@]}; do
  mv $FILE ${INT}.$FILE
  ((INT++))
done


# create per process file an print statistic - behold - awk magic ahead
grep -v "collectl-3" collectZ.all | awk '
/^#/{
  print $0 > "collectZ.proc";
  delete a;
  nfields=NF;}
/^[0-9]/{
  if(index($0,"usr/bin/collectl")) next;
  t=$2;
  if(lt && t!=lt) {
    printf("%s %s",ld,lt) > "collectZ.proc";
    for(i=3;i<nfields;i++) printf(" %s",a[i]) > "collectZ.proc";
    printf("\n") > "collectZ.proc";
    delete a;
  }
  for(i=3;i<nfields;i++) a[i]=a[i]+$i;
  lt=t;
  ld=$1;
  cmd=$nfields
  #for(i=nfields+1;i<=NF;i++) cmd=cmd " " $i
  #cmd=substr(cmd,1,112)
  cmds[cmd]+=$19; # % CPU
}
END{
    printf("%10s  %s\n", "sum(%CPU)", "cmd")
  for(cmd in cmds) {
    printf("%10d  %s\n", cmds[cmd], cmd)
  }
}
'

