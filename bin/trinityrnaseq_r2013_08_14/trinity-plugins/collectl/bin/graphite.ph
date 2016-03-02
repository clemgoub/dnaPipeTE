# copyright, 2003-20012 Hewlett-Packard Development Company, LP

#  debug
#    1 - print Var, Units and Values
#    2 - only print sent 'changed' Var/Units/Vales
#    4 - not used
#    8 - do not open/use socket (typically used with other flags)
#   16 - print socket open/close info

our $graphiteInterval;

my $graphiteTimeout=5;
my $graphiteCounter=0;
my $graphiteSocketFailMax=5;    # report socket open fails every 100 intervals
my $graphiteIntTimeLast=0;      # tracks start of new interval
my $graphiteOneTB=1024*1024*1024*1024;
my $graphitePost='';            # insert AFTER hostname in message to carbon (don't forget '.' if you want one)
my ($graphiteSubsys, $graphiteBefore, $graphiteEscape, $graphiteRandomize);
my ($graphiteDebug, $graphiteColInt, $graphiteCOFlag, $graphiteSendCount);
my ($graphiteTTL, %graphiteTTL, %graphiteDataMin, %graphiteDataMax, %graphiteDataTot, %graphiteDataLast);
my ($graphiteMyHost, $graphiteSocket, $graphiteSockHost, $graphiteSockPort, $graphiteSocketFailCount);
my ($graphiteAlign, $graphiteFqdnFlag, $graphiteMinFlag, $graphiteMaxFlag, $graphiteAvgFlag, $graphiteTotFlag, $graphiteFlags)=(0,0,0,0,0,0,0);
my $graphiteOutputFlag=1;

sub graphiteInit
{
  my $hostport=shift;
  help()    if $hostport eq 'h';

  error("host[:port] must be specified as first parameter")    if !defined($hostport);
  error('--showcolheader not supported by graphite')           if $showColFlag;

  # Just like vmstat
  error("-f requires either --rawtoo or -P")     if $filename ne '' && !$rawtooFlag && !$plotFlag;
  error("-P or --rawtoo require -f")             if $filename eq '' && ($rawtooFlag || $plotFlag);

  # parameter defaults
  $hostport.=":2003"    if $hostport!~/:/;
  $graphiteDebug=$graphiteCOFlag=0;
  $graphiteInterval='';
  $graphiteSubsys=$subsys;
  $graphiteTTL=5;
  $graphiteBefore='';
  $graphiteEscape='';
  $graphiteRandomize='';

  foreach my $option (@_)
  {
    my ($name, $value)=split(/=/, $option);
    error("invalid graphite option '$name'")    if $name!~/^[bdefhiprs]?$|^align|^co$|^ttl$|^min$|^max$|^avg$|^tot$/;
    $graphiteAlignFlag=1        if $name eq 'align';
    $graphiteBefore=$value      if $name eq 'b';
    $graphiteCOFlag=1           if $name eq 'co';
    $graphiteDebug=$value       if $name eq 'd';
    $graphiteEscape=$value      if $name eq 'e';
    $graphiteInterval=$value    if $name eq 'i';
    $graphitePost=$value        if $name eq 'p';
    $graphiteRandomize=$value   if $name eq 'r';
    $graphiteSubsys=$value      if $name eq 's';
    $graphiteTTL=$value         if $name eq 'ttl';
    $graphiteFqdnFlag=1		if $name eq 'f';
    $graphiteMinFlag=1          if $name eq 'min';
    $graphiteMaxFlag=1          if $name eq 'max';
    $graphiteAvgFlag=1          if $name eq 'avg';
    $graphiteTotFlag=1          if $name eq 'tot';

    help()                      if $name eq 'h';
  }

  error("graphite does not support standard collectl socket I/O via -A")   if $graphiteSockFlag;
  ($graphiteSockHost, $graphiteSockPort)=split(/:/, $hostport);
  error("the port number must be specified")    if !defined($graphiteSockPort) || $graphiteSockPort eq '';

  # s= disables ALL subsys, only makes sense with imports
  error("graphite subsys options '$graphiteSubsys' not a proper subset of '$subsys'")
        if $subsys ne '' && $graphiteSubsys ne '' && $graphiteSubsys!~/^[$subsys]+$/;

  $graphiteFlags=$graphiteMinFlag+$graphiteMaxFlag+$graphiteAvgFlag+$graphiteTotFlag;
  error("only 1 of 'min', 'max', 'avg' or 'tot' with 'graphite'")    if $graphiteFlags>1;

  # If we ever run with a ':' in the interval, we need to be sure we're only looking at the main one.
  $graphiteColInt=(split(/:/, $interval))[0];
  $graphiteInterval=$graphiteColInt    if $graphiteInterval eq '';

  # convert to the number of samples we want to send
  $graphiteSendCount=int($graphiteInterval/$graphiteColInt);
  error("graphite interval '$graphiteInterval' is not a multiple of '$graphiteColInt' seconds")
	if $graphiteColInt*$graphiteSendCount != $graphiteInterval;
  error("'min', 'max', 'avg' & 'tot' require graphite 'i' that is > collectl's -i")
        if $graphiteFlags && $graphiteSendCount==1;

  if ($graphiteAlignFlag)
  {
    my $div1=int(60/$graphiteColInt);
    my $div2=int($graphiteColInt/60);
    error("'align' requires collectl interval be a factor or multiple of 60 seconds")
      		 if ($graphiteColInt<=60 && $div1*$graphiteColInt!=60) || ($graphiteColInt>60 && $div2*60!=$graphiteColInt);
    error("'align' only makes sense when multiple samples/interval")    if $graphiteInterval<=$graphiteColInt;
    error("'lexpr,align' requires -D or --align")                       if !$graphiteAlignFlag && !$daemonFlag;
  }

  error('randomize options requires a value')    if !defined($graphiteRandomize);
  if ($graphiteRandomize ne '')
  {
    error("randomization require hires time module")                  if !$hiResFlag;
    error("randomization requires interval of at least 2 seconds")    if $graphiteInterval<2;
    error("randomization value must be less than or equal to '" . ($graphiteInterval-1) . "' seconds")
          if $graphiteRandomize > $graphiteInterval-1;
  }

  # Since graphite DOES write over a socket but does not use -A, make sure the default
  # behavior for -f logs matches that of -A
  $rawtooFlag=1    if $filename ne '' && !$plotFlag;

  $graphiteMyHost=(!$graphiteFqdnFlag) ? `hostname` : `hostname -f`;
  chomp $graphiteMyHost;
  $graphiteMyHost =~ s/\./$graphiteEscape/g    if $graphiteEscape ne '';

  #    O p e n    S o c k e t

  $SIG{"PIPE"}=\&graphiteSigPipe;    # socket comm errors

  # set fail count such that if first open fails, we'll report an error
  $graphiteSocketFailCount=$graphiteSocketFailMax-1;
  openTcpSocket(1);
}

# NOTE - this routine is almost an identical copy from gexpr.
# Being lazy while making it easier to keep the 2 in sync, I left in the
# second parameter in the sendData() calls which are ignored in the
# modified version of sendData() itself, which prepends a hostname to the
# variable name and add a timestamp to the socket call.  In fact, I almost
# just hacked up gexpr to make it deal with both ganglia and graphite.
sub graphite
{
  # if socket not even open and the first try of this interval, try again
  # NOTE - we're making sure socket is open every interval whether we're
  # reporting data or not...
  openTcpSocket()    if !defined($graphiteSocket) && $graphiteIntTimeLast!=time;
  $graphiteIntTimeLast=time;
  return             if !defined($graphiteSocket) && !($graphiteDebug & 8);    # still not open?  get out!

  # if not time to print and we're not doing min/max/avg/tot, there's nothing to do.
  # BUT always make sure time aligns to top of minute based on i=
  $graphiteCounter++;
  $graphiteOutputFlag=(($graphiteCounter % $graphiteSendCount) == 0) ? 1 : 0         if !$graphiteAlignFlag;
  $graphiteOutputFlag=(!(int($lastSecs[$rawPFlag]) % $graphiteInterval)) ? 1 : 0     if  $graphiteAlignFlag;
  return    if (!$graphiteOutputFlag && $graphiteFlags==0);

  # random sleep when r= option
  Time::HiRes::usleep(rand($graphiteRandomize)*1000000)    if $graphiteRandomize ne '';

  if ($graphiteSubsys=~/c/)
  {
    # CPU utilization is a % and we don't want to report fractions
    my $i=$NumCpus;

    sendData('cputotals.user', 'percent', $userP[$i]);
    sendData('cputotals.nice', 'percent', $niceP[$i]);
    sendData('cputotals.sys',  'percent', $sysP[$i]);
    sendData('cputotals.wait', 'percent', $waitP[$i]);
    sendData('cputotals.idle', 'percent', $idleP[$i]);
    sendData('cputotals.irq',  'percent', $irqP[$i]);
    sendData('cputotals.soft', 'percent', $softP[$i]);
    sendData('cputotals.steal','percent', $stealP[$i]);

    sendData('ctxint.ctx',  'switches/sec', $ctxt/$intSecs);
    sendData('ctxint.int',  'intrpts/sec',  $intrpt/$intSecs);
    sendData('ctxint.proc', 'pcreates/sec', $proc/$intSecs);
    sendData('ctxint.runq', 'runqSize',     $loadQue);

    # these are the ONLY fraction, noting they will print to 2 decimal places
    sendData('cpuload.avg1',   'loadAvg1',  $loadAvg1,  2);
    sendData('cpuload.avg5',   'loadAvg5',  $loadAvg5,  2);
    sendData('cpuload.avg15',  'loadAvg15', $loadAvg15, 2);
  }

  if ($graphiteSubsys=~/C/)
  {
    for (my $i=0; $i<$NumCpus; $i++)
    {
      sendData("cpuinfo.user.cpu$i",  'percent', $userP[$i]);
      sendData("cpuinfo.nice.cpu$i",  'percent', $niceP[$i]);
      sendData("cpuinfo.sys.cpu$i",   'percent', $sysP[$i]);
      sendData("cpuinfo.wait.cpu$i",  'percent', $waitP[$i]);
      sendData("cpuinfo.irq.cpu$i",   'percent', $irqP[$i]);
      sendData("cpuinfo.soft.cpu$i",  'percent', $softP[$i]);
      sendData("cpuinfo.steal.cpu$i", 'percent', $stealP[$i]);
      sendData("cpuinfo.idle.cpu$i",  'percent', $idleP[$i]);
      sendData("cpuinfo.intrpt.cpu$i",'percent', $intrptTot[$i]);
    }
  }

  if ($graphiteSubsys=~/d/)
  {
    sendData('disktotals.reads',    'reads/sec',    $dskReadTot/$intSecs);
    sendData('disktotals.readkbs',  'readkbs/sec',  $dskReadKBTot/$intSecs);
    sendData('disktotals.writes',   'writes/sec',   $dskWriteTot/$intSecs);
    sendData('disktotals.writekbs', 'writekbs/sec', $dskWriteKBTot/$intSecs);
  }

  if ($graphiteSubsys=~/D/)
  {
    for (my $i=0; $i<@dskOrder; $i++)
    {
      # preserve display order but skip any disks not seen this interval
      $dskName=$dskOrder[$i];
      next    if !defined($dskSeen[$i]);
      next    if ($dskFiltKeep eq '' && $dskName=~/$dskFiltIgnore/) || ($dskFiltKeep ne '' && $dskName!~/$dskFiltKeep/);

      sendData("diskinfo.reads.$dskName",    'reads/sec',    $dskRead[$i]/$intSecs);
      sendData("diskinfo.readkbs.$dskName",  'readkbs/sec',  $dskReadKB[$i]/$intSecs);
      sendData("diskinfo.writes.$dskName",   'writes/sec',   $dskWrite[$i]/$intSecs);
      sendData("diskinfo.writekbs.$dskName", 'writekbs/sec', $dskWriteKB[$i]/$intSecs);
    }
  }

  if ($graphiteSubsys=~/f/)
  {
    if ($nfsSFlag)
    {
      sendData('nfsinfo.SRead',   'SvrReads/sec',  $nfsSReadsTot/$intSecs);
      sendData('nfsinfo.SWrite',  'SvrWrites/sec', $nfsSWritesTot/$intSecs);
      sendData('nfsinfo.Smeta',   'SvrMeta/sec',   $nfsSMetaTot/$intSecs);
      sendData('nfsinfo.Scommit', 'SvrCommt/sec' , $nfsSCommitTot/$intSecs);
    }
    if ($nfsCFlag)
    {
      sendData('nfsinfo.CRead',   'CltReads/sec',  $nfsCReadsTot/$intSecs);
      sendData('nfsinfo.CWrite',  'CltWrites/sec', $nfsCWritesTot/$intSecs);
      sendData('nfsinfo.Cmeta',   'CltMeta/sec',   $nfsCMetaTot/$intSecs);
      sendData('nfsinfo.Ccommit', 'CltCommt/sec' , $nfsCCommitTot/$intSecs);
    }
  }

  if ($graphiteSubsys=~/i/)
  {
    sendData('inodeinfo.dentnum',    'dentrynum',    $dentryNum);
    sendData('inodeinfo.dentunused', 'dentryunused', $dentryUnused);
    sendData('inodeinfo.fhandalloc', 'filesalloc',   $filesAlloc);
    sendData('inodeinfo.fhandmpct',  'filesmax',     $filesMax);
    sendData('inodeinfo.inodenum',   'inodeused',    $inodeUsed);
  }

  if ($graphiteSubsys=~/l/)
  {
    if ($CltFlag)
    {
      sendData('lusclt.reads',    'reads/sec',    $lustreCltReadTot/$intSecs);
      sendData('lusclt.readkbs',  'readkbs/sec',  $lustreCltReadKBTot/$intSecs);
      sendData('lusclt.writes',   'writes/sec',   $lustreCltWriteTot/$intSecs);
      sendData('lusclt.writekbs', 'writekbs/sec', $lustreCltWriteKBTot/$intSecs);
      sendData('lusclt.numfs',    'filesystems',  $NumLustreFS);
    }

    if ($MdsFlag)
    {
      my $getattrPlus=$lustreMdsGetattr+$lustreMdsGetattrLock+$lustreMdsGetxattr;
      my $setattrPlus=$lustreMdsReintSetattr+$lustreMdsSetxattr;
      my $varName=($cfsVersion lt '1.6.5') ? 'reint' : 'unlink';
      my $varVal= ($cfsVersion lt '1.6.5') ? $lustreMdsReint : $lustreMdsReintUnlink;

      sendData('lusmds.gattrP',    'gattrP/sec',   $getattrPlus/$intSecs);
      sendData('lusmds.sattrP',    'sattrP/sec',   $setattrPlus/$intSecs);
      sendData('lusmds.sync',      'sync/sec',     $lustreMdsSync/$intSecs);
      sendData("lusmds.$varName",  "$varName/sec", $varVal/$intSecs);
    }

    if ($OstFlag)
    {
      sendData('lusost.reads',    'reads/sec',    $lustreReadOpsTot/$intSecs);
      sendData('lusost.readkbs',  'readkbs/sec',  $lustreReadKBytesTot/$intSecs);
      sendData('lusost.writes',   'writes/sec',   $lustreWriteOpsTot/$intSecs);
      sendData('lusost.writekbs', 'writekbs/sec', $lustreWriteKBytesTot/$intSecs);
    }
  }

  if ($graphiteSubsys=~/L/)
  {
    if ($CltFlag)
    {
      # Either report details by filesystem OR OST
      if ($lustOpts!~/O/)
      {
        for (my $i=0; $i<$NumLustreFS; $i++)
        {
          sendData("lusost.reads.$lustreCltFS[$i]",    'reads/sec',    $lustreCltRead[$i]/$intSecs);
	  sendData("lusost.readkbs.$lustreCltFS[$i]",  'readkbs/sec',  $lustreCltReadKB[$i]/$intSecs);
          sendData("lusost.writes.$lustreCltFS[$i]",   'writes/sec',   $lustreCltWrite[$i]/$intSecs);
          sendData("lusost.writekbs.$lustreCltFS[$i]", 'writekbs/sec', $lustreCltWriteKB[$i]/$intSecs);
        }
      }
      else
      {
        for (my $i=0; $i<$NumLustreCltOsts; $i++)
        {
          sendData("lusost.reads.$lustreCltOsts[$i]",    'reads/sec',    $lustreCltLunRead[$i]/$intSecs);
          sendData("lusost.readkbs.$lustreCltOsts[$i]",  'readkbs/sec',  $lustreCltLunReadKB[$i]/$intSecs);
          sendData("lusost.writes.$lustreCltOsts[$i]",   'writes/sec',   $lustreCltLunWrite[$i]/$intSecs);
          sendData("lusost.writekbs.$lustreCltOsts[$i]", 'writekbs/sec', $lustreCltLunWriteKB[$i]/$intSecs);
        }
      }
    }

    if ($OstFlag)
    {
      for ($i=0; $i<$NumOst; $i++)
      {
        sendData("lusost.reads.$lustreOsts[$i]",    'reads/sec',    $lustreReadOps[$i]/$intSecs);
        sendData("lusost.readkbs.$lustreOsts[$i]",  'readkbs/sec',  $lustreReadKBytes[$i]/$intSecs);
        sendData("lusost.writes.$lustreOsts[$i]",   'writes/sec',   $lustreWriteOps[$i]/$intSecs);
        sendData("lusost.writekbs.$lustreOsts[$i]", 'writekbs/sec', $lustreWriteKBytes[$i]/$intSecs);
      }
    }
  }

  if ($graphiteSubsys=~/m/)
  {
    sendData('meminfo.tot',       'kb',         $memTot);
    sendData('meminfo.free',      'kb',         $memFree);
    sendData('meminfo.shared',    'kb',         $memShared);
    sendData('meminfo.buf',       'kb',         $memBuf);
    sendData('meminfo.cached',    'kb',         $memCached);
    sendData('meminfo.used',      'kb',         $memUsed);
    sendData('meminfo.slab',      'kb',         $memSlab);
    sendData('meminfo.map',       'kb',         $memMap);
    sendData('meminfo.hugetot',   'kb',         $memHugeTot);
    sendData('meminfo.hugefree',  'kb',         $memHugeFree);
    sendData('meminfo.hugersvd',  'kb',         $memHugeRsvd);

    sendData('swapinfo.total',    'kb',         $swapTotal);
    sendData('swapinfo.free',     'kb',         $swapFree);
    sendData('swapinfo.used',     'kb',         $swapUsed);
    sendData('swapinfo.in',       'swaps/sec',  $swapin/$intSecs);
    sendData('swapinfo.out',      'swaps/sec',  $swapout/$intSecs);

    sendData('pageinfo.fault',    'faults/sec', $pagefault/$intSecs);
    sendData('pageinfo.majfault', 'majflt/sec', $pagemajfault/$intSecs);
    sendData('pageinfo.in',       'pages/sec',  $pagein/$intSecs);
    sendData('pageinfo.out',      'pages/sec',  $pageout/$intSecs);
  }

  if ($graphiteSubsys=~/M/)
  {
    for (my $i=0; $i<$CpuNodes; $i++)
    {
      foreach my $field ('used', 'free', 'slab', 'map', 'anon', 'lock', 'act', 'inact')
      {
        sendData("numainfo.$field.$i", 'kb', $numaMem[$i]->{$field});
      }
    }
  }

  if ($graphiteSubsys=~/n/)
  {
    sendData('nettotals.kbin',   'kb/sec', $netRxKBTot/$intSecs);
    sendData('nettotals.pktin',  'kb/sec', $netRxPktTot/$intSecs);
    sendData('nettotals.kbout',  'kb/sec', $netTxKBTot/$intSecs);
    sendData('nettotals.pktout', 'kb/sec', $netTxPktTot/$intSecs);
  }

  if ($graphiteSubsys=~/N/)
  {
    for ($i=0; $i<@netOrder; $i++)
    {
      $netName=$netOrder[$i];
      next    if !defined($netSeen[$i]);
      next    if ($netFiltKeep eq '' && $netName=~/$netFiltIgnore/) || ($netFiltKeep ne '' && $netName!~/$netFiltKeep/);
      next    if $netName=~/lo|sit/;

      sendData("nettotals.kbin.$netName",   'kb/sec', $netRxKB[$i]/$intSecs);
      sendData("nettotals.pktin.$netName",  'kb/sec', $netRxPkt[$i]/$intSecs);
      sendData("nettotals.kbout.$netName",  'kb/sec', $netTxKB[$i]/$intSecs);
      sendData("nettotals.pktout.$netName", 'kb/sec', $netTxPkt[$i]/$intSecs);
    }
  }

  if ($graphiteSubsys=~/s/)
  {
    sendData("sockinfo.used",  'sockets', $sockUsed);
    sendData("sockinfo.tcp",   'sockets', $sockTcp);
    sendData("sockinfo.orphan",'sockets', $sockOrphan);
    sendData("sockinfo.tw",    'sockets', $sockTw);
    sendData("sockinfo.alloc", 'sockets', $sockAlloc);
    sendData("sockinfo.mem",   'sockets', $sockMem);
    sendData("sockinfo.udp",   'sockets', $sockUdp);
    sendData("sockinfo.raw",   'sockets', $sockRaw);
    sendData("sockinfo.frag",  'sockets', $sockFrag);
    sendData("sockinfo.fragm", 'sockets', $sockFragM);
  }

  if ($graphiteSubsys=~/t/)
  {

    sendData("tcpinfo.iperrs",   'num/sec', $ipErrors/$intSecs)       if $tcpFilt=~/i/;
    sendData("tcpinfo.tcperrs",  'num/sec', $tcpErrors/$intSecs)      if $tcpFilt=~/t/;
    sendData("tcpinfo.udperrs",  'num/sec', $udpErrors/$intSecs)      if $tcpFilt=~/u/;
    sendData("tcpinfo.icmperrs", 'num/sec', $icmpErrors/$intSecs)     if $tcpFilt=~/c/;
    sendData("tcpinfo.tcpxerrs", 'num/sec', $tcpExErrors/$intSecs)    if $tcpFilt=~/T/;
  }

  if ($graphiteSubsys=~/x/i)
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
   
    sendData("iconnect.kbin",   'kb/sec',  $kbInT/$intSecs);
    sendData("iconnect.pktin",  'pkt/sec', $pktInT/$intSecs);
    sendData("iconnect.kbout",  'kb/sec',  $kbOutT/$intSecs);
    sendData("iconnect.pktout", 'pkt/sec', $pktOutT/$intSecs);
  }

  if ($graphiteSubsys=~/E/i)
  {
    foreach $key (sort keys %$ipmiData)
    {
      for (my $i=0; $i<scalar(@{$ipmiData->{$key}}); $i++)
      {
        my $name=$ipmiData->{$key}->[$i]->{name};
        my $inst=($key!~/power/ && $ipmiData->{$key}->[$i]->{inst} ne '-1') ? $ipmiData->{$key}->[$i]->{inst} : '';

        sendData("env.$name$inst", $name,  $ipmiData->{$key}->[$i]->{value}, '%s');
      }
    }
  }

  my (@names, @units, @vals);
  for (my $i=0; $i<$impNumMods; $i++) { &{$impPrintExport[$i]}('g', \@names, \@units, \@vals); }
  foreach (my $i=0; $i<scalar(@names); $i++)
  {
    sendData($names[$i], $units[$i], $vals[$i]);
  }
  $graphiteCounter=0    if $graphiteOutputFlag;
}

# this code tightly synchronized with gexpr and lexpr
sub sendData
{
  my $name= shift;
  my $units=shift;
  my $value=shift;
  my $numpl=shift;    # number of decimal places 

  # These are only undefined the very first time
  if (!defined($graphiteTTL{$name}))
  {
    $graphiteTTL{$name}=$lexTTL;
    $graphiteDataLast{$name}=-1;
  }

  # if graphite went away in the middle of an interval there's no point continuing.
  # we're try to reopen it next pass through here
  return    if !defined($graphiteSocket) && !($graphiteDebug & 8);

  $value=int($value)    if !defined($numpl);

  # As a minor optimization, only do this when dealing with min/max/avg/tot values
  if ($graphiteFlags)
  {
    # And while this should be done in init(), we really don't know how may indexes
    # there are until our first pass through...
    if ($graphiteCounter==1)
    {
      $graphiteDataMin{$name}=$graphiteOneTB;
      $graphiteDataMax{$name}=0;
      $graphiteDataTot{$name}=0;
    }

    $graphiteDataMin{$name}=$value    if $graphiteMinFlag && $value<$graphiteDataMin{$name};
    $graphiteDataMax{$name}=$value    if $graphiteMaxFlag && $value>$graphiteDataMax{$name};
    $graphiteDataTot{$name}+=$value   if $graphiteAvgFlag || $graphiteTotFlag;
  }

  return('')    if !$graphiteOutputFlag;

  #    A c t u a l    S e n d    H a p p e n s    H e r e

  # If doing min/max/avg, reset $value
  if ($graphiteFlags)
  {
    $value=$graphiteDataMin{$name}                        if $graphiteMinFlag;
    $value=$graphiteDataMax{$name}                        if $graphiteMaxFlag;
    $value=$graphiteDataTot{$name}                        if $graphiteTotFlag;
    $value=($graphiteDataTot{$name}/$graphiteCounter)      if $graphiteAvgFlag;
  }

  # Always send send data if not CO mode, but if so only send when it has
  # indeed changed OR TTL about to expire
  my $valSentFlag=0;
  if (!$graphiteCOFlag || $value!=$graphiteDataLast{$name} || $graphiteTTL{$name}==1)
  {
    $valSentFlag=1;
    my $valString=(!defined($numpl)) ? sprintf('%d', $value) : sprintf("%.${numpl}f", $value);
    my $message=sprintf("$graphiteBefore$graphiteMyHost$graphitePost.$name $valString %d\n", $graphiteIntTimeLast);
    print $message    if $graphiteDebug & 1;
    if (!($graphiteDebug & 8))
    {
      my $bytes=syswrite($graphiteSocket, $message, length($message), 0);
    }
    $graphiteDataLast{$name}=$value;
  }

  # TTL only applies when in 'CO' mode
  if ($graphiteCOFlag)
  {
    $graphiteTTL{$name}--               if !$valSentFlag;
    $graphiteTTL{$name}=$graphiteTTL    if $valSentFlag || $graphiteTTL{$name}==0;
  }
}

sub openTcpSocket
{
  return   if $graphiteDebug & 8;    # don't open socket

  print "Opening Socket on $graphiteSockHost:$graphiteSockPort\n"    if $graphiteDebug & 16;
  $graphiteSocket=new IO::Socket::INET(
        PeerAddr => $graphiteSockHost,
        PeerPort => $graphiteSockPort,
        Proto    => 'tcp',
        Timeout  => $graphiteTimeout);

  if (!defined($graphiteSocket))
  {
    if (++$graphiteSocketFailCount==$graphiteSocketFailMax)
    {
      logmsg('E', "Could not create socket to $graphiteSockHost:$graphiteSockPort.  Reason: $!");
      $graphiteSocketFailCount=0;
    }
  }
  else
  {
    # we're printing to the term with d=16 because 'I' messages don't go there.
    my $message="Socket opened to graphite/carbon on $graphiteSockHost:$graphiteSockPort";
    print "$message\n"    if $graphiteDebug & 16;
    logmsg('I', $message);
    $graphiteSocketFailCount=0;
  }
}

# This catches the socket failure.  Only problem is it doesn't happen until we try write
# and as a result when we return the write fails with an undef on the socket variable.
# Not really a big deal...
sub graphiteSigPipe
{ 
  undef $graphiteSocket;
}

sub help
{
  my $text=<<EOF;

usage: --export=graphite,host[:port][,options]
  where each option is separated by a comma, noting some take args themselves
    align       align output to whole minute boundary
    b=string    preface each variable name with string
    co          only reports changes since last reported value
    d=mask      debugging options, see beginning of graphite.ph for details
    e=escape    escape character to replace '.' with in hostname
    f           use fqdn instead of simple hostname for statistics naming
    h           print this help and exit
    i=seconds   reporting interval, must be multiple of collect's -i
    p=text      insert this text right after hostname, including '.' if you want one
    r=seconds   randomized wait of up to 'r' seconds before submitting to graphite
    s=subsys    only report subsystems, must be a subset of collectl's -s
    ttl=num     if data hasn't changed for this many intervals, report it
                only used with 'co', def=5
    avg         report average of values since last report
    max         report maximum value since last report
    min         report minimal value since last report
    tot		report total values (as makes sense) since last report
EOF

  print $text;
  exit(0);
}

1;
