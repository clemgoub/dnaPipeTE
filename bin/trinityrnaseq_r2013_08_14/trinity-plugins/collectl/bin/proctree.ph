# copyright, 2008 Hewlett-Packard Development Company, LP
#
# collectl may be copied only under the terms of either the Artistic License
# or the GNU General Public License, which may be found in the source kit

# Call with --export "proctreee[,sort[,options]]

# todo
# - allow skiptype and/or 'z' in either --top or proctree in playback mode

# doc notes
#  in playback mode you can specify skip field in either procopts OR export
#  can specify 'z' with --procopts OR --export

my $procCount;
my %level;
my %procPrinted;
my $eol=sprintf("%c[K", 27);

my $expSort;
my $expOpts;
my $debug=0;
my $depth=5;
my $aggregateFlag=1;
my $kFlag=0;
my $threadsFlag=1;
my $skipFlag=0;
my $cmd1Width=999;
my $pidSelect;

my $mult=1;
my $ioSkip=0;
my %procChild;
sub proctreeInit
{
  $expSkip=shift;
  $expOpts=shift;

  error("you cannot do socket I/O with proctree")       if $sockFlag;
  error("you cannot use --procfilt with 'proctree'")    if $procFilt ne '';
  error("do not specify any options with --export when using --top interactively")
	    if $numTop && $playback eq '' && defined($expSkip);

  # Too bad we didn't call initRecord() yet...
  if ($playback eq '')
  {
    $processIOFlag=(-e '/proc/self/io')  ? 1 : 0;
    error("You cannot use --top and IO options with this kernel")  if $topType=~/kb|sys$|cncl/ && !$processIOFlag;
  }

  # we're allowing options in either of the two fields!
  if (defined($expSkip))
  {
    if ($expSkip=~/^[adkzZ0-9]+$/)
    {
      $expOpts=$expSkip    if $expSkip=~/^[adkzZ0-9]+$/;
      $expSkip=($topType ne '') ? $topType : 'time';
    }
    if ($expOpts=~/d/)
    {
      error("option 'd' must be followed by a number")    if $expOpts!~s/d(\d+)//;
      $depth=$1;
    }
    if ($expOpts=~/Z/)
    {
      error("option 'Z' only applies to I/O KB fields")    if $expSkip!~/kb/;
      error("option 'Z' must be followed by a number")     if $expOpts!~s/Z(\d+)//;
      $ioSkip=$1;
    }

    error("do not specify skip field in both --top and --export")    if $expSkip ne '' && $topType ne '' && $expSkip ne $topType && $topType ne 'time';
    error("Invalid 'proctree' option string: '$expOpts'")    if (defined($expOpts) && $expOpts ne '' && $expOpts!~/^([akz]+)$/);
    $aggregateFlag=1    if $expOpts=~/a/;
    $kFlag=1            if $expOpts=~/k/;
    $skipFlag=1         if $expOpts=~/z/ || $ioSkip;
  }

  # Always use default skip type from --top if there, otherwise it's whatever
  # follows 'proctree,' OR 'time'.  Then fake this out to look like --top.
  # noting we're now taking our sort field from $expSkip and NOT --top
  $expSkip=($numTop) ? $topType : 'time'   if !defined($expSkip);
  $topType=$expSkip                        if !$numTop;

  # note that in --top $expSkip has already been verified because it comes from $topType
  error("Invalid process sorting field '$expSkip', try --showtopopt")    if !defined($TopProcTypes{$expSkip});

  # any other options follow 'proctree,sort,' noting 'sort' NOT optional
  $expOpts=''                        if !defined($expOpts);
  $subsys='Z'                        if $userSubsys eq '';
  $skipFlag=1                        if $procOpts=~/z/ || $numTop;

  error("you can only specify 'Z' with -s")             if $userSubsys ne '' && $subsys ne 'Z';

  $aggregateFlag=0    if $expOpts=~/A/;
  $threadsFlag=0      if $expOpts=~/T/;

  $quietFlag=1;    # skip warning line threaded processes exiting...

  $proctreeSelect=new IO::Select(STDIN)    if !defined($proctreeSelect);
  `stty -echo`;
}

sub proctree
{
  my $pidPrinted;
  undef %procPrinted;
  undef @stack;

  return    if !$interval2Print;
  commandCheck();
  print $clscr    if $numTop && $playback eq '';

  # Build a hash that points to all a process' kids
  undef %procChild;
  foreach my $pid (keys %procIndexes)
  {
    my $i=$procIndexes{$pid};
    my $ppid=(defined($procTgid[$i]) && $procTgid[$i]!=$procPid[$i]) ? $procTgid[$i] : $procPpid[$i];

    my $pidZ=sprintf("%05d", $pid);
    my $ppidZ=sprintf("%05d", $ppid);
    my $kids=(!defined($procChild{$ppidZ})) ? 0 : scalar(@{$procChild{$ppidZ}});
    $procChild{$ppidZ}->[$kids]=$pidZ;
    #printf "PID: $pidZ  I: $i PPID: $ppidZ KIDS: $kids\n";
  }

  if ($debug & 1)
  {
    # Look for orphans.  Probably only useful for debugging and then not even sure...
    foreach my $pid (keys %procIndexes)
    {
      my $i=$procIndexes{$pid};
      my $ppid=(defined($procTgid[$i]) && $procTgid[$i]!=$procPid[$i]) ? $procTgid[$i] : $procPpid[$i];
      my $ppidZ=sprintf("%05d", $ppid);
      print "*** Pid $pid is an orphan ***\n"    if !defined($procChild{$ppidZ});
    }

    foreach my $ppid (sort keys %procChild)
    {
      printf "Parent: %5d  Kids: %5d  PIDS:", $ppid, scalar(@{$procChild{$ppid}});
      foreach my $pid (@{$procChild{$ppid}})
      {
        printf "  %d", $pid;
      }
      print "\n";
    }
  }

  printTreeHeader();
  aggregate('00000')    if $aggregateFlag;

  $procCount=0;
  $level{'00000'}=-1;
  push @stack, '00000';

  my $i2=$interval2Secs;
  while (scalar(@stack))
  {
    my $ppidZ=pop(@stack);
    my $i=$procIndexes{$ppidZ*1};
    #print "POPPED: $ppidZ  I: $i  LEVEL: $level{$ppidZ}\n";

    my $level=$level{$ppidZ}+1;
    foreach my $pidZ (@{$procChild{$ppidZ}})
    {
      $level{$pidZ}=$level;
      push @stack, $pidZ;
    }
    next    if $level==0 || $level>$depth;
    next    if !$threadsFlag && $procThread[$i];

    if ($skipFlag)
    {
      next    if $topType eq 'syst' && $procSTime[$i]==0;
      next    if $topType eq 'usrt' && $procUTime[$i]==0;
      next    if $topType eq 'time' && $procSTime[$i]+$procUTime[$i]==0;

      if ($procOpts!~/f/)
      {
        next    if $topType eq 'majf' && $procMajFlt[$i]==0;
        next    if $topType eq 'minf' && $procMinFlt[$i]==0;
        next    if $topType eq 'flt'  && $procMajFlt[$i]+$procMinFlt[$i]==0;
      }
      else
      {
        next    if $topType eq 'majf' && $procMajFltTot[$i]==0;
        next    if $topType eq 'minf' && $procMinFltTot[$i]==0;
        next    if $topType eq 'flt'  && $procMajFltTot[$i]+$procMinFltTot[$i]==0;
      }

      # I/O KBs are special...
      next    if $topType eq 'rkb'   && $procRKB[$i]/$i2<=$ioSkip;
      next    if $topType eq 'wkb'   && $procWKB[$i]/$i2<=$ioSkip;
      next    if $topType eq 'iokb'  && ($procRKB[$i]+$procWKB[$i])/$i2<=$ioSkip;
      next    if $topType eq 'rkbc'  && $procRKBC[$i]/$i2<=$ioSkip;
      next    if $topType eq 'wkbc'  && $procWKBC[$i]/$i2<=$ioSkip;
      next    if $topType eq 'iokbc' && ($procRKBC[$i]+$procWKBC[$i])/$i2<=$ioSkip;
      next    if $topType eq 'ioall' && ($procRKB[$i]+$procWKB[$i]+$procRKBC[$i]+$procWKBC[$i])/$i2<=$ioSkip;
      next    if $topType eq 'rsys'  && $procRSys[$i]==0;
      next    if $topType eq 'wsys'  && $procWSys[$i]==0;
      next    if $topType eq 'iosys' && $procRSys[$i]+$procWSys[$i]==0;
    }
    next    if defined($pidSelect) && ($ppidZ ne $pidSelect) && !$pidPrinted;
    $pidPrinted=1;

    my $parent=defined($procTgid[$i]) && $procTgid[$i]!=$procPid[$i] ? $procTgid[$i] : $procPpid[$i];
    my $pIndex=$procIndexes{$parent};
    printPid($pIndex, $parent)    if $procThread[$i] && !defined($procPrinted{$parent});
    printPid($i, $ppidZ*1);

    last    if $numTop && $procCount>=$numTop;
  }
  $clscr=$home;
  print $clr;
}

sub printTreeHeader
{
  my $tempTime='';

  $tempTime= " ".(split(/\s+/,localtime($lastInt2Secs)))[3];
  $tempTime.=sprintf(".%03d", $usecs)    if $options=~/m/;
  my $line="Process Tree$tempTime ";
  $line.=sprintf("[skip when '$expSkip'<=%d%s is '%s' ", $ioSkip, $ioSkip ? 'KB' : '', $skipFlag ? 'on' : 'off');
  $line.=sprintf("aggr: '%s' x1024: '%s' depth $depth",
	           $aggregateFlag ? 'on' : 'off', $kFlag ? 'on' : 'off');
  $line.=sprintf(" threads: %s", $threadsFlag ? 'on' : 'off')    if $procOpts=~/t/;
  $line.="]$eol\n";

  $line.=$eol        if $playback eq '' && $numTop;
  printText("\n")    if !$homeFlag;
  printText($line);

  my $filler=' 'x$depth;
  if ($procOpts!~/[im]/)
  {
    $tempHdr= "#  PID$filler  PPID User     PR S   VSZ   RSS CP  SysT  UsrT Pct  AccuTime ";
    $tempHdr.=" RKB  WKB "    if $processIOFlag;
    $tempHdr.="MajF MinF Command\n";
  }
  elsif ($procOpts=~/i/)
  {
    $tempHdr= "#  PID$filler  PPID User     S  SysT  UsrT  AccuTime   RKB   WKB  RKBC  WKBC  RSys  WSys  Cncl Command\n";
  }
  elsif ($procOpts=~/m/)
  {
    $tempHdr= "#  PID$filler  PPID User     S VmSize  VmLck  VmRSS VmData  VmStk  VmExe  VmLib MajF MinF Command\n";
  }
  printText($tempHdr);
}

sub printPid
{
  my $i=   shift;
  my $ppid=shift;

  my $ppidZ=sprintf("%05d", $ppid);
  my $pad=($level{$ppidZ});
  my $padL=' 'x$pad;
  my $padR=' 'x($depth-$pad);

  my $parent=defined($procTgid[$i]) && $procTgid[$i]!=$procPid[$i] ? $procTgid[$i] : $procPpid[$i];
  my $line=sprintf("$padL%05d%s$padR %5d ", $ppid, $procThread[$i] ? '+' : ' ', $parent);

  # Handle --procopts f
  if ($procOpts=~/f/)
  {
    $majFlt=$procMajFltTot[$i];
    $minFlt=$procMinFltTot[$i];
  }
  else
  {
    $majFlt=$procMajFlt[$i]/$interval2Secs;
    $minFlt=$procMinFlt[$i]/$interval2Secs;
  }

  my ($cmd0, $cmd1)=(defined($procCmd[$i])) ? split(/\s+/,$procCmd[$i],2) : ($procName[$i],'');
  $cmd0=basename($cmd0)    if $procOpts=~/r/ && $cmd0=~/^\//;
  $cmd1=''                 if $procOpts!~/w/ || !defined($cmd1);
  $cmd1=~s/\s+$//          if $procOpts=~/w/;
  $cmd1=substr($cmd1, 0, $cmd1Width);

  if ($procOpts!~/[im]/)
  {
    # Note we only started fetching Tgid in V3.0.0
    $line.=sprintf("%-8s %2s %1s %5s %5s %2d %s %s %s %s ",
                substr($procUser[$i],0,8), $procPri[$i],
                $procState[$i],
                defined($procVmSize[$i]) ? cvt($procVmSize[$i],4,1,1) : 0,
                defined($procVmRSS[$i])  ? cvt($procVmRSS[$i],4,1,1)  : 0,
                $procCPU[$i],
                cvtT1($procSTime[$i]), cvtT1($procUTime[$i]),
                cvtP($procSTime[$i]+$procUTime[$i]),
                cvtT2($procSTimeTot[$i]+$procUTimeTot[$i]));
    $line.=sprintf("%4s %4s ",
                cvt($procRKB[$i]*$mult/$interval2Secs,4,0,1),
                cvt($procWKB[$i]*$mult/$interval2Secs,4,0,1))     if $processIOFlag;
    $line.=sprintf("%4s %4s %s %s",
                cvt($majFlt), cvt($minFlt), "$padL$cmd0", $cmd1);
  }
  elsif ($procOpts=~/i/)
  {
    $line.=sprintf("%-8s %1s %s %s %s ",
                substr($procUser[$i],0,8),
                $procState[$i],
                cvtT1($procSTime[$i]), cvtT1($procUTime[$i]),
                cvtT2($procSTimeTot[$i]+$procUTimeTot[$i]));
    $line.=sprintf("%5s %5s %5s %5s %5s %5s %5s %s %s",
                cvt($procRKB[$i]*$mult/$interval2Secs,5,0,1),
                cvt($procWKB[$i]*$mult/$interval2Secs,5,0,1),
                cvt($procRKBC[$i]*$mult/$interval2Secs,5,0,1),
                cvt($procWKBC[$i]*$mult/$interval2Secs,5,0,1),
                cvt($procRSys[$i]/$interval2Secs,5,0,1),
                cvt($procWSys[$i]/$interval2Secs,5,0,1),
                cvt($procCKB[$i]*$mult/$interval2Secs,5,0,1),
                "$padL$cmd0", $cmd1);
  }
  elsif ($procOpts=~/m/)
  {
    $line.=sprintf("%-8s %1s %6s %6s %6s %6s %6s %6s %6s %4s %4s %s %s",
                $procUser[$i], $procState[$i],
                defined($procVmSize[$i]) ? cvt($procVmSize[$i],6,1,1) : 0,
                defined($procVmLck[$i])  ? cvt($procVmLck[$i],6,1,1)  : 0,
                defined($procVmRSS[$i])  ? cvt($procVmRSS[$i],6,1,1)  : 0,
                defined($procVmData[$i]) ? cvt($procVmData[$i],6,1,1) : 0,
                defined($procVmStk[$i])  ? cvt($procVmStk[$i],6,1,1)  : 0,
                defined($procVmExe[$i])  ? cvt($procVmExe[$i],6,1,1)  : 0,
                defined($procVmLib[$i])  ? cvt($procVmLib[$i],6,1,1)  : 0,
                cvt($majFlt), cvt($minFlt), "$padL$cmd0", $cmd1);
  }
  $line.=$eol    if $playback eq '' && $numTop;

  $procCount++;
  $line.="\n"    if $playback ne '' || !$numTop || $procCount<$numTop;
  printText($line);
  $procPrinted{$ppid}=1;    # string leading 0s
}

sub aggregate
{
  my $pidZ=shift;

  my $kidArray=$procChild{$pidZ};
  foreach my $kidZ (@$kidArray)
  {
    my $kidI=aggregate($kidZ);
  }

  if ($pidZ ne '00000')
  {
    my $i=$procIndexes{$pidZ*1};

    # Aggregate everything that makes sense...
    foreach my $kidZ (@$kidArray)
    {
      $kidI=$procIndexes{$kidZ*1};

      $procSTime[$i]+=   $procSTime[$kidI];
      $procUTime[$i]+=   $procUTime[$kidI];
      $procSTimeTot[$i]+=$procSTimeTot[$kidI];
      $procUTimeTot[$i]+=$procUTimeTot[$kidI];

      $procMinFlt[$i]+=   $procMinFlt[$kidI];
      $procMajFlt[$i]+=   $procMajFlt[$kidI];
      $procMinFltTot[$i]+=$procMinFltTot[$kidI];
      $procMajFltTot[$i]+=$procMajFltTot[$kidI];

      if ($processIOFlag)
      {
        $procRKB[$i]+= $procRKB[$kidI];
        $procWKB[$i]+= $procWKB[$kidI];
        $procRKBC[$i]+=$procRKBC[$kidI];
        $procWKBC[$i]+=$procWKBC[$kidI];
        $procRSys[$i]+=$procRSys[$kidI];
        $procWSys[$i]+=$procWSys[$kidI];
        $procCKB[$i]+= $procCKB[$kidI];
      }

      # If one not defined for this process, none defined and same for parent
      $procVmSize[$kidI]=$procVmLck[$kidI]=$procVmRSS[$kidI]=$procVmData[$kidI]=
      $procVmStk[$kidI]=$procVmExe[$kidI]=$procVmLib[$kidI]=0
		if !defined($procVmSize[$kidI]);
      $procVmSize[$i]=$procVmLck[$i]=$procVmRSS[$i]=$procVmData[$i]=
      $procVmStk[$i]=$procVmExe[$i]=$procVmLib[$i]=0
		if !defined($procVmSize[$i]);

      $procVmSize[$i]+=$procVmSize[$kidI];
      $procVmLck[$i]+= $procVmLck[$kidI];
      $procVmRSS[$i]+= $procVmRSS[$kidI];
      $procVmData[$i]+=$procVmData[$kidI];
      $procVmStk[$i]+= $procVmStk[$kidI];
      $procVmExe[$i]+= $procVmExe[$kidI];
      $procVmLib[$i]+= $procVmLib[$kidI];
    }
  }
}

sub commandCheck
{
  # see if user entered a command
  my @ready=$proctreeSelect->can_read(0);
  if (scalar(@ready))
  {
    my $command=<STDIN>;
    chomp $command;

    if ($command=~/^(\d+)/)
    {
      $pidSelect=sprintf("%05d", $1);
      $pidPrinted=0;
    }
    elsif ($command=~/^a/)
    {
      $aggregateFlag=($aggregateFlag+1) % 2;
    }
    elsif ($command=~/^d(\d+)/)
    {
      $depth=$1;
    }
    elsif ($command=~/^([imp])/)
    {
      my $format=$1;
      $procOpts=~s/[imp]//;
      $procOpts.=$format;
    }
    elsif ($command=~/^h/ || $command eq '')
    {
      helpMenu();
    }
    elsif ($command=~/^k/)
    {
      $kFlag=($kFlag+1) % 2;
      $mult=($kFlag) ? 1024 : 1;
    }
    elsif ($command=~/^s(\S+)/)
    {
      my $skip=$1;
      if (defined($TopProcTypes{$skip}))
      {
        $topType=$skip;
      }
      else
      {
        treeError("Invalid process sorting field '$sort'");
      }
    }
    elsif ($command=~/^t/)
    {
      if ($procOpts=~/t/)
      {
        $threadsFlag=($threadsFlag + 1) %2;
      }
      else
      {
        treeError("threads must be selected with --procopts to use 't' command")
      }
    }
    elsif ($command=~/^w(\d+)/)
    {
      $cmd1Width=$1;
    }
    elsif ($command=~/^z/)
    {
      my $saveOpts=$procOpts;
      $skipFlag=($skipFlag+1) % 2;
      $procOpts.=($saveOpts!~/z/) ? 'z' : '';
    }
    elsif ($command=~/^Z(\d+)/)
    {
      if ($processIOFlag)
      {
        $ioSkip=$1;
        $expSkip=$ioSkip;   # for reporting name in header
      }
      else
      {
        treeError("'Z' only applies to kernels that track process I/O")
      }
    }
    else
    {
      helpMenu("Invalid command: $command");
    }
  }
}

sub treeError
{
  print "$clscr$clr";
  print "$_[0]\n"    if defined($_[0]);
  print "Press RETURN to go back to display mode...\n";
  <STDIN>;
}

sub helpMenu
{
  print "$clscr$clr";
  print "$_[0]\n"    if defined($_[0]);
  print "Enter a command and RETURN while in display mode:\n";
  print "  pid    only display this pid and its children\n";
  print "  a      toggle aggregation between 'on' and 'off'\n";
  print "  dxx    change display hierarchy depth to xx\n";
  print "  i      change display format to 'I/O'\n";
  print "  k      toggle multiplication of I/O numbers by 1024 between 'on' and 'off'\n";
  print "  m      change display format to 'memory'\n";
  print "  p      change display format to 'process'\n";
  print "  h      show this menu\n";
  print "  stype  where 'type' is a valid sorting type (see --showtopopts)\n";
  print "         entries with 0s in those field(s) will be skipped\n"; 
  print "  wxx    max width for display of command arguments\n";
  print "  z      toggle 'skip' logic between 'on' and 'off'\n";
  print "  Zxx    when skipping, only keep entries with I/O fields > xxKB\n";
  print "Press RETURN to go back to display mode...\n";
  <STDIN>;
}
1;
