# copyright, 2003-2009 Hewlett-Packard Development Company, LP

# Call with --custom "lexpr[,switches]
# Debug
#   1 - show all names/values, noting the timestamps are now!
#   2 - just show names/values 'sent'
#   4 - include real times in timestamps (useful for testing) along with skipped intervals
#   8 - do not send anything 
#       (useful when displaying normal output on terminal)
#  16 - show 'x' processing

our $lexInterval;
my ($lexSubsys, $lexDebug, $lexCOFlag, $lexTTL, $lexFilename, $lexSumFlag);
my (%lexDataLast, %lexDataMin, %lexDataMax, %lexDataTot, %lexTTL);
my ($lexColInt, $lexSendCount, $lexFlags);
my ($lexMinFlag, $lexMaxFlag, $lexAvgFlag, $lexTotFlag)=(0,0,0,0);
my $lexOneTB=1024*1024*1024*1024;
my $lexSamples=0;
my $lexOutputFlag=1;
my $lexFirstInt=1;
my $lexAlignFlag=0;
my $lexCounter;
my $lexExtName='';

sub lexprInit
{
  error('--showcolheader not supported by lexpr')    if $showColFlag;

  # on the odd chance someone did -s-all and have other ways to generate data, collectl
  # hasn't yet hit the code that resets $subsys so we have to do it here.
  $subsys=''    if $userSubsys eq '-all';

  # Defaults for options
  $lexDebug=$lexCOFlag=0;
  $lexFilename='';
  $lexInterval='';
  $lexSubsys=$subsys;
  $lexTTL=5;

  foreach my $option (@_)
  {
    my ($name, $value)=split(/=/, $option, 2);   # in case more than 1 = in single option string
    error("invalid lexpr option '$name'")    if $name!~/^[dfhisx]?$|^align$|^co$|^ttl$|^min$|^max$|^avg$|^tot$/;

    $lexAlignFlag=1        if $name eq 'align';
    $lexCOFlag=1           if $name eq 'co';
    $lexDebug=$value       if $name eq 'd';
    $lexFilename=$value    if $name eq 'f';
    $lexInterval=$value    if $name eq 'i';
    $lexSubsys=$value      if $name eq 's';
    $lexExtName=$value     if $name eq 'x';
    $lexTTL=$value         if $name eq 'ttl';
    $lexMinFlag=1          if $name eq 'min';
    $lexMaxFlag=1          if $name eq 'max';
    $lexAvgFlag=1          if $name eq 'avg';
    $lexTotFlag=1          if $name eq 'tot';

    help()                 if $name eq 'h';

    last    if $lexExtName ne '';
  }

  # If importing data, and if not reporting anything else, $subsys will be ''
  $lexSumFlag=$lexSubsys=~/[cdfilmnstxE]/ ? 1 : 0;

  # s= disables ALL subsys, only makes sense with imports
  error("lexpr subsys options '$lexSubsys' not a proper subset of '$subsys'")
	    if $subsys ne '' && $lexSubsys ne '' && $lexSubsys!~/^[$subsys]+$/;
 
  error("lexpr cannot write a snapshot file and use a socket at the same time")
	if $sockFlag && $lexFilename ne '';

  # Using -f and f= will not result in raw or plot file so need this message.
  error ("using lexpr option 'f=' AND -f requires -P and/or --rawtoo")
	if $lexFilename ne '' && $filename ne '' && !$plotFlag && !$rawtooFlag;

  # if -f, use that dirname/L for snampshot file; otherwise use f= for it.
  $lexFilename=(-d $filename) ? "$filename/L" : dirname($filename)."/L"
	if $lexFilename eq '' && $filename ne '';

  $lexFlags=$lexMinFlag+$lexMaxFlag+$lexAvgFlag|$lexTotFlag;
  error("only 1 of 'min', 'max', 'avg' or 'tot' with 'lexpr'")    if $lexFlags>1;

  # check for consistent intervals in interactive mode
  if ($playback eq '')
  {
    $lexColInt=(split(/:/, $interval))[0];
    $lexInterval=$lexColInt    if $lexInterval eq '';
    $lexSendCount=int($lexInterval/$lexColInt);
    error("lexpr interval of '$lexInterval' is not a multiple of collectl interval of '$lexColInt' seconds")
    		 if $lexColInt*$lexSendCount != $lexInterval;
    error("'min', 'max', 'avg' & 'tot' require lexpr 'i' that is > collectl's -i")
    		 if $lexFlags && $lexSendCount==1;

    if ($lexAlignFlag)
    {
      my $div1=int(60/$lexColInt);
      my $div2=int($lexColInt/60);
      error("'align' requires collectl interval be a factor or multiple of 60 seconds")
      		     if ($lexColInt<=60 && $div1*$lexColInt!=60) || ($lexColInt>60 && $div2*60!=$lexColInt);
      error("'align' only makes sense when multiple samples/interval")	  if $lexInterval<=$lexColInt;
      error("'lexpr,align' requires -D or --align")                       if !$alignFlag && !$daemonFlag;
    }
  }

  if ($lexExtName ne '')
  {
    # build up swiches from EVERYTHING seen after x=
    my $xSeen=0;
    my $switches='';
    foreach my $option (@_)
    {
      $xSeen=1    if $option=~/^x/;
      $switches.="$option,"     if $xSeen && $option!~/^x/;
    }
    $switches=~s/,$//;

    ($lexExtName, $switches)=(split(/:/, $lexExtName, 2))[0,1]    if $lexExtName=~/:/;    # backwards compatibility with : for switches
    $lexExtBase=$lexExtName;
    $lexExtBase=~s/\..*//;    # in case extension
    $lexExtName.='.ph'    if $lexExtName!~/\./;
    #print "NAME: $lexExtName  Switches: $switches\n";

    $tempName=$lexExtName;   # name for error message before prepending with directory
    $lexExtName="$ReqDir/$lexExtName"    if !-e $lexExtName;
    if (!-e "$lexExtName")
    {
      my $temp="can't find lexpr extension file '$tempName' in ./";
      $temp.=" OR $ReqDir/"    if $ReqDir ne '.';
      error($temp);
    }
    require $lexExtName;
    print "$lexExtName loaded\n"    if $lexDebug & 16;

    # rather than pass an undefined switch, if not there don't pass anything
    my $initName="${lexExtBase}Init";
    if (defined($switches))
    { 
      print "$initName($switches)\n"    if $debug & 16;
      &$initName($switches);
    }
    else
    { &$initName(); }
  }

  # need to reset here in case processing multiple files
  $lexCounter=0;
}

sub lexpr
{
  # since our init routine gets call BEFORE playback processing we have to wait until first interval to do this
  if ($lexFirstInt && $playback ne '')
  {
    # you might be able to align with data collected with --align or -D, but I'd rather discourage this
    $lexColInt=(split(/:/, $recInterval))[0];
    $lexInterval=$lexColInt    if $lexInterval eq '';
    $lexSendCount=int($lexInterval/$lexColInt);
    error("lexpr interval of '$lexInterval' is not a multiple of recorded interval of '$lexColInt' seconds")
    		 if $lexColInt*$lexSendCount != $lexInterval;
    error("'align' not supported with -p")                              if $lexAlignFlag;
    error("'min', 'max', 'avg' & 'tot' require lexpr 'i' that is > collectl's -i")
    		 if $lexFlags && $lexSendCount==1;
  }
  $lexFirstInt=0;

  # if not time to print and we're not doing min/max/avg/tot, there's nothing to do.
  # BUT if align, always make sure time aligns to top of minute based on i= and NOT sendCount
  $lexCounter++;
  $lexSamples++;
  $lexOutputFlag=(($lexCounter % $lexSendCount) ==0) ? 1 : 0               if !$lexAlignFlag;
  $lexOutputFlag=(!(int($lastSecs[$rawPFlag]) % $lexInterval)) ? 1 : 0     if  $lexAlignFlag;
  #print "Align: $lexAlignFlag Counter: $lexCounter  LexSend: $lexSendCount  Last: $lastSecs[$rawPFlag]  Output: $lexOutputFlag\n";

  return    if (!$lexOutputFlag && $lexFlags==0);

  my ($cpuSumString,$cpuDetString)=('','');
  if ($lexSubsys=~/c/i)
  {
    if ($lexSubsys=~/c/)
    {
      # CPU utilization is a % and we don't want to report fractions
      my $i=$NumCpus;

      $cpuSumString.=sendData("cputotals.num",   $i, 1);
      $cpuSumString.=sendData("cputotals.user",  $userP[$i], 1);
      $cpuSumString.=sendData("cputotals.nice",  $niceP[$i], 1);
      $cpuSumString.=sendData("cputotals.sys",   $sysP[$i], 1);
      $cpuSumString.=sendData("cputotals.wait",  $waitP[$i], 1);
      $cpuSumString.=sendData("cputotals.irq",   $irqP[$i], 1);
      $cpuSumString.=sendData("cputotals.soft",  $softP[$i], 1);
      $cpuSumString.=sendData("cputotals.steal", $stealP[$i], 1);
      $cpuSumString.=sendData("cputotals.idle",  $idleP[$i], 1);

      # These 2 are redundant, but also handy
      $cpuSumString.=sendData("cputotals.systot",  $sysP[$i]+$irqP[$i]+$softP[$i]+$stealP[$i], 1);
      $cpuSumString.=sendData("cputotals.usertot", $userP[$i]+$niceP[$i], 1);
      $cpuSumString.=sendData("cputotals.total",   $sysP[$i]+$irqP[$i]+$softP[$i]+$stealP[$i]+$userP[$i]+$niceP[$i], 1);

      $cpuSumString.=sendData("ctxint.ctx",  $ctxt/$intSecs);
      $cpuSumString.=sendData("ctxint.int",  $intrpt/$intSecs);

      $cpuSumString.=sendData("proc.creates", $proc/$intSecs);
      $cpuSumString.=sendData("proc.runq",    $loadQue, 1);
      $cpuSumString.=sendData("proc.run",     $loadRun, 1);

      $cpuSumString.=sendData("cpuload.avg1",  $loadAvg1, 1, '%4.2f');
      $cpuSumString.=sendData("cpuload.avg5",  $loadAvg5, 1, '%4.2f');
      $cpuSumString.=sendData("cpuload.avg15", $loadAvg15, 1,'%4.2f');
    }

    if ($lexSubsys=~/C/)
    {
      for (my $i=0; $i<$NumCpus; $i++)
      {
        $cpuDetString.=sendData("cpuinfo.user.cpu$i",   $userP[$i], 1);
        $cpuDetString.=sendData("cpuinfo.nice.cpu$i",   $niceP[$i], 1);
        $cpuDetString.=sendData("cpuinfo.sys.cpu$i",    $sysP[$i], 1);
        $cpuDetString.=sendData("cpuinfo.wait.cpu$i",   $waitP[$i], 1);
        $cpuDetString.=sendData("cpuinfo.irq.cpu$i",    $irqP[$i], 1);
        $cpuDetString.=sendData("cpuinfo.soft.cpu$i",   $softP[$i], 1);
        $cpuDetString.=sendData("cpuinfo.steal.cpu$i",  $stealP[$i], 1);
        $cpuDetString.=sendData("cpuinfo.idle.cpu$i",   $idleP[$i], 1);
        $cpuDetString.=sendData("cpuinfo.intrpt.cpu$i", $intrptTot[$i], 1);

        $cpuSumString.=sendData("cputotals.systot.cpu$i",  $sysP[$i]+$irqP[$i]+$softP[$i]+$stealP[$i], 1);
        $cpuSumString.=sendData("cputotals.usertot.cpu$i", $userP[$i]+$niceP[$i], 1);
      }
    }
  }

  my ($diskSumString,$diskDetString)=('','');
  if ($lexSubsys=~/d/i)
  {
    if ($lexSubsys=~/d/)
    {
      $diskSumString.=sendData("disktotals.reads",    $dskReadTot/$intSecs);
      $diskSumString.=sendData("disktotals.readkbs",  $dskReadKBTot/$intSecs);
      $diskSumString.=sendData("disktotals.writes",   $dskWriteTot/$intSecs);
      $diskSumString.=sendData("disktotals.writekbs", $dskWriteKBTot/$intSecs);
    }

    if ($lexSubsys=~/D/)
    {
      for (my $i=0; $i<@dskOrder; $i++)
      {
        # preserve display order but skip any disks not seen this interval
        $dskName=$dskOrder[$i];
        next    if !defined($dskSeen[$i]);
        next    if ($dskFiltKeep eq '' && $dskName=~/$dskFiltIgnore/) || ($dskFiltKeep ne '' && $dskName!~/$dskFiltKeep/);

        $diskDetString.=sendData("diskinfo.reads.$dskName",    $dskRead[$i]/$intSecs);
        $diskDetString.=sendData("diskinfo.readkbs.$dskName",  $dskReadKB[$i]/$intSecs);
        $diskDetString.=sendData("diskinfo.writes.$dskName",   $dskWrite[$i]/$intSecs);
        $diskDetString.=sendData("diskinfo.writekbs.$dskName", $dskWriteKB[$i]/$intSecs);
        $diskDetString.=sendData("diskinfo.quelen.$dskName",   $dskQueLen[$i]/$intSecs);
        $diskDetString.=sendData("diskinfo.wait.$dskName",     $dskWait[$i]/$intSecs);
        $diskDetString.=sendData("diskinfo.svctime.$dskName",  $dskSvcTime[$i]/$intSecs);
        $diskDetString.=sendData("diskinfo.util.$dskName",     $dskUtil[$i]/$intSecs);
      }
    }
  }

  my $nfsString='';
  if ($lexSubsys=~/f/)
  {
    if ($nfsSFlag)
    {
      $nfsString.=sendData("nfsinfo.Sread",  $nfsSReadsTot/$intSecs);
      $nfsString.=sendData("nfsinfo.Swrite", $nfsSWritesTot/$intSecs);
      $nfsString.=sendData("nfsinfo.Smeta",  $nfsSMetaTot/$intSecs);
      $nfsString.=sendData("nfsinfo.Scommit",$nfsSCommitTot/$intSecs);
    }
    if ($nfsCFlag)
    {
      $nfsString.=sendData("nfsinfo.Cread",  $nfsCReadsTot/$intSecs);
      $nfsString.=sendData("nfsinfo.Cwrite", $nfsCWritesTot/$intSecs);
      $nfsString.=sendData("nfsinfo.Cmeta",  $nfsCMetaTot/$intSecs);
      $nfsString.=sendData("nfsinfo.Ccommit",$nfsCCommitTot/$intSecs);
    }
  }

  my $inodeString='';
  if ($lexSubsys=~/i/)
  {
    $inodeString.=sendData("inodeinfo.dentrynum", $dentryNum, 1);
    $inodeString.=sendData("inodeinfo.dentryunused", $dentryUnused, 1);
    $inodeString.=sendData("inodeinfo.filesalloc", $filesAlloc, 1);
    $inodeString.=sendData("inodeinfo.filesmax", $filesMax, 1);
    $inodeString.=sendData("inodeinfo.inodeused", $inodeUsed, 1);
  }

  # No lustre details, at least not for now...
  my $lusSumString='';
  if ($lexSubsys=~/l/)
  {
    if ($CltFlag)
    {
      $lusSumString.=sendData("lusclt.reads",    $lustreCltReadTot/$intSecs);
      $lusSumString.=sendData("lusclt.readkbs",  $lustreCltReadKBTot/$intSecs);
      $lusSumString.=sendData("lusclt.writes",   $lustreCltWriteTot/$intSecs);
      $lusSumString.=sendData("lusclt.writekbs", $lustreCltWriteKBTot/$intSecs);
      $lusSumString.=sendData("lusclt.numfs",    $NumLustreFS, 1);
    }

    if ($MdsFlag)
    {
      my $getattrPlus=$lustreMdsGetattr+$lustreMdsGetattrLock+$lustreMdsGetxattr;
      my $setattrPlus=$lustreMdsReintSetattr+$lustreMdsSetxattr;
      my $varName=($cfsVersion lt '1.6.5') ? 'reint' : 'unlink';
      my $varVal= ($cfsVersion lt '1.6.5') ? $lustreMdsReint : $lustreMdsReintUnlink;

      $lusSumString.=sendData('lusmds.gattrP',   $getattrPlus/$intSecs);
      $lusSumString.=sendData('lusmds.sattrP',   $setattrPlus/$intSecs);
      $lusSumString.=sendData('lusmds.sync',     $lustreMdsSync/$intSecs);
      $lusSumString.=sendData("lusmds.$varName", $varVal/$intSecs);
    }

    if ($OstFlag)
    {
      $lusSumString.=sendData("lusost.reads",    $lustreReadOpsTot/$intSecs);
      $lusSumString.=sendData("lusost.readkbs",  $lustreReadKBytesTot/$intSecs);
      $lusSumString.=sendData("lusost.writes",   $lustreWriteOpsTot/$intSecs);
      $lusSumString.=sendData("lusost.writekbs", $lustreWriteKBytesTot/$intSecs);
    }
  }

  my ($memString, $memDetString)=('','');
  if ($lexSubsys=~/m/i)
  {
    if ($lexSubsys=~/m/)
    {
      $memString.=sendData("meminfo.tot", $memTot, 1);
      $memString.=sendData("meminfo.used", $memUsed, 1);
      $memString.=sendData("meminfo.free", $memFree, 1);
      $memString.=sendData("meminfo.shared", $memShared, 1);
      $memString.=sendData("meminfo.buf", $memBuf, 1);
      $memString.=sendData("meminfo.cached", $memCached, 1);
      $memString.=sendData("meminfo.slab", $memSlab, 1);
      $memString.=sendData("meminfo.map", $memMap, 1);
      $memString.=sendData("meminfo.anon", $memAnon, 1);
      $memString.=sendData("meminfo.dirty", $memDirty, 1);
      $memString.=sendData("meminfo.locked", $memLocked, 1);
      $memString.=sendData("meminfo.inactive", $memInact, 1);
      $memString.=sendData("meminfo.hugetot", $memHugeTot, 1);
      $memString.=sendData("meminfo.hugefree", $memHugeFree, 1);
      $memString.=sendData("meminfo.hugersvd", $memHugeRsvd, 1);
      $memString.=sendData("meminfo.sunreclaim", $memSUnreclaim, 1);
      $memString.=sendData("swapinfo.total", $swapTotal, 1);
      $memString.=sendData("swapinfo.free", $swapFree, 1);
      $memString.=sendData("swapinfo.used", $swapUsed, 1);
      $memString.=sendData("swapinfo.in", $swapin/$intSecs);
      $memString.=sendData("swapinfo.out", $swapout/$intSecs);
      $memString.=sendData("pageinfo.fault", $pagefault/$intSecs);
      $memString.=sendData("pageinfo.majfault", $pagemajfault/$intSecs);
      $memString.=sendData("pageinfo.in", $pagein/$intSecs);
      $memString.=sendData("pageinfo.out", $pageout/$intSecs);
    }

    if ($lexSubsys=~/M/)
    {
      for (my $i=0; $i<$CpuNodes; $i++)
      {
        foreach my $field ('used', 'free', 'slab', 'map', 'anon', 'lock', 'act', 'inact')
        {
          $memDetString.=sendData("numainfo.$field.$i", $numaMem[$i]->{$field}, 1);
        }
      }
    }
  }

  my ($netSumString,$netDetString)=('','');
  if ($lexSubsys=~/n/i)
  {
    if ($lexSubsys=~/n/)
    {
      $netSumString.=sendData("nettotals.kbin",   $netRxKBTot/$intSecs);
      $netSumString.=sendData("nettotals.pktin",  $netRxPktTot/$intSecs);
      $netSumString.=sendData("nettotals.kbout",  $netTxKBTot/$intSecs);
      $netSumString.=sendData("nettotals.pktout", $netTxPktTot/$intSecs);
    }

    if ($lexSubsys=~/N/)
    {
      for ($i=0; $i<@netOrder; $i++)
      {
        $netName=$netOrder[$i];
        next    if !defined($netSeen[$i]);
        next    if ($netFiltKeep eq '' && $netName=~/$netFiltIgnore/) || ($netFiltKeep ne '' && $netName!~/$netFiltKeep/);
        next    if $netName=~/lo|sit/;

        $netDetString.=sendData("netinfo.kbin.$netName",   $netRxKB[$i]/$intSecs);
        $netDetString.=sendData("netinfo.pktin.$netName",  $netRxPkt[$i]/$intSecs);
        $netDetString.=sendData("netinfo.kbout.$netName",  $netTxKB[$i]/$intSecs);
        $netDetString.=sendData("netinfo.pktout.$netName", $netTxPkt[$i]/$intSecs);
      }
    }
  }

  my $sockString='';
  if ($lexSubsys=~/s/)
  {
    $sockString.=sendData("sockinfo.used", $sockUsed, 1);
    $sockString.=sendData("sockinfo.tcp", $sockTcp, 1);
    $sockString.=sendData("sockinfo.orphan", $sockOrphan, 1);
    $sockString.=sendData("sockinfo.tw", $sockTw, 1);
    $sockString.=sendData("sockinfo.alloc", $sockAlloc, 1);
    $sockString.=sendData("sockinfo.mem", $sockMem, 1);
    $sockString.=sendData("sockinfo.udp", $sockUdp, 1);
    $sockString.=sendData("sockinfo.raw", $sockRaw, 1);
    $sockString.=sendData("sockinfo.frag", $sockFrag, 1);
    $sockString.=sendData("sockinfo.fragm", $sockFragM, 1);
  }

  my $tcpString='';
  if ($lexSubsys=~/t/)
  {
    $tcpString.=sendData("tcpinfo.iperrs",   $ipErrors/$intSecs)       if $tcpFilt=~/i/;
    $tcpString.=sendData("tcpinfo.tcperrs",  $tcpErrors/$intSecs)      if $tcpFilt=~/t/;
    $tcpString.=sendData("tcpinfo.udperrs",  $udpErrors/$intSecs)      if $tcpFilt=~/u/;
    $tcpString.=sendData("tcpinfo.icmperrs", $icmpErrors/$intSecs)     if $tcpFilt=~/c/;
    $tcpString.=sendData("tcpinfo.tcpxerrs", $tcpExErrors/$intSecs)    if $tcpFilt=~/T/;
  }

  my $intString='';
  if ($lexSubsys=~/x/i)
  {
    if ($NumXRails)
    {
      $kbInT=  $elanRxKBTot;
      $pktInT= $elanRxTot;
      $kbOutT= $elanTxKBTot;
      $pktOutT=$elanTxTot;
    }

    if ($NumHCAs)
    {
      $kbInT=  $ibRxKBTot;
      $pktInT= $ibRxTot;
      $kbOutT= $ibTxKBTot;
      $pktOutT=$ibTxTot;
    }
   
    $intString.=sendData("iconnect.kbin",   $kbInT/$intSecs);
    $intString.=sendData("iconnect.pktin",  $pktInT/$intSecs);
    $intString.=sendData("iconnect.kbout",  $kbOutT/$intSecs);
    $intString.=sendData("iconnect.pktout", $pktOutT/$intSecs);
  }

  my $envString='';
  if ($lexSubsys=~/E/i)
  {
    foreach $key (sort keys %$ipmiData)
    {
      for (my $i=0; $i<scalar(@{$ipmiData->{$key}}); $i++)
      {
        my $name=$ipmiData->{$key}->[$i]->{name};
        my $inst=($key!~/power/ && $ipmiData->{$key}->[$i]->{inst} ne '-1') ? $ipmiData->{$key}->[$i]->{inst} : '';
        $envString.=sendData("env.$name$inst", $ipmiData->{$key}->[$i]->{value}, 1, '%s');
      }
    }
  }

  # if any imported data, it may want to include lexpr output AND we do a little more work to
  # separate the summary from the detail. also, in case any variables are gauges and we're doing
  # totals we'll need to know that too.
  my (@nameS, @valS, @nameD, @valD, @gaugeS, @gaugeD);
  my ($impSumString, $impDetString)=('','');
  for (my $i=0; $i<$impNumMods; $i++) { &{$impPrintExport[$i]}('l', \@nameS, \@valS, \@nameD, \@valD, \@gaugeS, \@gaugeD); }
  foreach (my $i=0; $i<scalar(@nameS); $i++) { $impSumString.=sendData($nameS[$i], $valS[$i], $gaugeS[$i]); }
  foreach (my $i=0; $i<scalar(@nameD); $i++) { $impDetString.=sendData($nameD[$i], $valD[$i], $gaugeD[$i]); }
  $lexSumFlag=1    if $impSumString ne '';   # in case not already set

  $lexprExtString='';
  &$lexExtBase(\$lexprExtString)    if $lexExtName ne '';

  # min/max/tot now updated, but there may be nothing to actally print yet
  return    if !$lexOutputFlag;

  #     B u i l d    O u t p u t    S t r i n g

  my $debTime='';
  if ($lexDebug & 4)
  {
    my $seconds=(split(/\./, $lastSecs[$rawPFlag]))[0];
    my ($sec, $min, $hour)=(localtime($seconds))[0..2];
    $debTime=sprintf(" %02d:%02d:%02d", $hour, $min, $sec);
  }

  my $lexprRec='';
  $lexprRec.="sample.time $lastSecs[$rawPFlag]$debTime\n"    if $lexSumFlag;
  $lexprRec.="$cpuSumString$diskSumString$nfsString$inodeString$memString$netSumString";
  $lexprRec.="$lusSumString$sockString$tcpString$intString$envString$impSumString";
  $lexprRec.=$lexprExtString;

  $lexprRec.="sample.time $lastSecs[$rawPFlag]$debTime\n"   if !$lexSumFlag;
  $lexprRec.="$cpuDetString$diskDetString$memDetString$netDetString$impDetString";

  # Either send data over socket or print to terminal OR write to
  # a file, but not both!
  if ($sockFlag || $lexFilename eq '')
  {
    printText($lexprRec, 1);    # include EOL marker at end
  }
  elsif ($lexFilename ne '')
  {
    open  EXP, ">$lexFilename" or logmsg("F", "Couldn't create '$lexFilename'");
    print EXP  $lexprRec;
    close EXP;
  }
  $lexSamples=0;
}

# this code tightly synchronized with gexpr and graphite
sub sendData
{
  my $name=  shift;
  my $value= shift;
  my $gauge= shift;
  my $format=shift;
  #print "Name: $name  VAL: $value\n";

  # These are only undefined the very first time
  if (!defined($lexTTL{$name}))
  {
    $lexTTL{$name}=$lexTTL;
    $lexDataLast{$name}=-1;
  }

  # As a minor optimization, only do this when dealing with min/max/avg/tot values
  if ($lexFlags)
  {
    # And while this should be done in init(), we really don't know how may indexes
    # there are until our first pass through...
    if ($lexSamples==1)
    {
      $lexDataMin{$name}=$lexOneTB;
      $lexDataMax{$name}=0;
      $lexDataTot{$name}=0;
    }

    $lexDataMin{$name}=$value    if $lexMinFlag && $value<$lexDataMin{$name};
    $lexDataMax{$name}=$value    if $lexMaxFlag && $value>$lexDataMax{$name};
    $lexDataTot{$name}+=$value   if $lexAvgFlag;

    # totals are a little different.  In the case of rates, we need to multiply by the collectl
    # interval to get the interval total, but for gauges we're really only doing averages
    $lexDataTot{$name}+=(!$gauge) ? $value*$lexColInt : $value    if $lexTotFlag;
  }
  return('')    if !$lexOutputFlag;

  #    A c t u a l    S e n d    H a p p e n s    H e r e

  # If doing min/max/avg, reset $value
  if ($lexFlags)
  {
    $value=$lexDataMin{$name}                    if $lexMinFlag;
    $value=$lexDataMax{$name}                    if $lexMaxFlag;
    $value=$lexDataTot{$name}                    if $lexTotFlag;
    $value=$lexDataTot{$name}/$lexSamples        if $lexAvgFlag || defined($gauge);    # gauges are reported as averages
  }

  # Always send send data if not CO mode, but if so only send when it has
  # indeed changed OR TTL about to expire
  my $valSentFlag=0;
  my $returnString='';
  if (!$lexCOFlag || $value!=$lexDataLast{$name} || $lexTTL{$name}==1)
  {
    $valSentFlag=1;
    $format='%d'    if !defined($format);
    $value+=.5      if $format=~/d/;
    $returnString=sprintf("%s $format\n", $name, $value)    unless $lexDebug & 8;
    $lexDataLast{$name}=$value;
  }

  # A fair chunk of work, but worth it
  if ($lexDebug & 3)
  {
    my ($intSeconds, $intUsecs);
    if ($hiResFlag)
    {
      # we have to fully qualify name because or 'require' vs 'use'
      ($intSeconds, $intUsecs)=Time::HiRes::gettimeofday();
    }
    else
    {
      $intSeconds=time;
      $intUsecs=0;
    }

    $intUsecs=sprintf("%06d", $intUsecs);
    my ($sec, $min, $hour)=localtime($intSeconds);
    my $timestamp=sprintf("%02d:%02d:%02d.%s", $hour, $min, $sec, substr($intUsecs, 0, 3));
    printf "$timestamp Name: %-20s Val: %8d TTL: %d %s\n",
		$name, $value, $lexTTL{$name}, ($valSentFlag) ? 'sent' : ''
			if $lexDebug & 1 || $valSentFlag;
  }

  # TTL only applies when in 'CO' mode, noting we already made expiration
  # decision above when we saw counter of 1
  if ($lexCOFlag)
  {
    $lexTTL{$name}--          if !$valSentFlag;
    $lexTTL{$name}=$lexTTL    if $valSentFlag || $lexTTL{$name}==0;
  }
  return($returnString);
}

sub help
{
  my $text=<<EOF;

usage: --export=lexpr[,options]
  where each option is separated by a comma, noting some take args themselves
    align       align output to whole minute boundary
    co          only reports changes since last reported value
    d=mask      debugging options, see beginning of graphite.ph for details
    f=file      snapshot filename
    h           print this help and exit
    i=seconds   reporting interval, must be multiple of collect's -i
    s=subsys    only report subsystems, must be a subset of collectl's -s
    ttl=num     if data hasn't changed for this many intervals, report it
                only used with 'co', def=5
    x=file      do a 'require' on specified file to extend lexpr functionality
    avg         report average of values since last report    
    max         report maximum value since last report
    min         report minimal value since last report
    tot		report total values (as makes sense) since last report
EOF

  print $text;
  exit(0);
}

1;
