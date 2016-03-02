# copyright, 2003-20012 Hewlett-Packard Development Company, LP
#
# collectl may be copied only under the terms of either the Artistic License
# or the GNU General Public License, which may be found in the source kit

# local flags not needed/used by mainline.  probably others in this category
my $printTermFirst=0;

# shared with main collectl
our %netSpeeds;

# these are only init'd when in 'record' mode, one of the reasons being that
# many of these variables may be different on the system on which the data
# is being played back on
sub initRecord
{
  print "initRecord() - Subsys: $subsys\n"    if $debug & 1;
  initDay();

  $rawPFlag=0;    # always 0 when no files involved

  # In some case, we need to know if we're root.
  $rootFlag=`whoami`;
  $rootFlag=($rootFlag=~/root/) ? 1 : 0;

  # be sure to remove domain portion if present.  also note we keep the hostname in
  # two formats, one in it's unaltered form (at least needed by lustre directory 
  # parsing) as well as all lc because it displays nicer.
  $Host=`hostname`;
  chomp $Host;
  $Host=(split(/\./, $Host))[0];
  $HostLC=lc($Host);

  # when was system booted?
  $uptime=(split(/\s+/, `cat /proc/uptime`))[0];
  $boottime=time-$uptime;

  $Distro=cat('/etc/redhat-release')    if -e '/etc/redhat-release';
  chomp $Distro;

  if (-e '/etc/redhat-release')
  {
    $Distro=cat('/etc/redhat-release');
    chomp $Distro;
  }
  elsif (-e '/etc/SuSE-release')
  {
    my @temp=split(/\n/, cat('/etc/SuSE-release', 1));
    $temp[2]=~/(\d+$)/;         # patchlevel
    $Distro="$temp[0] SP$1";    # append onto release string as SP
  }
  elsif (-e '/etc/debian_version')
  {
    # Both debian and ubuntu have 2 files
    $Distro='debian '.cat('/etc/debian_version');
    chomp $Distro;

    # append distro to base release, if there
    if (-e '/etc/lsb-release')
    {
      my $temp=cat('/etc/lsb-release',1);
      $temp=~/DESCRIPTION=(.*)/;
      $temp=$1;
      $temp=~s/\"//g;
      $Distro.=", $temp";
    }
  }

  # For -sD calculations, we need the HZ of the system
  $HZ=POSIX::sysconf(&POSIX::_SC_CLK_TCK);
  $PageSize=POSIX::sysconf(_SC_PAGESIZE);

  # If we have process IO everyone must.  This was added in 2.6.23,
  # but then only if someone builds the kernel with it enabled, though
  # that, will probably change with future kernels.
  $processIOFlag=(-e '/proc/self/io')  ? 1 : 0;
  $slabinfoFlag= (-e '/proc/slabinfo') ? 1 : 0;
  $slubinfoFlag= (-e '/sys/slab')      ? 1 : 0;

  $processCtxFlag=($subsys=~/Z/ && `$Grep ctxt /proc/self/status` ne '') ? 1 : 0;

  # just because slab structures there, are they readable?  A chunk of extra work, but worth it.
  if ($subsys=~/y/i && $slabinfoFlag || $slubinfoFlag)
  {
    $message='';
    $message='/proc/slabinfo'    if $slabinfoFlag && !(eval {`cat /proc/slabinfo 2>/dev/null` or die});
    $message='/sys/slab'         if $slubinfoFlag && !(eval {`cat /proc/slubinfo 2>/dev/null` or die});
    if ($message ne '')
    {
      my $whoami=`whoami`;
      chomp $whoami;
      disableSubsys('y', "/proc/slabinfo is not readable by $whoami");
      $interval=~s/(^\d*):\d+/$1:/    if $subsys!~/z/i;    # remove int2 if not needed or we'll get error
    }
  }

  # Get number of ACTIVE CPUs from /proc/stat and in case we're not running on a
  # kernel that will set the CPU states (or let us change them), enable CPU flag
  $NumCpus=`$Grep cpu /proc/stat | wc -l`;
  $NumCpus=~/(\d+)/;
  $NumCpus=$1-1;
  for (my $i=0; $i<$NumCpus; $i++)
  {
    $cpuEnabled[$i]=1;
  }
  $cpusEnabled=$NumCpus;

  # Now get the total number the system sees, and if different, reset the
  # number as well as a flag for the header
  $cpuDisabledFlag=0;
  $cpuDisabledMsg='';
  $cpusDisabled=0;
  if (-e '/sys')
  {
    my $totalCpus=`ls /sys/devices/system/cpu/|$Grep '^cpu[0-9]'|wc -l`;
    chomp $totalCpus;
    if ($totalCpus!=$NumCpus)
    {
      $NumCpus=$totalCpus;
      $cpusDisabled++;    # for use in header
      $cpuDisabledFlag=1;

      # we really only have to worry about lower level details of WHO is disabled when
      # doing cpu or interrupt stats.  Furthermore, if doing cpu, the dynamic processing
      # will figure out who's disabled but its too much overhead for interrupts alone so
      # we'll do that here one time only.  This may have to be do dynamically if a problem. 
      if ($subsys=~/j/i && $subsys!~/c/i)
      {
        # CPU0 always online AND no 'online' entry exists!
        $cpusEnabled=1;
        $cpuEnabled[0]=1;

        for (my $i=1; $i<$NumCpus; $i++)
        {
          my $online=`cat /sys/devices/system/cpu/cpu$i/online`;
          chomp $online;

          $cpuEnabled[$i]=$online;
          $cpusEnabled++    if $online;
          $intrptTot[$i]=0;
        }
      }
    }
  }

  $temp=`$Grep vendor_id /proc/cpuinfo`;
  $CpuVendor=($temp=~/: (.*)/) ? $1 : '???';
  $temp=`$Grep siblings /proc/cpuinfo`;
  $CpuSiblings=($temp=~/: (\d+)/) ? $1 : 1;  # if not there assume 1
  $temp=`$Grep "cpu cores" /proc/cpuinfo`;
  $CpuCores=($temp=~/: (\d+)/) ? $1 : 1;     # if not there assume 1
  $temp=`$Grep "cpu MHz" /proc/cpuinfo`;
  $CpuMHz=($temp=~/: (.*)/) ? $1 : '???';
  $Hyper=($CpuSiblings/$CpuCores==2) ? "[HYPER]" : "";
  if (-e "/sys/devices/system/node")
  {
    $CpuNodes=`ls /sys/devices/system/node |$Grep '^node[0-9]'|wc -l`;
  }
  else
  {
    # if doesn't exist set nodes to 1 and disable '-sM' if specified
    $CpuNodes=1;
    disableSubsys('M', "/sys/devices/system/node doesn't exist", 1)    if $subsys=~/M/;
  }
  chomp $CpuNodes;

  # /proc read speed test, note various reasons to skip it
  # These tests should be updated as we learn more about other distros
  $ProcReadTest='no'    if $NumCpus<32 || $Kernel lt '2.6.32';
  $ProcReadTest='no'    if $Distro=~/Red Hat.*release (\S+)/ && $1>=6.2;
  $ProcReadTest='no'    if $Distro=~/SUSE.*Server (\d+).*SP(\d+)/ && ($1!=11 || $2>=1);

  if ($ProcReadTest=~/yes/i)
  {
    $procReadTested=1;    # can call this routine twice!

    my $strace=`strace -c cat /proc/stat 2>&1`;
    $strace=~/^\s*\S+\s+(\S+).*read$/m;
    my $speed=$1;
    print "ProcReadSpeed: $speed\n"    if $debug * 1;
    if ($speed>0.01)
    {
      # may be going to a lot of effort here but I want to make sure these messages aren't
      # recorded as errors and you don't have to include -m to see them as they are pretty
      # important to the users to know about this.
      my $line1="Slow /proc/stat read speed of $speed seconds";
      my $line2="Consider a kernel patch/upgrade. See http://collectl.sourceforge.net/FAQ for more";
      my $line3="Change 'ProcReadSpeed' in /etc/collectl.conf to suppress this message in the future";
      if ($DaemonFlag)
      {
        logmsg('W', $line1);
        logmsg('I', $line2);
        logmsg('I', $line3);
      }
      else
      {
        print "$line1\n$line2\n$line3\n";
      }
    }
  }

  $Memory=`$Grep MemTotal /proc/meminfo`;
  $Memory=(split(/\s+/, $Memory, 2))[1];
  chomp $Memory;
  $Swap=`$Grep SwapTotal /proc/meminfo`;
  $Swap=(split(/\s+/, $Swap, 2))[1];
  chomp $Swap;

  #    B u d d y i n f o

  if ($subsys=~/b/i)
  {
    if (!open BUD, '</proc/buddyinfo')
    {
      disableSubsys('b', '/proc/buddyinfo does not exist');
    }
    else
    {
      $NumBud=0;
      while (my $line=<BUD>)
      {
	$NumBud++
      }
      close BUD;
    }
  }

  #    D i s k    C h e c k s

  undef @dskOrder;
  $dskIndexNext=0;
  my @temp=`$Cat /proc/diskstats`;
  foreach my $line (@temp)
  {
    next    if $line!~/$DiskFilter/;

    my @fields=split(/\s+/, $line);

    my $diskName=$fields[3];
    $diskName=remapDiskName($diskName)    if $diskRemapFlag;
    $diskName=~s/cciss\///;
    push @dskOrder, $diskName;
    $disks{$diskName}=$dskIndexNext++;
  }
  $dskSeenLast=$dskIndexNext;
  logmsg("I", "initDisk initialized $dskIndexNext disks")    if $debug & 1;

  #    I n o d e s

  if ($subsys=~/i/)
  {
    $dentryFlag= (-e '/proc/sys/fs/dentry-state') ? 1 : 0;
    $inodeFlag=  (-e '/proc/sys/fs/inode-state')  ? 1 : 0;
    $filenrFlag= (-e '/proc/sys/fs/file-nr')      ? 1 : 0;
    if ($debug & 1)
    {
      print "/proc/sys/fs/dentry-state missing\n"    if !$dentryFlag;
      print "/proc/sys/fs/dentry-state missing\n"    if !$inodeFlag;
      print "/proc/sys/fs/dentry-state missing\n"    if !$filenrFlag;
    }
   }

  #    I n t e r c o n n e c t    C h e c k s

  # Set IB speeds non-conditionally (even if not running IB) and then only for ofed.  
  # Furthermore assume if mulitple IB interfaces they're all the same speed.
  $ibSpeed='??';
  if (-e '/sys/class/infiniband')
  {
    $line=`cat /sys/class/infiniband/*/ports/1/rate 2>&1`;
    if ($line=~/\s*(\d+)\s+(\S)/)
    {
      $ibSpeed=$1;
      $ibSpeed*=1000    if $2 eq 'G';
    }
  }

  # if doing interconnect, the first thing to do is see what interconnect
  # hardware is present via lspci.  Note that from the H/W database, we get
  # the following IDS -Quadrics: 14fc, Myricom: 14c1, Mellanox (IB): 15b3
  # OR 0c06, QLogic (IB): 1077
  # we also have to make sure in the right position of output of lspci command
  # so need to be a little clever
  $NumXRails=$NumHCAs=0;
  $myrinetFlag=$quadricsFlag=$mellanoxFlag=0;
  if ($subsys=~/x/i)
  {
    my $lspciVer=`$Lspci --version`;
    $lspciVer=~/ (\d+\.\d+)/;
    $lspciVer=$1;
    my $lspciVendorField=($lspciVer<2.2) ? 3 : 2;

    # Turns out SuSE put 'Class' string back into V2.4.4 without changing
    # version number in SLES 10.  It also looks like they got it right in
    # SLES 11, but who know what will happen in SLES 12!
    $lspciVendorField=3    if $Distro=~/SUSE.*10/;
    print "lspci -- Version: $lspciVer  Vendor Field: $lspciVendorField\n"
	if $debug & 1;

    $command="$Lspci -n | $Egrep '15b3|0c06|14c1|14fc|1077'";
    print "Command: $command\n"    if $debug & 1;
    @pci=`$command`;
    foreach $temp (@pci)
    {
      # Save the type in case we ever need that level of discrimination.
      ($vendorID, $type)=split(/:/,(split(/\s+/, $temp))[$lspciVendorField]);
      if ($vendorID eq '14c1')
      {
        printf "WARNING: found myrinet card but no collectl support\n";
      }

      if ($vendorID eq '14fc')
      {
	print "Found Quadrics Interconnect\n"    if $debug & 2;
        $quadricsFlag=1;
	elanCheck();
      }

      if ($vendorID=~/15b3|0c06|1077/)
      {
	next    if $type eq '5a46';    # ignore pci bridge
	print "Found Infiniband Interconnect\n"    if $debug & 1;
	$mellanoxFlag=1;
	$HCANames='';
        ibCheck('');
      }
    }

    disableSubsys('x', 'no interconnect hardware/drivers found')
	if $myrinetFlag+$quadricsFlag+$mellanoxFlag==0;

    # User had ability to turn off in case they don't want destructive monitoring
    if ($mellanoxFlag)
    {
      $message='';
      $message="Open Fabric IB Stats disabled in $configFile"    if  -e $SysIB && $PQuery eq '';
      $message="Voltaire IB Stats disabled in $configFile"       if !-e $SysIB && $PCounter eq '';
      if ($message ne '')
      {
        logmsg("W", $message);
        $xFlag=$XFlag=0;
        $subsys=~s/x//ig;
        $mellanoxFlag=0;
      }

      if ($mellanoxFlag)
      {
        # The way forward is clearly OFED
	if (-e $SysIB)
        {
          # This block's job is to make sure perfquery is there
          {
            print "Looking for 'perfquery' and 'ofed_info'\n"    if $debug & 2;
            $PQuery=getOfedPath($PQuery, 'perfquery', 'PQuery');
            if ($PQuery eq '')
            {
              disableSubsys('x', "couldn't find perfquery!");
              $mellanoxFlag=0;
	      last;
            }

            # I hate support questions and this is the place to catch perfquery problems!
            # so, if perfquery IS there, since it generates warnings on stderr in V1.5 and
            # we don't know the version yet, always ignore them
            if ($mellanoxFlag)
            {
              my $message='';
              my $temp=`$PQuery 2>/dev/null`;

              $message="Permission denied"            if $temp=~/Permission denied/;
              $message="Failed to open IB device"     if $temp=~/Failed to open/;
              $message="Required module missing"      if $temp=~/required by/;
              $message="No such file or directory"    if $temp=~/No such file/;
              if ($message ne '')
              {
                disableSubsys('x', "perfquery error: $message!");
                $mellanoxFlag=0;
                $PQuery='';
		last;
              }
            }

            # perfquery IS there and we can execute it w/o error...
            # Can you believe it?  PQuery writes its version output to stderr!
            $temp=`$PQuery -V 2>&1`;
            $temp=~/VERSION: (\d+\.\d+\.\d+)/;
            $PQVersion=$1;
          }

          # perfquery there, but what is ofed's version?
          # NOTE - looks like RedHat is no longer shipping ofed
          if ($PQuery ne '')
	  {
            if (!-e $OfedInfo)
            {
              $OfedInfo=getOfedPath($OfedInfo, 'ofed_info', 'OfedInfo');
              logmsg('W', "Couldn't find 'ofed_info'.  Won't be able to determine OFED version")
	          if $OfedInfo eq '';
            }

            # Unfortunately the ofed_info that ships with voltaire adds 5 extra
            # line at front end so let's look at first 10 lines for version.
            $IBVersion=($OfedInfo ne '' && `$OfedInfo|head -n10`=~/OFED-(.*)/) ? $1 : '???';
	    print "OFED V: $IBVersion PQ V:$PQVersion\n"    if $debug & 2;
	  }
        }
	else
        {
  	  $IBVersion=(`head -n1 $VoltaireStats`=~/ibstat\s+(.*)/) ? $1 : '???';
	  print "Voltaire IB V$IBVersion\n"    if $debug & 2;
        }
      }
    }

    # One last check and this is a doozie!  Because we read IB counters by doing
    # a read/clear everytime, multiple copies of collectl will step on each other.
    # Therefore we can only allow one instance to actually monitor the IB and the
    # first one wins, unless we're trying to start a daemon in which case we let 
    # step on the other [hopefully temporary] instance.  Since there are odd cases
    # where it may not always catch exception, one can override checking in .conf
    if ($IbDupCheckFlag && $mellanoxFlag)
    {
      my $myppid=getppid();
      $command="$Ps axo pid,cmd | $Grep collectl | $Grep -vE 'grep|ssh'";
      foreach my $line (`$command`)
      {
        $line=~s/^\s+//;    # some pids have leading white space
        my ($pid, $procCmd)=split(/ /, $line, 2);
        next    if $pid==$$ || $pid==$myppid;   # check ppid in case started by a script

        # There are just too many ways one can specify the subsystems whether it's
        # overriding the DaemonCommands or SubsysCore in collectl.conf, using an
        # alternate collectl.conf or specifying --subsys instead of -s  and I'm 
        # just not going to go there [for now] as it's complicated enough, hence
        # '$IbDupCheckFlag'

        # If not running as a daemon, '$procCmd' has the command invocation string
        # from the 'ps' above.  If a daemon, we need to pull it out of collectl.cont.
        my $tempDaemonFlag=($procCmd=~/-D/) ? 1 : 0;
        if ($tempDaemonFlag)
        {
          # This is getting even uglier, but if someone chose to duplicate 
          # 'DaemonCommands' and comment one out, we really need to look for
          # the last uncommented one.
          foreach my $cmd (`$Grep 'DaemonCommands =' $configFile`)
          {
	    next    if $cmd=~/^#/;
            $procCmd=$cmd;
          }
        }

	# Now that we have the full command passed to collectl, pull out -s (if any)
        # which may be surrounded by optional white space.
        chomp $procCmd;
	$procSubsys=($procCmd=~/-s\s*(\S+)\s*/) ? $1 : '';

        # The default subsys is different for daemon and interactive use
        # if no -s, we use default and if there, assume we're overriding
        $tempSubsys=($tempDaemonFlag) ? $SubsysDefDaemon : $SubsysDefInt;

        # So now we need to figure out what actual subsystems are in use
        # by that instance in case it was started with either +/- OR
        # a fixed set
        if ($procSubsys=~/^[\+\-]/)
        {
	  # the stolen from main collectl switch validation code noting
          # we don't need to validate the switches since done when
          # daemon started
          if ($procSubsys=~/-(.*)/)
	  {
    	    my $pat=$1;
            $pat=~s/\+.*//;    # if followed by '+' string
            $tempSubsys=~s/[$pat]//g;
          }
	  if ($procSubsys=~/\+(.*)/)
  	  {
	    my $pat=$1;
	    $pat=~s/-.*//;    # if followed by '-' string
	    $tempSubsys.=$pat;
	  }
        }
        elsif ($procSubsys ne '')
        {
          $tempSubsys=$procSubsys;
        }

	# At this point if there IS an instance of collectl running with -sx,
        # we need to disable it here, unless we're a daemon in which case we
        # just log a warning.
        if ($tempSubsys=~/x/i)
        {
	  if (!$daemonFlag)
          {
	    disableSubsys('x', 'another instance already monitoring Infiniband');
          }
          else
          {
            logmsg("W", "another instance is monitoring IB and the stats will be in error until it is stopped");
          }
          last;
        }
      }
    }
  }

  # Let's always get the platform name if dmidecode is there
  if ($Dmidecode ne '')
  {
    $ProductName=($rootFlag) ? `$Dmidecode | grep -m1 'Product Name'` : '';
    $ProductName=~s/\s*Product Name: //;
    chomp $ProductName;
    $ProductName=~s/\s*$//;   # some have trailing whitespace
  }

  #    E n v i r o n m e n t a l    C h e c k s

  if ($subsys=~/E/ && $envTestFile eq '')
  {
    # Note that these tests are in the reverse order since the last value of $message
    # in the one reported AND only if not using a 'test' file for data source.
    my $message='';
    $message="'IpmiCache' not defined or specifies a directory"
                if $IpmiCache eq '' || -d $IpmiCache;
    $message="cannot find /dev/ipmi* (is impi_si loaded?)"
                if !-e '/dev/ipmi0' && !-e '/dev/ipmi/0' && !-e '/dev/ipmidev/0';
    $message="cannot find 'ipmitool' in '$ipmitoolPath'"
                if $Ipmitool eq '';
    $message="you must be 'root' to do environmental monitoring"
		if !$rootFlag;

    if ($message eq '')
    {
      # If specified by --envopts, set -d for ipmitool
      $Ipmitool.=" -d $1"    if $envOpts=~/(\d+)/;

      logmsg('I', "Initialized ipmitool cache file '$IpmiCache'");
      my $command="$Ipmitool sdr dump $IpmiCache";

      # If we can't dump the cache, something is wrong so make sure we pass along
      # error and disable E monitoring.  Ok to create 'exec' below since we'll 
      # never execute it
      $message=`$command 2>&1`;
      if ($message=~/^Dumping/)
      {
        # Create 'exec' option file in save directory as cache, but only for
        # those options that actually return data
        my $cacheDir=dirname($IpmiCache);
        $ipmiExec="$cacheDir/collectl-ipmiexec";
        if (open EXEC, ">$ipmiExec")
        {
	  $message='';    # indicates no errors for test below
          foreach my $type (split(/,/, $IpmiTypes))
          {
            my $command="$Ipmitool -S $IpmiCache sdr type $type";
            next    if `$command` eq '';
            print EXEC "sdr type $type\n";
          }
          close EXEC;
        }
        else
        {
          $message="couldn't create '$ipmiExec'";
        }
      }
    }
    disableSubsys('E', $message)    if $message ne '';
  }

  # find all the networks and when possible include their speeds
  undef @temp;
  $netIndexNext=0;
  $NetWidth=$netOptsW;     # Minimum size
  $null=($debug & 1) ? '' : '2>/dev/null';
  my $interval1=(split(/:/, $interval))[0];

  # but first look up all the network speed in /sys/devices and load them into a hash 
  # for easier access in the loop below
  my $command="find /sys/devices/ 2>&1 | grep net | grep speed";
  open FIND, "$command|" or logmsg('E', "couldn't execute '$command'");
  while (my $line=<FIND>)
  {
    chomp $line;
    my $mode=$line;
    $mode=~s/speed/operstate/;
    $mode=`cat $mode`;
    next    if $mode!~/up|unknown/;

    my $speed=`cat $line 2>&1`;
    chomp $speed;

    $line=~/.*\/(\S+)\/speed/;
    my $netName=$1;
    $speed='??'    if $netName=~/^vnet/;                     # hardcoded in kernel to 10 which causes bogus msgs later
    $netSpeeds{$netName}=$speed    if $speed!~/Invalid/;    # this can happen on a VM where operstate IS up
    #print "set netSpeeds{$netName}=$speed\n";
  }

  # Since this routine can get called multiple times during
  # initialization, we need to make sure @netOrder gets clean start.
  undef @netOrder;
  @temp=`$Grep -v -E "Inter|face" /proc/net/dev`;
  foreach my $temp (@temp)
  {
    next    if $rawNetFilter ne '' && $temp!~/$rawNetFilter/;

    $temp=~/^\s*(\S+)/;    # most names have leading whitespace
    $netName=$1;
    $netName=~s/://;
    $NetWidth=length($netName)    if length($netName)>$NetWidth;
    $speed=($netName=~/^ib/) ? $ibSpeed : $netSpeeds{$netName};
    $speed='??'   if !defined($speed);

    push @netOrder, $netName;
    $netIndex=$netIndexNext;
    $networks{$netName}=$netIndexNext++;

    # Since speeds are in Mb we really need to multiple by 125 to conver to KB
    $NetMaxTraffic[$netIndex]=($speed ne '' && $speed ne '??') ?
		2*$interval1*$speed*125 : 2*$interval1*$DefNetSpeed*125;
  }
  $netSeenLast=$netIndexNext;
  $NetWidth++;    # make room for trailing colon

  #    S C S I    C h e c k s

  # not entirely sure what to do with SCSI info, but if feels like a good
  # thing to have.  also, if no scsi present deal accordingly
  undef @temp;
  $ScsiInfo='';
  if (-e "/proc/scsi/scsi")
  {
    @temp=`$Grep -E "Host|Type" /proc/scsi/scsi`;
    foreach $temp (@temp)
    {
      if ($temp=~/^Host: scsi(\d+) Channel: (\d+) Id: (\d+) Lun: (\d+)/)
      {
        $scsiHost=$1;
        $channel=$2;
        $id=$3;
        $lun=$4;
      }
      if ($temp=~/Type:\s+(\S+)/)
      {
        $scsiType=$1;
        $type="??";
        $type="SC"    if $scsiType=~/scanner/i;
        $type="DA"    if $scsiType=~/Direct-Access/i;
        $type="SA"    if $scsiType=~/Sequential-Access/i;
        $type="CD"    if $scsiType=~/CD-ROM/i;
        $type="PR"    if $scsiType=~/Processor/i;

        $ScsiInfo.="$type:$scsiHost:$channel:$id:$lun ";
      }
    }
    $ScsiInfo=~s/ $//;
  }

  #    L u s t r e    C h e c k s

  $CltFlag=$MdsFlag=$OstFlag=0;
  $NumLustreFS=$numBrwBuckets=0;
  if ($subsys=~/l/i)
  {
    if ((`ls /lib/modules/*/kernel/net/lustre 2>/dev/null|wc -l`==0) &&
        (`ls /lib/modules/*/*/kernel/net/lustre 2>/dev/null|wc -l`==0))
    {
      disableSubsys('l', 'this system does not have lustre modules installed');
    }
    else
    {
      # Get Luster and SFS Versions before looking at any data structions in the
      # 'lustreCheck' routines because things change over time
      $temp=`$Lctl lustre_build_version 2>/dev/null`;
      $temp=~/version: (.+?)-/m;
      $cfsVersion=$1;
      $sfsVersion='';
      if (-e '/etc/sfs-release')
      {
        $temp=cat('/etc/sfs-release');
	$temp=~/(\d.*)/;
	$sfsVersion=$1;
      }
      elsif (-e "/usr/sbin/sfsmount" && -e $Rpm)
      {
        # XC and client enabler
        $llite=`$Rpm -qa | $Grep lustre-client`;
        $llite=~/lustre-client-(.*)/;
        $sfsVersion=$1;
      }

      $OstWidth=$FSWidth=0;
      $NumMds=$NumOst=0;
      $MdsNames=$OstNames=$lustreCltInfo='';
      $inactiveOstFlag=0;
      lustreCheckClt();
      lustreCheckMds();
      lustreCheckOst();
      print "Lustre -- CltFlag: $CltFlag  NumMds: $NumMds  NumOst: $NumOst\n"
	  if $debug & 8;

      disableSubsys('l', "no lustre services running and I don't know its type.  You will need to use --lustsvc to force type.")
      	if $CltFlag+$NumMds+$NumOst==0 && $lustreSvcs eq '';

      # Global to count how many buckets there are for brw_stats
      @brwBuckets=(1,2,4,8,16,32,64,128,256);

      push @brwBuckets, (512,1024)    if $sfsVersion ge '2.2';
      $numBrwBuckets=scalar(@brwBuckets);

      # if we're doing lustre DISK stats, figure out what kinds of disks
      # and then build up a list of them for collection to use.  To keep switch
      # error processing clean, only try to open the file if an MDS or OSS.
      # Since services may not be up, we also need to look at '$lustreSvcs',
      # though ultimately we'll only set the disk types and the maximum buckets
      if ($subsys=~/l/i && $lustOpts=~/D/ && ($MdsFlag || $OstFlag || $lustreSvcs=~/[mo]/i))
      {
        # The first step is to build up a hash of the sizes of all the
        # existing partitions.  Since we're only doing this once, a 'cat's
        # overhead should be minimal
        @partitions=`cat /proc/partitions`;
        foreach $part (@partitions)
        {
          # ignore blank lines and header
          next    if $part=~/^\s*$|^major/;

          # now for the magic.  Get the partition size and name, but ignore
          # cciss devices on controller 0 OR any devices with partitions
          # noting cciss device partitions end in 'p-digit' and sd partitions
          # always end in a digit.
	  ($size, $name)=(split(/\s+/, $part))[3,4];
  	  $name=~s/cciss\///;
	  next    if $name=~/^c0|^c.*p\d$|^sd.*\d$/; 
          $partitionSize{$name}=$size;
        }

        # Determine which directory to look in based on whether or not there
        # is an EVA present.  If so, we look at 'sd' stats; otherwize 'cciss'
        $LusDiskNames='';
        $LusDiskDir=(-e '/proc/scsi/sd_iostats') ? 
	  '/proc/scsi/sd_iostats' : '/proc/driver/cciss/cciss_iostats';

        # Now find all the stat files, noting that in the case of cciss, we
        # always skip c0 disks since they're local ones...  Also note that
        # if we're doing a showHeader with -Lm or -Lo on a client, the file
        # isn't there AND we don't want to report an error either.
        $openFlag=(opendir(DIR, $LusDiskDir)) ? 1 : 0;
        logmsg('F', "Disk stats requested but couldn't open '$LusDiskDir'")
	    if !$openFlag && !$showHeaderFlag;
        while ($diskname=readdir(DIR))
        {
	  next    if $diskname=~/^\.|^c0/;

  	  # if this has a partition within the range of a service lun,
          # ignore it.
          if ($partitionSize{$diskname}/(1024*1024)<$LustreSvcLunMax)
          {
	    print "Ignoring $diskname because its size of ".
	        "$partitionSize{$diskname} is less than ${LustreSvcLunMax}GB\n"
		    if $debug & 1;
  	    next;
          }
          push @LusDiskNames, $diskname;
          $LusDiskNames.="$diskname ";
        }
        $LusDiskNames=~s/ $//;
        $NumLusDisks=scalar(@LusDiskNames);
        $LusMaxIndex=($LusDiskNames=~/sd/) ? 16 : 24;
      }
    }
  }

  #    S L A B    C h e c k s

  # Header for /proc/slabinfo changed in 2.6
  if ($slabinfoFlag && $subsys=~/y/i)
  {
    $SlabGetProc=($slabFilt eq '') ? 99 : 14;

    $temp=`head -n 1 /proc/slabinfo`;
    $temp=~/(\d+\.\d+)/;
    $SlabVersion=$1;
    $NumSlabs=`cat /proc/slabinfo | wc -l`*1;
    chomp $NumSlabs;
    $NumSlabs-=2;

    if ($SlabVersion!~/^1\.1|^2/)
    {
      # since 'W' will echo on terminal, we only use when writing to files
      $severity=(defined($opt_s)) ? "E" : "I";
      $severity="W"    if $logToFileFlag;
      logmsg($severity, "unsupported /proc/slabinfo version: $SlabVersion");
      $subsys=~s/y//gi;
      $yFlag=$YFlag=0;
    }
  }
}

# Why is initFormat() so damn big?
# 
# Since logs can be analyzed on a system on which they were not generated
# and to avoid having to read the actual data to determine things like how
# many cpus or disks there are, this info is written into the log file 
# header.  initFormat() then reads this out of the head and initialized the
# corresponding variables.
#
# Counters are always incrementing (until they wrap) and therefore to get the
# value for the current interval one needs decrement it by the sample from
# the previous interval.  Therefore, theere are 3 different types of 
# variables to deal with:
# - current sample: some 'root', ends in 'Now'
# - last sample:    some 'root', end in 'Last'
# - true value:     'root' only - rootNow-rootLast
#
# To make all this work the very first time through, all 'Last' variables 
# need to be initialized to 0 both to suppress -w initialization warnings AND
# because it's good coding practice.  Furthermore, life is a lot cleaner just
# to initialize everything whether we've selected the corresponding subsystem
# or not.  Furthermore, since it is possible to select a subsystem in plot
# mode for which we never gathered any data, we need to initialize all the 
# printable values to 0s as well.  That's why there is so much crap in 
# initFormat().

sub initFormat
{
  my $playfile=shift;
  my ($day, $mon, $year, $i, $recsys, $host);
  my ($version, $datestamp, $timestamp, $interval);

  $temp=(defined($playfile)) ? $playfile : '';
  print "initFormat($temp)\n"    if $debug & 1;

  # Constants local to formatting
  $OneKB=1024;
  $OneMB=1024*1024;
  $OneGB=1024*1024*1024;
  $TenGB=$OneGB*10;

  # in normal mode we report "/sec", but with -on we report "/int", noting
  # this is also appended to plot format headers
  $rate=$options!~/n/ ? "/sec" : "/int";

  if (defined($playfile))
  {
    $header=getHeader($playfile);
    return undef    if $header eq '';

    # save the first two lines of the header for writing into the new header.
    # since the Deamon Options have been renamed in V1.5.3 we need to get a 
    # little trickier to handle both.  Since they are so specific I'm leaving
    # them global.
    $header=~/(Collectl.*)/;
    $recHdr1=$1;
    $recHdr2=(($header=~/(Daemon Options: )(.*)/ || $header=~/(DaemonOpts: )(.*)/) && $2 ne '') ? "$1$2" : "";

    $header=~/Collectl:\s+V(\S+)/;
    $version=$1;
    $hiResFlag=$1    if $header=~/HiRes:\s+(\d+)/;   # only after V1.5.3

    $boottime=($header=~/Booted:\s+(\S+)/) ? $1 : 0;

    $Distro='';
    if ($header=~/Distro:\s+(.+)/)    # was optional before 'Platform' added
    {
      $Distro=$1;
      $ProductName=$1    if $Distro=~s/Platform: (.*)//;
    }

    # Prior to collect V3.2.1-4, use the header to determine the type of nfs data in the
    # file noting very old versions used SubOpts.
    $recNfsFilt=$1    if $header=~/NfsFilt: (\S*) \S/;
    $subOpts=($header=~/SubOpts:\s+(\S*)\s*Options/) ? $1 : '';    # pre V3.2.1-4
    if  ($version lt '3.2.1-4')
    {
      $nfsOpts=($header=~/NfsOpts: (\S*)\s*Interval/) ? $1 : $subOpts;
      $nfsOpts=~s/[BDMORcom]//g;    # in case it came from SubOpts remove lustre stuff

      if ($version lt '3.2.1-3')
      {
        $recNfsFilt=($nfsOpts=~/C/) ? 'c' : 's';
        $recNfsFilt.=($nfsOpts=~/([234])/) ? $1 : 3;
      }
      else
      {
        # very limited release
        $recNfsFilt=($nfsOpts=~/C/) ? 'c3,c4' : 's3,s4';
      }
    }

    if ($header=~/TcpFilt:\s+(\S+)/)
    {
      # remember, even if an option is not recorded we still report on it
      my $recOpts=(defined($1)) ? $1 : $tcpFiltDefault;
      $tcpFilt=$recOpts    if $tcpFilt eq '';
    }

    # Users CAN overrider LustOpts so we need to do it this way, again accounting for
    # older versions of collectl storing them as part of SubOpts
    if ($lustOpts eq '')
    {
      $lustOpts=($header=~/LustOpts: (\S*)\s*Services/) ? $1 : $subOpts;
      $lustOpts=~s/[23C]//g;    # remove nfs options
    }

    # we want to preserve original subsys from the header, but we
    # also want to override it if user did a -s.  If user specified a
    # +/- we also need to deal with as in collectl.pl, but in this
    # case without the error checking since it already passed through.
    # NOTE - rare, but if not subsys, set to ' ' also noting '' won't work
    #        in regx in collectl after call to this routine
    $header=~/SubSys:\s+(\S*) /;
    $recSubsys=$subsys=($1!~/Options/) ? $1 : ' ';
    $recHdr1.=" Subsys: $subsys";
    $recSubsys=$subsys='Y'    if $topSlabFlag && $userSubsys eq '';
    $recSubsys=$subsys='Z'    if $topProcFlag && $userSubsys eq '';

    # reset subsys based on what was recorded and -s
    $subsys=mergeSubsys($recSubsys);
    $subsys.='Y'    if $subsys!~/Y/ && $topSlabFlag;    # if --top need to include Y or Z if not in -s
    $subsys.='Z'    if $subsys!~/Z/ && $topProcFlag;

    # I'm not sure the Mds/Ost/Clt names still need to be initialized
    # but it can't hurt.  Clearly the 'lustre' variables do.
    $MdsNames=$OstNames=$lustreClts='';
    $lustreMdss=$lustreOsts=$lustreClts='';

    # This can only happen with pre 3.0.0 version of collectl
    if ($subsys=~/LL/)
    {
      $subsys=~s//L/;
      $lustOpts.='O';
    }

    # We ONLY override the settings for the raw file, never any others.
    # Even though currently only 'rawp' files, we're doing pattern match below
    # with [p] to make easier to add others if we ever need to.
    $playfile=~/(.*-\d{8})-\d{6}\.raw([p]*)/;
    if (defined($playbackSettings{$1}) && $2 eq '')
    {
      # NOTE - when -L not specified for lustre, $lustreSvcs will end up being 
      # set to the combined values of all files for this prefix
      ($subsys, $lustreSvcs, $lustreMdss, $lustreOsts, $lustreClts)=
		split(/\|/, $playbackSettings{$1});
      print "OVERRIDES - Subsys: $subsys  LustreSvc: $lustreSvcs  ".
	    "MDSs: $lustreMdss Osts: $lustreOsts Clts: $lustreClts\n"
			if $debug & 2048;
    }
    print "Playfile: $playfile  Subsys: $subsys\n"    if $debug & 1;
    setFlags($subsys);

    # In case not in current file header but defined within set for prefix/date
    $CltFlag=$MdsFlag=$OstFlag=$NumMds=$NumOst=$OstWidth=$FSWidth=0;
    $MdsNames=$lustreMdss    if $lustreMdss ne '';
    $OstNames=$lustreOsts    if $lustreOsts ne '';

    # Maybe some day we can get rid of pre 1.5.0 support?
    $numBrwBuckets=0;
    if ($header=~/Lustre/ && $version ge '1.5.0')
    {
      # Remember, we could have cfs without sfs so need 2 separate pattern tests
      $cfsVersion=$sfsVersion='';
      if ($version ge '2.1')
      {
        $header=~/CfsVersion:\s+(\S+)/;
	$cfsVersion=$1;
	$header=~/SfsVersion:\s+(\S+)/;
	$sfsVersion=$1;
      }

      # In case not already defined (for single or consistent files, these are
      # not specified as overrides), get them from the file header.  Note that
      # when no osts, this will grab the next line it I include \s* after
      # OstNames:, so for now I'm doing it this way and chopping leading space.
      $MdsHdrNames=$OstHdrNames='';
      if ($header=~/MdsNames:\s+(.*)\s*NumOst:\s+\d+\s+OstNames:(.*)$/m)
      {
        $MdsHdrNames=$1;
        $OstHdrNames=$2;
	$OstHdrNames=~s/\s+//;

        $MdsNames=($lustreMdss ne '') ? $lustreMdss : $MdsHdrNames;
        $OstNames=($lustreOsts ne '') ? $lustreOsts : $OstHdrNames;
      }

      if ($MdsNames ne '')
      {
        @MdsMap=remapLustreNames($MdsHdrNames, $MdsNames, 0)    if $MdsHdrNames ne '';
      	foreach $name (split(/ /, $MdsNames))
      	{	
          $NumMds++;
	  $MdsFlag=1;
        }
      }

      if ($OstNames ne '')
      {
        # This build list for interpretting input from 'raw' file if there is any
        @OstMap=remapLustreNames($OstHdrNames, $OstNames, 0)    if $OstHdrNames ne '';

        # This builds data needed for display
        foreach $name (split(/ /, $OstNames))
        {
	  $lustreOstName[$NumOst]=$name;
          $lustreOsts[$NumOst++]=$name;
	  $OstWidth=length($name)    if length($name)>$OstWidth;
	  $OstFlag=1;
        }
      }

      if ($header=~/CltInfo:\s+(.*)$/m)
      {
        $CltHdrNames=$1;
        $lustreCltInfo=($lustreCltInfo ne '') ? $lustreCltInfo : $CltHdrNames;
      }
      undef %fsNames;
      $CltFlag=$NumLustreFS=$NumLustreCltOsts=0;
      $lustreCltInfo=$lustreClts    if $lustreClts ne '';

      if ($lustreCltInfo ne "")
      {
        $CltFlag=1;
        foreach $name (split(/ /, $lustreCltInfo))
        {
          ($fsName, $ostName)=split(/:/, $name);

          $lustreCltFS[$NumLustreFS++]=$fsName    if !defined($fsNames{$fsName});
          $fsNames{$fsName}=1;
          $FSWidth=length($fsName)    if length($fsName)>$FSWidth;

          # if osts defined, we just overwrite anything with did for the non-ost
          if ($ostName ne '')
          {
	    $lustreCltOsts[$NumLustreCltOsts]=$ostName;
            $lustreCltOstFS[$NumLustreCltOsts]=$fsName;
            $OstWidth=length($ostName)    if length($ostName)>$OstWidth;
            $NumLustreCltOsts++;
          }
        }

        @CltFSMap= remapLustreNames($CltHdrNames, $lustreCltInfo, 1)
	    if defined($CltHdrNames);
        @CltOstMap=remapLustreNames($CltHdrNames, $lustreCltInfo, 2)
	    if defined($CltHdrNames);
      }
      print "CLT: $CltFlag  OST: $OstFlag  MDS: $MdsFlag\n"    if $debug & 1;

      # if disk I/O stats specified in header, init appropriate variables
      if ($header=~/LustreDisks.*Names:\s+(.*)/)
      {
        @lusDiskDirs=split(/\s+/, $1);
	$NumLusDisks=scalar(@lusDiskDirs);
        $LusDiskNames=$1;
	@LusDiskNames=split(/\s+/, $LusDiskNames);
      }
    }
    else    # PRE 1.5.0 lustre stuff goes here...
    {
      if ($header=~/NumOsts:\s+(\d+)\s+NumMds:\s+(\d+)/)
      {
        $NumOst=$1;
        $NumMds=$2;
	$OstNames=$MdsNames='';
	for ($i=0; $i<$NumOst; $i++)
	{
	  $OstMap[$i]=$i;
	  $OstNames.="Ost$i ";
	  $lustreOsts[$i]="Ost$i";
	  $OstWidth=length("Ost$i")    if length("ost$i")>$OstWidth;
	  $OstFlag=1;	
	}
	$OstNames=~s/ $//;

	for ($i=0; $i<$NumMds; $i++)
	{
	  $MdsMap[$i]=$i;
	  $MdsNames.="Mds$i ";
	  $MdsFlag=1;	
	}
	$MdsNames=~s/ $//;
      }

      $NumLustreFS=$NumLustreCltOsts=0;
      if ($header=~/FS:\s+(.*)\s+Luns:\s+(.*)\s+LunNames:\s+(.*)$/m)
      {
	$CltFlag=1;
	$tempFS=$1;
        $tempLuns=$2;
        $tempFSNames=$3;

        foreach $fsName (split(/ /, $tempFS))
        {
          $CltFSMap[$NumLustreFS]=$NumLustreFS;
	  $lustreCltFS[$NumLustreFS]=$fsName;
          $FSWidth=length($fsName)    if length($fsName)>$FSWidth;
	  $NumLustreFS++;
        }

	# If defined, user did --lustopts O and need to reset FS info
	# Also note that since these numbers appear in raw data, we can't use a
        # simple index but rather need lun number
	if ($tempLuns ne '')
        {
	  # The lun numbers will be mapped into OSTs
          foreach $lunNum (split(/ /, $tempLuns))
          {
            $CltFSMap[$lunNum]=$NumLustreCltOsts;
            $CltOstMap[$lunNum]=$NumLustreCltOsts;
	    $lustreCltOsts[$NumLustreCltOsts]=$lunNum;
            $OstWidth=length($lunNum)    if length($lunNum)>$FSWidth;
	    $NumLustreCltOsts++;
	  }
	  $NumLustreFS=0;
          foreach $fsName (split(/ /, $tempFSNames))
          {
	    $lustreCltOstFS[$NumLustreFS]=$fsName;
            $FSWidth=length($fsName)    if length($fsName)>$FSWidth;
	    $NumLustreFS++;
          }
        }
      }
    }

    $header=~/Host:\s+(\S+)/;
    $Host=$1;
    $HostLC=lc($Host);

    # we need this for timezone conversions...
    $header=~/Date:\s+(\d+)-(\d+)/;
    $datestamp=$1;
    $timestamp=$2;
    $timesecs=$timezone='';  # for logs generated with older versions
    if ($header=~/Secs:\s+(\d+)\s+TZ:\s+(.*)/)
    {
      $timesecs=$1;
      $timezone=$2;
    }

    # Allows us to move its location in the header
    $header=~/Interval: (\S+)/;
    $interval=$1;

    # For -s p calculations, we need the HZ of the system
    $header=~/HZ:\s+(\d+)\s+Arch:\s+(\S+)/;
    $HZ=$1;
    $SrcArch=$2;

    # In case pagesize not defined in header (for earlier versions
    # of collectl) pick a default based on architecture;
    $PageSize=($SrcArch=~/ia64/) ? 16384 : 4096;
    $PageSize=$1    if $header=~/PageSize:\s+(\d+)/;

    # Even though we don't do anything with CPU, Speed, Cores and Siblings we need
    # to put them in new header.
    $header=~/Cpu:\s+(.*) Speed/;
    $CpuVendor=$1;
    $header=~/Speed\(MHz\): (\S+)/;
    $CpuMHz=$1;
    $header=~/Cores: (\d+)/;
    $CpuCores=$1;
    $header=~/Siblings: (\d+)/;
    $CpuSiblings=$1;
    $header=~/Nodes: (\d+)/;
    $CpuNodes=$1;

    # when playing back from a file we need to make sure the KERNEL is that of
    # the file and not the one the data was collected on.
    $header=~/Kernel:\s+(\S+)/;
    $Kernel=$1;
    error("collectl no longer supports 2.4 kernels")    if $Kernel=~/^2\.4/;

    $header=~/NumCPUs:\s+(\d+)/;
    $NumCpus=$1;
    $Hyper=($header=~/HYPER/) ? "[HYPER]" : "";

    $header=~/NumBud:\s+(\d+)/;
    $NumBud=$1;

    $flags=($header=~/Flags:\s+(\S+)/) ? $1 : '';
    $tworawFlag=     ($flags=~/[g2]/) ? 1 : 0;
    $processIOFlag=  ($flags=~/i/) ? 1 : 0;
    $slubinfoFlag=   ($flags=~/s/) ? 1 : 0;
    $processCtxFlag= ($flags=~/x/) ? 1 : 0;
    $cpuDisabledFlag=($flags=~/D/) ? 1 : 0;

    # If we're not processing CPU data, this message will never be set so
    # just initialized for all cases.
    $cpuDisabledMsg='';

    $header=~/Memory:\s+(\d+)/;
    $Memory=$1;

    # Since disks are discovered dynamically all we need to init a few pointers.
    $dskIndex=$dskSeenLast=0;

    # networks are dynamic too but also messier because while we can't get speeds in playback mode
    # we do need those that have been recorded so our 'bogus' checks.
    $header=~/NumNets:\s+(\d+)\s+NetNames:\s+(.*)/;
    $numNets=$1;
    $netNames=$2;
    $NetWidth=$netOptsW;
    my $netIndex=0;
    my $interval1=(split(/:/, $interval))[0];
    foreach my $netName (split(/ /, $netNames))
    {
      my $speed=($netName=~/:(\d+)/) ? $1 : $DefNetSpeed;
      $netName=~s/(\S+):.*/$1/;
      $NetMaxTraffic[$netIndex]=2*$interval1*$speed*125;
      $NetWidth=length($netName)    if $NetWidth<length($netName);
      $networks{$netName}=$netIndex++;
      push @netOrder, $netName;
      $netSpeeds{$netName}=$speed;
    }
    $netIndexNext=$netSeenLast=$netIndex;
    $NetWidth++;

    # This really shouldn't happen but data collected before V3.5.1 could have added new
    # network devices, incremented $numNets and not updated NetNames!
    if ($numNets!=$netIndexNext)
    {
      logmsg('E', "NumNets in header is '$numNets' but only '$netIndexNext' listed and so was reset");
      logmsg('E', "This is a BUG because this was fixed in V3.5.1")    if $version ge '3.5.1';
    }

    # shouldn't hurt if no slabs defined since we only use during slab reporting
    # but if there ARE slabs and not the slub allocator, we've got the older type
    $header=~/NumSlabs:\s+(\d+)\s+Version:\s+(\S+)/;
    $NumSlabs=$1;
    $SlabVersion=$2;
    $slabinfoFlag=1    if $NumSlabs && !$slubinfoFlag;

    # If using the SLUB allocator, the data has been recorded using the 'root' names for each
    # slab and when we print the data we want the 'first' name which we need to extract from
    # the header.  All other data in $slabdata{} will be populated as the raw data is read in.
    if ($slubinfoFlag)
    {
      my $skipFlag=1;
      foreach my $line (split(/\n/, $header))
      {
	if ($line=~/#SLUB/)
        {
  	  $skipFlag=0;
	  next;
        }
	next    if $skipFlag;
        next    if $line=~/^##/;

	$line=~s/^#//;
	my ($slab, $first)=split(/\s+/, $line);
        $slabfirst{$first}=$slab;
      }
    }

    # Since what is recorded for slabs is identical whether y or Y, we want 
    # to be able to let someone who recorded with -sy play it back with -sY
    # and so the extra diddling with $yFlag and $YFlag.  Eventually we may
    # find other flags to diddle too.
    $yFlag=$YFlag=1    if $userSubsys=~/y/i;

    # This one not always present in header
    $NumXRails=0;
    $XType=$XVersion='';
    if ($header=~/NumXRails:\s+(\d+)\s+XType:\s+(\S*)\s+XVersion:\s+(\S*)/m)
    {
      $NumXRails=$1;
      $XType=$2;
      $XVersion=$3;
    }

    # Nor this
    $NumHCAs=0;
    if ($header=~/NumHCAs:\s+(\d+)\s+PortStates:\s+(\S+)/m)
    {
      $NumHCAs=$1;
      $portStates=$2;
      for ($i=0; $i<$NumHCAs; $i++)
      {
	# The first 2 chars are the states for ports 1 and 2.  The last HCA will
        # only have 2 chars and therefore we don't try to shift.
	$HCAPorts[$i][1]=substr($portStates, 0, 1);
	$HCAPorts[$i][2]=substr($portStates, 1, 1);
	$portStates=substr($portStates, 3)    if length($portStates)>2;
      }

      # Now get OFED/Perqquery versions which for earlier versions were not in header
      # Not clear if we really need these in playback mode but since we may some day...
      $IBVersion=($header=~/IBVersion:\s+(\S+)/) ? $1 : '';
      $PQVersion=($header=~/PQVersion:\s+(\S+)/) ? $1 : '';
    }

    # Scsi info is optional
    $ScsiInfo=($header=~/SCSI:\s+(.*)/) ? $1 : '';

    # Pass header to import routines BUT only if they have a callback defined
    for (my $i=0; $i<$impNumMods; $i++)
    { &{$impGetHeader[$i]}(\$header)    if defined(&{$impGetHeader[$i]});}
  }

  # Initialize global arrays with sizes of buckets for lustre brw stats and
  # not to worry if lustre not there.
  @brwBuckets=(1,2,4,8,16,32,64,128,256);
  push @brwBuckets, (512,1024)    if defined($sfsVersion) && $sfsVersion ge '2.2';
  $numBrwBuckets=scalar(@brwBuckets);

  # same thing for lustre disk state though these are a little tricker.
  if ($LusDiskNames=~/sd/)
  {
    @diskBuckets=(.5,1,2,4,8,16,32,64,128,256,512,1024,2048,4096,8192,16384);
  }
  else
  {
    @diskBuckets=(.5,1,2,4,8,16,32,63,64,65,80,96,112,124,128,129,144,252,255,256,257,512,1024,2048);
  }
  $LusMaxIndex=scalar(@diskBuckets);

  # this inits lustre variables in both playback and collection modes.
  initLustre('o',  0, $NumOst);
  initLustre('m',  0, $NumMds);
  initLustre('c',  0, $NumLustreFS);
  initLustre('c2', 0, $NumLustreCltOsts)    if $NumLustreCltOsts ne '-';

  #    I n i t    ' C o r e '    V a r i a b l e s

  # when we're generating plot data and we're either not collecting
  # everything or we're in playback mode and it's not all in raw file, make
  # sure all the core variables that get printed have been initialized to 0s.
  # for disks, nets and pars the core variables are the totals and so get
  # initialized in the initInterval() routine every cycle
  $i=$NumCpus;
  $userP[$i]=$niceP[$i]=$sysP[$i]=$idleP[$i]=$totlP[$i]=0;
  $irqP[$i]=$softP[$i]=$stealP[$i]=$waitP[$i]=0;

  for (my $i=0; $i<$CpuNodes; $i++)
  {
    foreach my $numa ('used', 'free', 'slab', 'map', 'anon', 'lock', 'inact',)
    { $numaMem[$i]->{$numa}=$numaMem[$i]->{$numa.'C'}=0; }

    foreach my $hits ('for', 'miss', 'hits')
    { $numaStat[$i]->{$hits}=0; }   
  }

  $dentryNum=$dentryUnused=$filesAlloc=$filesMax=$inodeUsed=$inodeMax=0;
  $loadAvg1=$loadAvg5=$loadAvg15=$loadRun=$loadQue=$ctxt=$intrpt=$proc=0;
  $memDirty=$clean=$target=$laundry=$memAct=$memInact=0;
  $procsRun=$procsBlock=0;
  $pagein=$pageout=$swapin=$swapout=$swapTotal=$swapUsed=$swapFree=0;
  $pagefault=$pagemajfault=0;
  $memTot=$memUsed=$memFree=$memShared=$memBuf=$memCached=$memSlab=$memAnon=$memMap=$memCommit=$memLocked=0;
  $memHugeTot=$memHugeFree=$memHugeRsvd=$memSUnreclaim=0;
  $sockUsed=$sockTcp=$sockOrphan=$sockTw=$sockAlloc=0;
  $sockMem=$sockUdp=$sockRaw=$sockFrag=$sockFragM=0;

  # extended memory stats, just in case some are missing
  $pageFree=$pageActivate=0;
  $pageAllocDma=$pageAllocDma32=$pageAllocNormal=$pageAllocMove=0;
  $pageRefillDma=$pageRefillDma32=$pageRefillNormal=$pageRefillMove=0;
  $pageStealDma=$pageStealDma32=$pageStealNormal=$pageStealMove=0;
  $pageKSwapDma=$pageKSwapDma32=$pageKSwapNormal=$pageKSwapMove=0;
  $pageDirectDma=$pageDirectDma32=$pageDirectNormal=$pageDirectMove=0;

  # Lustre MDS stuff - in case no data
  $lustreMdsReintCreate=$lustreMdsReintLink=$lustreMdsReintSetattr=0;
  $lustreMdsReintRename=$lustreMdsReintUnlink=$lustreMdsReint=0;
  $lustreMdsGetattr=$lustreMdsGetattrLock=$lustreMdsStatfs=0;
  $lustreMdsGetxattr=$lustreMdsSetxattr=$lustreMdsSync=0;
  $lustreMdsConnect=$lustreMdsDisconnect=0;

  # Common nfs stats
  $rpcCCalls=$rpcSCalls=$rpcBadAuth=$rpcBadClnt=$rpcRetrans=$rpcCredRef=0;
  $nfsPkts=$nfsUdp=$nfsTcp=$nfsTcpConn=0;

  # V2
  $nfs2CNull=$nfs2CGetattr=$nfs2CSetattr=$nfs2CRoot=$nfs2CLookup=$nfs2CReadlink=
  $nfs2CRead=$nfs2CWrcache=$nfs2CWrite=$nfs2CCreate=$nfs2CRemove=$nfs2CRename=
  $nfs2CLink=$nfs2CSymlink=$nfs2CMkdir=$nfs2CRmdir=$nfs2CReaddir=$nfs2CFsstat=$nfs2CMeta=0;
  $nfs2SNull=$nfs2SGetattr=$nfs2SSetattr=$nfs2SRoot=$nfs2SLookup=$nfs2SReadlink=
  $nfs2SRead=$nfs2SWrcache=$nfs2SWrite=$nfs2SCreate=$nfs2SRemove=$nfs2SRename=
  $nfs2SLink=$nfs2SSymlink=$nfs2SMkdir=$nfs2SRmdir=$nfs2SReaddir=$nfs2SFsstat=$nfs2SMeta=0;

  # V3
  $nfs3CNull=$nfs3CGetattr=$nfs3CSetattr=$nfs3CLookup=$nfs3CAccess=$nfs3CReadlink=0;
  $nfs3CRead=$nfs3CWrite=$nfs3CCreate=$nfs3CMkdir=$nfs3CSymlink=$nfs3CMknod=$nfs3CRemove=0;
  $nfs3CRmdir=$nfs3CRename=$nfs3CLink=$nfs3CReaddir=$nfs3CReaddirplus=$nfs3CFsstat=0;
  $nfs3CFsinfo=$nfs3CPathconf=$nfs3CCommit=$nfs3CMeta=0;
  $nfs3SNull=$nfs3SGetattr=$nfs3SSetattr=$nfs3SLookup=$nfs3SAccess=$nfs3SReadlink=0;
  $nfs3SRead=$nfs3SWrite=$nfs3SCreate=$nfs3SMkdir=$nfs3SSymlink=$nfs3SMknod=$nfs3SRemove=0;
  $nfs3SRmdir=$nfs3SRename=$nfs3SLink=$nfs3SReaddir=$nfs3SReaddirplus=$nfs3SFsstat=0;
  $nfs3SFsinfo=$nfs3SPathconf=$nfs3SCommit=$nfs3SMeta=0;

  # V4
  $nfs4CNull=$nfs4CRead=$nfs4CWrite=$nfs4CCommit=$nfs4CSetattr=$nfs4CFsinfo=0;
  $nfs4CAccess=$nfs4CGetattr=$nfs4CLookup=$nfs4CRemove=$nfs4CRename=$nfs4CLink=0;
  $nfs4CSymlink=$nfs4CCreate=$nfs4CPathconf=$nfs4CReadlink=$nfs4CReaddir=$nfs4CMeta=0;
  $nfs4SAccess=$nfs4SCommit=$nfs4SCreate=$nfs4SGetattr=$nfs4SLink=$nfs4SLookup=0;
  $nfs4SRead=$nfs4SReaddir=$nfs4SReadlink=$nfs4SRemove=$nfs4SRename=$nfs4SSetattr=0;
  $nfs4SWrite=$nfs4SMeta=0;

  # tcp - this is sooo ugly.  not all variable are part of all kernels and these are at least
  # some of the ones I've found to be missing in some.  This list may need to be augmented over
  # time.  The alternative it to have conditional tests on all the printing and there is just
  # too much of that.
  $tcpData{TcpExt}->{PAWSEstab}=      $tcpData{TcpExt}->{DelayedACKs}=   $tcpData{TcpExt}->{TW}=0;
  $tcpData{TcpExt}->{DelayedACKLost}= $tcpData{TcpExt}->{TCPPrequeued}=  $tcpData{TcpExt}->{TCPDirectCopyFromPrequeue}=0;
  $tcpData{TcpExt}->{TCPHPHits}=      $tcpData{TcpExt}->{TCPPureAcks}=   $tcpData{TcpExt}->{TCPHPAcks}=0;
  $tcpData{TcpExt}->{TCPDSACKOldSent}=$tcpData{TcpExt}->{TCPAbortOnData}=$tcpData{TcpExt}->{TCPAbortOnClose}=0;
  $tcpData{TcpExt}->{TCPSackShiftFallback}=0;

  $tcpData{IpExt}->{InMcastPkts}=  $tcpData{IpExt}->{InBcastPkts}=  $tcpData{IpExt}->{InOctets}=0;
  $tcpData{IpExt}->{InMcastOctets}=$tcpData{IpExt}->{InBcastOctets}=$tcpData{IpExt}->{OutMcastPkts}=0;
  $tcp{IpExt}->{OutOctets}=        $tcpData{IpExt}->{OutMcastOctets}=0;

  $tcpData{TcpExt}->{TCPLoss}=$tcpData{TcpExt}->{TCPFastRetrans}=0;
  $ipErrors=$icmpErrors=$tcpErrors=$udpErrors=$ipExErrors=$tcpExErrors=0;

  # this is here strictly for compatibility with older raw files
  $NumTcpFields=65;
  for ($i=0; $i<$NumTcpFields; $i++)
  { $tcpValue[$i]=$tcpLast[$i]=0; }

  # get ready to process first interval noting '$lastSecs' gets initialized 
  # when the data file is read in playback mode
  $lastSecs[0]=$lastSecs[1]=0    if $playback eq '';
  $intFirstSeen=0;
  initInterval();

  #    I n i t    ' E x t e n d e d '    V a r i a b l e s

  # The current thinking is if someone wants to plot extended variables and
  # they haven't been collected (remember the rule that when you report for
  # plotting, you always produce what's in -s) we better intialize the results
  # variables to all zeros.

  for ($i=0; $i<$NumCpus; $i++)
  {
    $userP[$i]=$niceP[$i]=$sysP[$i]=$idleP[$i]=$totlP[$i]=0;
    $irqP[$i]=$softP[$i]=$stealP[$i]=$waitP[$i]=0;
  }

  # these all need to be initialized in case we use /proc/stats since not all variables
  # supplied by that

  for ($i=0; $i<<$dskIndexNext; $i++)
  {
    $dskOps[$i]=$dskTicks[$i]=0;
    $dskRead[$i]=$dskReadKB[$i]=$dskReadMrg[$i]=0;
    $dskWrite[$i]=$dskWriteKB[$i]=$dskWriteMrg[$i]=0;
    $dskRqst[$i]=$dskQueLen[$i]=$dskWait[$i]=$dskSvcTime[$i]=$dskUtil[$i]=0;
  }

  for ($i=0; $i<$netIndexNext; $i++)
  {
    $netName[$i]="";
    $netRxPkt[$i]=$netTxPkt[$i]= $netRxKB[$i]=  $netTxKB[$i]=  $netRxErr[$i]=
    $netRxDrp[$i]=$netRxFifo[$i]=$netRxFra[$i]= $netRxCmp[$i]= $netRxMlt[$i]=
    $netTxErr[$i]=$netTxDrp[$i]= $netTxFifo[$i]=$netTxColl[$i]=$netTxCar[$i]=
    $netTxCmp[$i]=$netRxErrs[$i]=$netTxErrs[$i]=0;
  }

  # Don't forget infiniband
  for ($i=0; $i<$NumHCAs; $i++)
  {
    $ibTxKB[$i]=$ibTx[$i]=$ibRxKB[$i]=$ibRx[$i]=$ibErrorsTot[$i]=0;
  }

  # if we ever want to map scsi devices to their host/channel/etc, this does it
  # for partitions
  undef @scsi;
  $scsiIndex=0;
  foreach $device (split(/\s+/, $ScsiInfo))
  {
    $scsi[$scsiIndex++]=(split(/:/, $device, 2))[1]    if $device=~/DA/;
  }

  #    C o n s t a n t    H e a d e r    S t u f f

  # I suppose for performance it would be good to build all headers once, 
  # but for now at least do a few pieces.

  # get mini date/time header string according to $options but also note these
  # don't apply to --top mode
  $miniDateTime="";  # so we don't get 'undef' down below
  $miniDateTime="Time     "                  if $miniTimeFlag;
  $miniDateTime="Date Time      "            if $miniDateFlag && $options=~/d/;
  $miniDateTime="Date    Time      "         if $miniDateFlag && $options=~/D/;
  $miniDateTime.="    "                      if $options=~/m/;
  $miniFiller=' ' x length($miniDateTime);

  # sometimes we want to shift things 1 space to the left.
  $miniFiller1=substr($miniFiller, 0, length($miniFiller)-1);

  # If we need two lines, we need to align
  $len=length($miniDateTime);
  $miniBlanks=sprintf("%${len}s", '');

  $interval1Counter=0;

  #    S l a b    S t u f f

  $slabIndexNext=0;
  $slabDataFlag=0;
  undef %slabIndex;

  #    P r o c e s s   S t u f f

  $procIndexNext=0;

  #    I n t e r v a l 2    S t u f f

  $interval2Counter=

  #    I n t e r v a l 3    S t u f f

  $interval3Counter=0;
  $ipmiFile->{pre}=[];    # in case no --envrules specified
  $ipmiFile->{post}=[];
  $ipmiFile->{ignore}=[];
  loadEnvRules()    if $subsys=~/E/ || $envTestFile ne '';

  # Wasn't sure if this should have been buried in 'loadEnvRules()'
  # since they're not actualy 'rules'
  if ($envRemap ne '')
  {
    @envRemaps=split(/,/,$envRemap);
    for (my $i=0; $i<@envRemaps; $i++)
    {
      $envRemaps[$i]=~/\/(.*?)\/(.*?)\//;
      $ipmiRemap->[$i]->[1]=$1;
      $ipmiRemap->[$i]->[2]=$2;
    }
  }

  #    A r c h i t e c t u r e    S t u f f

  $word32=2**32;
  $maxword= ($SrcArch=~/ia64|x86_64/) ? 2**64 : $word32;

  return(($version, $datestamp, $timestamp, $timesecs, $timezone, $interval, $recSubsys, $recNfsFilt, $recHeader))
    if defined($playfile);
}

#    I n i t i a l i z e    ' L a s t '    V a r i a b l e s

sub initLast
{
  # 0=raw 1=rawp
  my $rawType=shift;

  # just init slab variables because process ones are all dynamic
  if (!defined($rawType) || $rawType)
  {
    for ($i=0; $i<$NumSlabs; $i++)
    {
      $slabObjActLast[$i]=$slabObjAllLast[$i]=0;
      $slabSlabActLast[$i]=$slabSlabAllLast[$i]=0;
    }
    return   if defined($rawType);
  }

  # Since dynamically defined need to start clean.
  undef(%intrptType);

  $ctxtLast=$intrptLast=$procLast=0;
  $rpcCCallsLast=$rpcSCallsLast=$rpcBadAuthLast=$rpcBadClntLast=0;
  $rpcRetransLast=$rpcCredRefLast=0;
  $nfsPktsLast=$nfsUdpLast=$nfsTcpLast=$nfsTcpConnLast=0;
  $pageinLast=$pageoutLast=$swapinLast=$swapoutLast=0;
  $pagefaultLast=$pagemajfaultLast=0;
  $opsLast=$readLast=$readKBLast=$writeLast=$writeKBLast=0;
  $memFreeLast=$memUsedLast=$memBufLast=$memCachedLast=0;
  $memInactLast=$memSlabLast=$memMapLast=$memAnonLast=$memCommitLast=$memLockedLast=0;
  $swapFreeLast=$swapUsedLast=0;

  for ($i=0; $i<18; $i++)
  {
    $nfs2CValuesLast[$i]=0;
    $nfs2SValuesLast[$i]=0;
  }

  for ($i=0; $i<22; $i++)
  {
    $nfs3CValuesLast[$i]=0;
    $nfs3SValuesLast[$i]=0;
  }

  for ($i=0; $i<59; $i++)
  {
    $nfs4CValuesLast[$i]=0;
    $nfs4SValuesLast[$i]=0;
  }

  for ($i=0; $i<=$NumCpus; $i++)
  {
    $userLast[$i]=$niceLast[$i]=$sysLast[$i]=$idleLast[$i]=0;
    $waitLast[$i]=$irqLast[$i]=$softLast[$i]=$stealLast[$i]=0;
  }

  for (my $i=0; $i<$CpuNodes; $i++)
  {
    $numaStat[$i]->{hitsLast}=$numaStat[$i]->{missLast}=$numaStat[$i]->{forLast}=0;
    $numaMem[$i]->{freeLast}= $numaMem[$i]->{usedLast}=$numaMem[$i]->{actLast}=0;
    $numaMem[$i]->{inactLast}=$numaMem[$i]->{mapLast}= $numaMem[$i]->{anonLast}=0;
    $numaMem[$i]->{lockLast}= $numaMem[$i]->{slabLast}=0;
  }

  # ...and disks
  for ($i=0; $i<$dskIndexNext; $i++)
  {
    $dskOpsLast[$i]=0;
    $dskReadLast[$i]=$dskReadKBLast[$i]=$dskReadMrgLast[$i]=$dskReadTicksLast[$i]=0;
    $dskWriteLast[$i]=$dskWriteKBLast[$i]=$dskWriteMrgLast[$i]=$dskWriteTicksLast[$i]=0;
    $dskInProgLast[$i]=$dskTicksLast[$i]=$dskWeightedLast[$i]=0;

    for ($j=0; $j<11; $j++)
    {
      $dskFieldsLast[$i][$j]=0;
    }
  }

  for ($i=0; $i<$netIndexNext; $i++)
  {
    $netRxKBLast[$i]=$netRxPktLast[$i]=$netTxKBLast[$i]=$netTxPktLast[$i]=0;
    $netRxErrLast[$i]=$netRxDrpLast[$i]=$netRxFifoLast[$i]=$netRxFraLast[$i]=0;
    $netRxCmpLast[$i]=$netRxMltLast[$i]=$netTxErrLast[$i]=$netTxDrpLast[$i]=0;
    $netTxFifoLast[$i]=$netTxCollLast[$i]=$netTxCarLast[$i]=$netTxCmpLast[$i]=0;
  }

  # and interconnect
  for ($i=0; $i<$NumXRails; $i++)
  {
    $elanSendFailLast[$i]=$elanNeterrAtomicLast[$i]=$elanNeterrDmaLast[$i]=0;
    $elanRxLast[$i]=$elanRxMBLast[$i]=$elanTxLast[$i]=$elanTxMBLast[$i]=0;
    $elanPutLast[$i]=$elanPutMBLast[$i]=$elanGetLast[$i]=$elanGetMBLast[$i]=0;
    $elanCompLast[$i]=$elanCompMBLast[$i]=0;
  }

  # IB
  for ($i=0; $i<$NumHCAs; $i++)
  {
    for ($j=0; $j<16; $j++)
    {
      # There are 2 ports on an hca, numbered 1 and 2
      $ibFieldsLast[$i][1][$j]=$ibFieldsLast[$i][2][$j]=0;
    }
  }
}

# When a subsys is selected for which this is no possibility of collecting
# data, we must disable it in subsys as well as any --export modules which
# explicitly selects that subsys too
sub disableSubsys
{
  my $type=  shift;
  my $why=   shift;
  my $unique=shift;

  # If user specified --all, they shouldn't see these messages
  logmsg("W", "-s$type disabled because $why")    if !$allFlag;
  $subsys=~s/$type//ig    if !defined($unique) || !$unique;    # disable using /i if unique not set
  $subsys=~s/$type//g     if  defined($unique) &&  $unique;    # otherwise just disablehe one specified

  # Not really sure if need to do this but it certainly can't hurt.
  $EFlag=0           if $type=~/E/;
  $bFlag=$BFlag=0    if $type=~/b/;
  $lFlag=$LFlag=0    if $type=~/l/;
  $xFlag=$XFlag=0    if $type=~/x/;

  # Now make sure any occurances in s= of an export are disabled too.
  for (my $i=0; $i<@expOpts; $i++)
  {
    if ($expOpts[$i]=~/s=.*$type/i)
    {
      logmsg('W', "found 's=$type' in lexpr so disabled there too")     if !$allFlag;
      $expOpts[$i]=~s/$type//ig;
    }
  }
}

# when playing back lustre data, the indexes on the detail stats may be shifted 
# relative to collectl logs in which other OSTs existed.  In other words in one
# file one may have "ostY ostZ", in a second "ostX ostZ" and in a third "ostY".
# We need to generate index mappings such that ost1 will always map to 0, ost2
# to 1 and so on.
sub remapLustreNames
{
  my $hdrNames=shift;
  my $allNames=shift;
  my $cltType= shift;
  my ($i, $j, $uuid, @hdrTemp, @allTemp, @maps);

  # the names as contained in the header are always unique, including ':ost' for
  # --lustopt O.  However, for --lustopts O reporting, we only want the ost part
  # and hence the special treatment.  Type=1 used to be meaningful before I realized
  # stripping off the ':ost' lead to non-unique names and incorrect remapping.
  if ($cltType==2)
  {
    $hdrNames=~s/\S+:(\S+)/$1/g;
    $allNames=~s/\S+:(\S+)/$1/g;
  }
  print "remapLustrenames() -- Type: $cltType HDR: $hdrNames  ALL: $allNames\nREMAPPED: "
	    if $debug & 8;

  if ($hdrNames ne '')
  {
    @hdrTemp=split(/ /, $hdrNames);
    @allTemp=split(/ /, $allNames);
    for ($i=0; $i<scalar(@hdrTemp); $i++)
    {
      for ($j=0; $j<scalar(@allTemp); $j++)
      {
	if ($hdrTemp[$i] eq $allTemp[$j])
        {
	  $maps[$i]=$j;
	  print "Map[$i]=$j "    if $debug & 8;
	  last;
        }
      }
    }
  }
  print "\n"    if $debug & 8;
  return(@maps);
}

# Technically this could get called from within the lustreCheck() routines
# but I didn't want it to get lost there...
sub initLustre
{
  my $type=shift;
  my $from=shift;
  my $to= shift;
  my ($i, $j);

  printf "initLustre() -- Type: $type  From: $from  Number: %s\n",
	  defined($to) ? $to : ''    if $debug & 8;

  # NOTE - we have to init both the 'Last' and running variables in case they're not
  # set during this interval since we don't want to use old values.
  if ($type eq 'o')
  {
    for ($i=$from; $i<$to; $i++)
    {
      $lustreReadOps[$i]=$lustreReadKBytes[$i]=0;
      $lustreWriteOps[$i]=$lustreWriteKBytes[$i]=0;

      $lustreReadOpsLast[$i]=$lustreReadKBytesLast[$i]=0;
      $lustreWriteOpsLast[$i]=$lustreWriteKBytesLast[$i]=0;
      for ($j=0; $j<$numBrwBuckets; $j++)
      {
        $lustreBufRead[$i][$j]=    $lustreBufWrite[$i][$j]=0;
        $lustreBufReadLast[$i][$j]=$lustreBufWriteLast[$i][$j]=0;
      }
    }
  }
  elsif ($type eq 'c')
  {
    for ($i=$from; $i<$to; $i++)
    {
      $lustreCltDirtyHits[$i]=$lustreCltDirtyMiss[$i]=0;
      $lustreCltRead[$i]=$lustreCltReadKB[$i]=0;
      $lustreCltWrite[$i]=$lustreCltWriteKB[$i]=0;
      $lustreCltOpen[$i]=$lustreCltClose[$i]=$lustreCltSeek[$i]=0;
      $lustreCltFsync[$i]=$lustreCltSetattr[$i]=$lustreCltGetattr[$i]=0;

      $lustreCltRAPending[$i]=$lustreCltRAHits[$i]=$lustreCltRAMisses[$i]=0;
      $lustreCltRANotCon[$i]=$lustreCltRAMisWin[$i]=$lustreCltRALckFail[$i]=0;
      $lustreCltRAReadDisc[$i]=$lustreCltRAZeroLen[$i]=$lustreCltRAZeroWin[$i]=0;
      $lustreCltRA2EofMax[$i]=$lustreCltRAHitMax[$i]=0;
      $lustreCltRAFalGrab[$i]=$lustreCltRAWrong[$i]=0;

      $lustreCltDirtyHitsLast[$i]=$lustreCltDirtyMissLast[$i]=0;
      $lustreCltReadLast[$i]=$lustreCltReadKBLast[$i]=0;
      $lustreCltWriteLast[$i]=$lustreCltWriteKBLast[$i]=0;
      $lustreCltOpenLast[$i]=$lustreCltCloseLast[$i]=$lustreCltSeekLast[$i]=0;
      $lustreCltFsyncLast[$i]=$lustreCltSetattrLast[$i]=$lustreCltGetattrLast[$i]=0;

      $lustreCltRAHitsLast[$i]=$lustreCltRAMissesLast[$i]=0;
      $lustreCltRANotConLast[$i]=$lustreCltRAMisWinLast[$i]=$lustreCltRALckFailLast[$i]=0;
      $lustreCltRAReadDiscLast[$i]=$lustreCltRAZeroLenLast[$i]=$lustreCltRAZeroWinLast[$i]=0;
      $lustreCltRA2EofLast[$i]=$lustreCltRAHitMaxLast[$i]=0;
      $lustreCltRAFalGrabLast[$i]=$lustreCltRAWrongLast[$i]=0;
    }
  }
  elsif ($type eq 'c2')
  {
    # only used for --lustopts B or O
    for ($i=$from; $i<$to; $i++)
    {
      $lustreCltLunRead[$i]= $lustreCltLunReadKB[$i]=0;
      $lustreCltLunWrite[$i]=$lustreCltLunWriteKB[$i]=0;

      $lustreCltLunReadLast[$i]= $lustreCltLunReadKBLast[$i]=0;
      $lustreCltLunWriteLast[$i]=$lustreCltLunWriteKBLast[$i]=0;

      for ($j=0; $j<$numBrwBuckets; $j++)
      {
        $lustreCltRpcRead[$i][$j]=    $lustreCltRpcWrite[$i][$j]=0;
        $lustreCltRpcReadLast[$i][$j]=$lustreCltRpcWriteLast[$i][$j]=0;
      }
    }
  }
  elsif ($type eq 'm')
  {
    $lustreMdsReintCreateLast=$lustreMdsReintLinkLast=$lustreMdsReintSetattrLast=0;
    $lustreMdsReintRenameLast=$lustreMdsReintUnlinkLast=$lustreMdsReintLast=0;
    $lustreMdsGetattrLast=$lustreMdsGetattrLockLast=$lustreMdsStatfsLast=0;
    $lustreMdsGetxattrLast=$lustreMdsSetxattrLast=$lustreMdsSyncLast=0;
    $lustreMdsConnectLast=$lustreMdsDisconnectLast=0;

    # Use maximum size (cciss disk buckets)
    $lusDiskReadsTot[24]=$lusDiskReadBTot[24]=0;
    $lusDiskWritesTot[24]=$lusDiskWriteKBTot[24]=0;
  }

  if ($lustOpts=~/D/)
  {
    for (my $i=0; $i<$NumLusDisks; $i++)
    {
      # cciss disks have up to 24 rows, 25 counting total line!
      for (my $j=0; $j<25; $j++)
      {
        $lusDiskReadsLast[$i][$j]=$lusDiskWritesLast[$i][$j]=0;
        $lusDiskReadBLast[$i][$j]=$lusDiskWriteBLast[$i][$j]=0;
      }
    }
  }
}

# as of now, not much happens here
# the 'inactive' flags tell us whether or not an inactive warning was issued
# today for this associated hardware.
sub initDay
{
  $newDayFlag=1;
  $inactiveOstFlag=0;
  $inactiveMyrinetFlag=0;
  $inactiveElanFlag=0;
  $inactiveIBFlag=0;
}

# these variables must be initialized at the start of each interval because
# they occur for multiple devices and/or on multiple lines in the raw file.
sub initInterval
{
  $budIndex=0;
  for (my $i=0; $i<11; $i++)
  {
    $buddyInfoTot[$i]=0;
  }

  $userP[$NumCpus]=$niceP[$NumCpus]=$sysP[$NumCpus]=$idleP[$NumCpus]=0;
  $irq[$NumCpus]=$softP[$NumCpus]=$stealP[$NumCpus]=$waitP[$NumCpus]=0;

  # Since the number of cpus can change dynamically, we need to clear these every pass,
  # BUT for now since we're only checking when monitoring CPUS and not interrupts we
  # can't clear the '$cpuEnabled' when not doing cpu stats since that's to much overhead
  # Further, if cpu data wasn't recorded but we're playing back, set the number enabled
  # to all so we don't report warnings that one or more are disabled

  # There are 2 major situations - either we're dealing with actual CPU stats or we're not.
  # If we are (and the weren't finessed during playback when they weren't really recorded)
  # clear the count since it will be incremented with each cpu processed.  Otherwise just
  # set to the total since we have no other way of knowing what's going in.
  # NOTE - if we record interrupts and not cpus and a CPU is or goes offline, this WILL 
  # break!!!
  my $reset=($subsys=~/c/i && ($playback eq '' || $recSubsys=~/c/i)) ? 1: 0;
  $cpusEnabled=($reset) ? 0 : $NumCpus;

  # if cpus are/were being recorded, reset their state since the cpu records will force
  # then to be enabled
  for (my $i=0; $i<$NumCpus; $i++)
  {
    $cpuEnabled[$i]=($reset & !$noCpusFlag) ? 0 : 1;    # only way to tell if $subsys reset
    $intrptTot[$i]=0;    # But these HAVE to be reset every interval
  }

  undef @netSeen;
  $netSeenCount=0;
  $netChangeFlag=0;
  $netRxKBTot=$netRxPktTot=$netTxKBTot=$netTxPktTot=0;
  $netEthRxKBTot=$netEthRxPktTot=$netEthTxKBTot=$netEthTxPktTot=0;
  $netRxErrTot=$netRxDrpTot=$netRxFifoTot=$netRxFraTot=0;
  $netRxCmpTot=$netRxMltTot=$netTxErrTot=$netTxDrpTot=0;
  $netTxFifoTot=$netTxCollTot=$netTxCarTot=$netTxCmpTot=0;
  $netRxErrsTot=$netTxErrsTot=0;

  undef @dskSeen;
  $dskSeenCount=0;
  $dskChangeFlag=0;
  $dskOpsTot=$dskReadTot=$dskWriteTot=$dskReadKBTot=$dskWriteKBTot=0;
  $dskReadMrgTot=$dskReadTicksTot=$dskWriteMrgTot=$dskWriteTicksTot=0;  

  $nfsCReadsTot=$nfsSReadsTot=$nfsCWritesTot=$nfsSWritesTot=0;
  $nfsCMetaTot=$nfsSMetaTot=$nfsCCommitTot=$nfsSCommitTot=0;
  $nfsReadsTot=$nfsWritesTot=$nfsMetaTot=$nfsCommitTot=0;
  $nfsUdpTot=$nfsTcpTot=$nfsTcpConnTot=0;
  $rpcBadAuthTot=$rpcBadClntTot=$rpcRetransTot=$rpcCredRefTot=0;

  if ($reportOstFlag)
  {
    $lustreReadOpsTot=$lustreReadKBytesTot=0;
    $lustreWriteOpsTot=$lustreWriteKBytesTot=0;
    for ($i=0; $i<$numBrwBuckets; $i++)
    {
      $lustreBufReadTot[$i]=$lustreBufWriteTot[$i]=0;
    }
  }
  $lustreCltDirtyHitsTot=$lustreCltDirtyMissTot=0;
  $lustreCltReadTot=$lustreCltReadKBTot=$lustreCltWriteTot=$lustreCltWriteKBTot=0;
  $lustreCltOpenTot=$lustreCltCloseTot=$lustreCltSeekTot=$lustreCltFsyncTot=0;
  $lustreCltSetattrTot=$lustreCltGetattrTot=0;
  $lustreCltRAPendingTot=$lustreCltRAHitsTot=$lustreCltRAMissesTot=0;
  $lustreCltRANotConTot=$lustreCltRAMisWinTot=0;
  $lustreCltRAReadDiscTot=$lustreCltRAZeroLenTot=$lustreCltRAZeroWinTot=0;
  $lustreCltRA2EofTot=$lustreCltRAHitMaxTot=$lustreCltRAFalGrabTot=0;
  $lustreCltRALckFailTot=$lustreCltRAWrongTot=0;
  
  for ($i=0; $i<$numBrwBuckets; $i++)
  {
    $lustreCltRpcReadTot[$i]=$lustreCltRpcWriteTot[$i]=0;
  }
  for ($i=0; $i<25; $i++)
  {
    $lusDiskReadsTot[$i]=$lusDiskWritesTot[$i]=0;
    $lusDiskReadBTot[$i]=$lusDiskWriteBTot[$i]=0;
  }

  $elanSendFailTot=$elanNeterrAtomicTot=$elanNeterrDmaTot=0;
  $elanRxTot=$elanRxKBTot=$elanTxTot=$elanTxKBTot=$elanErrors=0;
  $elanPutTot=$elanPutKBTot=$elanGetTot=$elanGetKBTot=0;
  $elanCompTot=$elanCompKBTot=0;

  $ibRxTot=$ibRxKBTot=$ibTxTot=$ibTxKBTot=$ibErrorsTotTot=0;

  $slabObjActTotal=$slabObjAllTotal=$slabSlabActTotal=$slabSlabAllTotal=0;
  $slabObjActTotalB=$slabObjAllTotalB=$slabSlabActTotalB=$slabSlabAllTotalB=0;
  $slabNumAct=$slabNumTot=0;
  $slabNumObjTot=$slabObjAvailTot=$slabUsedTot=$slabTotalTot=0;    # These are for slub

  # processes and environmentals don't get reported every interval so we need
  # to set a flag when they do.  Further, just in case some plugin wants to do its
  # during intervals 2 or 3, set those to 'print' when --showcolver
  $interval2Print=$interval3Print=(!$showColFlag) ? 0 : 1;

  # on older kernels not always set.
  $memInact=0;

  # Lustre is a whole different thing since the state of the system we're
  # monitoring change change with each interval.  Since this applies across
  # all types of output, let's just do it once.
  $reportCltFlag=$reportMdsFlag=$reportOstFlag=0;

  # if no -L, report based on system components
  # I would have thought this could have been done once, but now I'm
  # too scared to change it!
  if ($lustreSvcs eq '')
  {
    $reportCltFlag=1    if $CltFlag;
    $reportMdsFlag=1    if $MdsFlag;
    $reportOstFlag=1    if $OstFlag;
  }
  else
  {
    $reportCltFlag=1    if $lustreSvcs=~/c/i;
    $reportMdsFlag=1    if $lustreSvcs=~/m/i;
    $reportOstFlag=1    if $lustreSvcs=~/o/i;
  }

  $envFanIndex=$envTempIndex=$envFirstHeader=$envNewHeader=0;

  # Interval initialization for imported modules, noting we're passing the constants in
  # a hash that we only look at once.
  for (my $i=0; $i<$impNumMods; $i++) { &{$impInitInterval[$i]}($intSecs); }
}

# End of interval processing/printing, called BEFORE printing anything
sub intervalEnd
{
  my $seconds=shift;

  # Only for debugging and typically used with -d4, we want to see the /proc
  # fields as they're read but NOT process them
  return()    if $debug & 32;

  #    C h e c k    f o r    d e l e t e d    d i s k s

  # remove any disks that might have disappeared AND return their index to avail stack
  # NOTE - this and network checks that follow are IDENTICAL!!!
  if ($subsys=~/d/i && ($dskSeenCount<$dskSeenLast || $dskChangeFlag & 1))
  {
    # examine each disk in the set of current disks for who is missing this interval
    foreach my $disk (keys %disks)
    {
      my $seen=0;
      for (my $i=0; !$seen && $i<@dskSeen; $i++)
      {
        next    if !defined($dskSeen[$i]);    # index not in use
        if (defined($dskSeen[$disks{$disk}]))
        {
	  $seen=1;
	  last;
	}
      }

      if (!$seen)
      {
        $dskChangeFlag|=2;
	my $index=$disks{$disk};
	delete $disks{$disk};
	push @dskIndexAvail, $index;
	print "deleted disk $disk with index $index\n"    if $debug & 1;
      }
    }
  }
  $dskSeenLast=$dskSeenCount;

  #    C h e c k    f o r    d e l e t e d    n e t w o r k s

  # remove any networks that might have disappeared AND return their index to avail stack
  if ($subsys=~/n/i && ($netSeenCount<$netSeenLast || $netChangeFlag & 1))
  {
    # examine each network in the set of current network for who is missing this interval
    foreach my $network (keys %networks)
    {
      my $seen=0;
      for (my $i=0; !$seen && $i<@netSeen; $i++)
      {
        next    if !defined($netSeen[$i]);    # index not in use
        if (defined($netSeen[$networks{$network}]))
        {
          $seen=1;
          last;
        }
      }

      if (!$seen)
      {
        $netChangeFlag|=2;
        my $index=$networks{$network};
        delete $networks{$network};
        push @netIndexAvail, $index;
        print "deleted network $network with index $index\n"    if $debug & 1;
      }
    }
  }
  $netSeenLast=$netSeenCount;

  # we need to know how long the interval was, noting that when testing with -i0 we
  # can't divide by 0 and so set the interval to 1 to make it work even though the
  # numbers will be bogus.  NOTE in interactive mode, first pass through '$lastSecs'
  # is 0, but that's ok because we don't generate any output
  $intSecs= $seconds-$lastSecs[$rawPFlag];
  $intSecs=1            if $options=~/n/ || !$intSecs;
  $lastSecs[$rawPFlag]=$seconds;

  # for interval2, we need to calculate the length of the interval as well,
  # which is usually longer than the base one.  this is also the perfect
  # time to clean out process stale pids from the %procIndexes hash.  
  # NOTE - if no processes during first interval (--procfilt used) our first
  # intervalSecs will be 0 and the flt/sec test will blow up so make it 1.
  # NOTE2 - in some cases, currently when computing cpu%, we need to use
  # the 'real' value of interval2 even if reset to 1 by -on.
  if ($interval2Print)
  {
    cleanStaleTasks()               if $ZFlag && !$pidOnly;

    # note - $interval2SecsReal never normalized
    my $lastInt2Secs=$lastSecs[$rawPFlag]      if $lastInt2Secs==0;
    my $lastInterval=$seconds-$lastInt2Secs;
    $interval2Secs=$interval2SecsReal=($lastInterval!=0) ? $lastInterval : $interval2;
    $interval2Secs=$interval2SecsReal=1                if $options=~/n/ || !$interval2Secs;
    $lastInt2Secs=$seconds;
  }

  # This is sooo rare, but if a CPU goes off-line it can happen at any time and so we need
  # to check at the end of every interval, whether interactively or during playback.
  if ($subsys=~/c/)
  {
    $cpuDisabledFlag=($cpusEnabled!=$NumCpus) ? 1 : 0;
    $cpuDisabledMsg= ($cpuDisabledFlag) ? ': *** One or more CPUs disabled ***' : '';
    if ($cpuDisabledFlag)
    {
      # Since current stats never get updated for cpus that are offline and not in /proc/stat
      # we need to manaually force their current values to 0.
      for (my $i=0; $i<$NumCpus; $i++)    # in case cpu0 goes offline on its own?
      {
        $userP[$i]=$niceP[$i]=$sysP[$i]=$waitP[$i]=$irqP[$i]=$softP[$i]=$stealP[$i]=$idleP[$i]=0
	  if !$cpuEnabled[$i];
      }
    }
  }

  # some variables are derived from others before printing and we need to call at end of
  # each interval including the first so that the 'last' variables set correctly.  BUT if 
  # playing back a rawp file we don't want to derive anything because they're not used.
  derived()    if $rawPFlag==0;

  # Call import intervalEnd() BUT only if they have a callback defined
  for (my $i=0; $i<$impNumMods; $i++)
  { &{$impIntervalEnd[$i]}(\$header)    if defined(&{$impIntervalEnd[$i]});}

  # during interactive processing, the first interval only provides baseline data
  # and so never call print
  intervalPrint($seconds)           if $playback ne '' || $intFirstSeen;

  # need to reinitialize all relevant variables at end of each interval.
  initInterval();

  # No longer the first interval OR the first interval of the day
  $intFirstSeen=1;
  $newDayFlag=0;
}

sub dataAnalyze
{
  my $subsys=shift;
  my $line=  shift;
  my $i;

  # Only for debugging and typically used with -d4, we want to see the /proc
  # fields as they're read but NOT process them
  return()    if $debug & 32;

  # if running 'live' & non-flushed buffer or in some cases simply no data
  # as in the case of a diskless system, if no data to analyze, skip it
  chomp $line;
  ($type, $data)=split(/\s+/, $line, 2);
  return    if (!defined($data) || $data eq "");

  # Custom data analysis based on KEY which must be defined in custom module
  for (my $i=0; $i<$impNumMods; $i++)
  { 
    &{$impAnalyze[$i]}($type, \$data)    if $type=~/$impKey[$i]/;
  }

  #    P R O C E S S E S

  if ($type=~/^proc(T*):(\d+)/)
  {
   # Note that if 'T' appended, this is a thread.
   $threadFlag=($1 eq 'T') ? 1 : 0;
   $procPidNow=$2;

   if ($subsys=~/Z/)
   {
    # make sure we note this this interval has process data in it and is ready
    # to be reported.
    $interval2Print=1;

    # Whenever we see a new pid, we need to add to allocate a new index
    # and add it to the hash of indexes PLUS this is where we have to 
    # initialize the 'last' variables.
    if (!defined($procIndexes{$procPidNow}))
    {
      $i=$procIndexes{$procPidNow}=nextAvailProcIndex();
      $procMinFltLast[$i]=$procMajFltLast[$i]=0;
      $procUTimeLast[$i]=$procSTimeLast[$i]=$procCUTimeLast[$i]=$procCSTimeLast[$i]=0;
      $procRCharLast[$i]=$procWCharLast[$i]=$procSyscrLast[$i]=	$procSyscwLast[$i]=0;
      $procRBytesLast[$i]=$procWBytesLast[$i]=$procCancelLast[$i]=0;
      $procVCtxLast[$i]=$procNCtxLast[$i]=0;
      print "### new index $i allocated for $procPidNow\n"    if $debug & 256;
    }

    # note - %procSeen works just like %pidSeen, except to keep collection
    # and formatting separate, we need to keep these flags separate too,
    # expecially since in playback mode %pidSeen never gets set.
    $procSeen{$procPidNow}=1;
    $i=$procIndexes{$procPidNow};

    # Since the counters presented here are zero based, they're actually
    # the totals already and all we need to is calculate the intervals
    if ($data=~/^stat /)
    {
      # 'C' variables include the values for dead children
      # Note that incomplete records happen too often to bother logging
      $procPid[$i]=$procPidNow;  # don't need to pull out of string...
      $procThread[$i]=$threadFlag;
      ($procName[$i], $procState[$i], $procPpid[$i], 
       $procMinFltTot[$i], $procMajFltTot[$i], 
       $procUTimeTot[$i], $procSTimeTot[$i], 
       $procCUTimeTot[$i], $procCSTimeTot[$i], $procPri[$i], $procNice[$i], $procTCount[$i], $procSTTime[$i], $procCPU[$i])=
		(split(/ /, $data))[2,3,4,10,12,14,15,16,17,18,19,20,22,39];
      return    if !defined($procSTimeTot[$i]);  # check for incomplete

      # don't incude main process in thread count
      $procTCount[$i]--;

      if ($procOpts=~/c/)
      {
        $procUTimeTot[$i]+=$procCUTimeTot[$i];
        $procSTimeTot[$i]+=$procCSTimeTot[$i];
      }

      $procName[$i]=~s/[()]//g;  # proc names are wrapped in ()s
      $procPri[$i]="RT"    if $procPri[$i]<0 && $procOpts!~/R/;
      $procMinFlt[$i]=fix($procMinFltTot[$i]-$procMinFltLast[$i]);
      $procMajFlt[$i]=fix($procMajFltTot[$i]-$procMajFltLast[$i]);
      $procUTime[$i]= fix($procUTimeTot[$i]-$procUTimeLast[$i]);
      $procSTime[$i]= fix($procSTimeTot[$i]-$procSTimeLast[$i]);

      $procMinFltLast[$i]=$procMinFltTot[$i];
      $procMajFltLast[$i]=$procMajFltTot[$i];
      $procUTimeLast[$i]= $procUTimeTot[$i];
      $procSTimeLast[$i]= $procSTimeTot[$i];

      # non-root users will no longer have access to io stats for anyone other than themselves, so make 
      # sure 0s are printed instead of uninit vars.  this also means if collected by non-root but
      # played back by root, the data won't be there either!
      $procRKBC[$i]=$procWKBC[$i]=$procRSys[$i]=$procWSys[$i]=$procRKB[$i]=$procWKB[$i]=$procCKB[$i]=0;
    }

    # Handle the IO counters
    elsif ($data=~/^io (.*)/)
    {
      $data2=$1;

      # This might be easier to do in 7 separate 'if' blocks but
      # this keeps the code denser and may be easier to follow
      $procRChar=$1     if $data2=~/^rchar: (\d+)/;
      $procWChar=$1     if $data2=~/^wchar: (\d+)/;
      $procSyscr=$1     if $data2=~/^syscr: (\d+)/;
      $procSyscw=$1     if $data2=~/^syscw: (\d+)/;
      $procRBytes=$1    if $data2=~/^read_bytes: (\d+)/;
      $procWBytes=$1    if $data2=~/^write_bytes: (\d+)/;

      if ($data2=~/^cancelled_write_bytes: (\d+)/)
      {
        # CentOS V4 (and therefore must be true for some RHEL distros) 
        # doesn't include all counters so if one isn't set I'm going
        # to assume ALL aren't set
        $procRChar=$procWChar=$procSyscr=$procSyscw=0    if !defined($procRChar);

        $procCancel=$1;
	$procRKBC[$i]=fix($procRChar-$procRCharLast[$i])/1024;
  	$procWKBC[$i]=fix($procWChar-$procWCharLast[$i])/1024;
	$procRSys[$i]=fix($procSyscr-$procSyscrLast[$i]);
	$procWSys[$i]=fix($procSyscw-$procSyscwLast[$i]);
	$procRKB[$i]= fix($procRBytes-$procRBytesLast[$i])/1024;
	$procWKB[$i]= fix($procWBytes-$procWBytesLast[$i])/1024;
	$procCKB[$i]= fix($procCancel-$procCancelLast[$i])/1024;

	$procRCharLast[$i]=$procRChar;
	$procWCharLast[$i]=$procWChar;
	$procSyscrLast[$i]=$procSyscr;
	$procSyscwLast[$i]=$procSyscw;
	$procRBytesLast[$i]=$procRBytes;
	$procWBytesLast[$i]=$procWBytes;
        $procCancelLast[$i]=$procCancel;
      }
    }

    # if bad stat file skip the rest
    elsif (!defined($procSTimeTot[$i])) { }
    elsif ($data=~/^cmd (.*)/)          { $procCmd[$i]=$1; }
    elsif ($data=~/^VmPeak:\s+(\d+)/)   { $procVmPeak[$i]=$1; }
    elsif ($data=~/^VmSize:\s+(\d+)/)   { $procVmSize[$i]=$1; }
    elsif ($data=~/^VmLck:\s+(\d+)/)    { $procVmLck[$i]=$1; } 
    elsif ($data=~/^VmHWM:\s+(\d+)/)    { $procVmHWM[$i]=$1; }
    elsif ($data=~/^VmRSS:\s+(\d+)/)    { $procVmRSS[$i]=$1; }
    elsif ($data=~/^VmData:\s+(\d+)/)   { $procVmData[$i]=$1; }
    elsif ($data=~/^VmStk:\s+(\d+)/)    { $procVmStk[$i]=$1; }
    elsif ($data=~/^VmExe:\s+(\d+)/)    { $procVmExe[$i]=$1; }
    elsif ($data=~/^VmLib:\s+(\d+)/)    { $procVmLib[$i]=$1; }
    elsif ($data=~/^VmPTE:\s+(\d+)/)    { $procVmPTE[$i]=$1; }
    elsif ($data=~/^VmSwap:\s+(\d+)/)   { $procVmSwap[$i]=$1; }
    elsif ($data=~/^Tgid:\s+(\d+)/)     { $procTgid[$i]=$1; }
    elsif ($data=~/^Uid:\s+(\d+)/)
    { 
      $uid=$1;
      $procUser[$i]=(defined($UidSelector{$uid})) ? $UidSelector{$uid} : $uid;
    }
    elsif ($data=~/^vol.*:\s+(\d+)/)
    {
      my $procVCtx=$1;
      $procVCtx[$i]=$procVCtx-$procVCtxLast[$i];
      $procVCtxLast[$i]=$procVCtx;
    }
    elsif ($data=~/^nonv.*:\s+(\d+)/)
    {
      my $procNCtx=$1;
      $procNCtx[$i]=$procNCtx-$procNCtxLast[$i];
      $procNCtxLast[$i]=$procNCtx;
    }
   }
  }

  #    S L A B S

  # Note the trailing '$'.  This is because there is a Slab: in /proc/meminfo
  # Also note this handles both slab and slub
  elsif ($type=~/^Slab$/)
  {
   if ($subsys=~/y/i)
   {
    $slabDataFlag=1;

    # First comes /proc/slabinfo
    # this is a little complicated, but not too much as the order of the ||
    # is key.  The idea is that only in playback mode and then only if the
    # user specifies a list of slabs to look at do we ever execute
    # that ugly 'defined()' function.
    if ($slabinfoFlag &&
	 ($playback eq '' || $slabFilt eq '' ||
	    defined($slabProc{(split(/ /,$data))[0]})))
    {
      # make sure we note this this interval has process data in it and is ready
      # to be reported.
      $interval2Print=1;

      # in case slabs don't always appear in same order (new ones
      # dynamically added?), we'll index everything...
      $name=(split(/ /, $data))[0];
      $slabIndex{$name}=$slabIndexNext++    if !defined($slabIndex{$name});
      $i=$slabIndex{$name};
      $slabName[$i]=$name;

      # very rare (I hope), but if the number of slabs grew after we started, make
      # a note in message log and init the variable that got missed because of this.
      if ($i>=$NumSlabs)
      {
        $NumSlabs++;
        $slabObjActLast[$i]=$slabObjAllLast[$i]=0;
        $slabSlabActLast[$i]=$slabSlabAllLast[$i]=0;
        logmsg("W", "New slab created after logging started")    
      }

      # since these are NOT counters, the values are actually totals from which we
      # can derive changes from individual entries.
      if ($SlabVersion eq '1.1')
      {
        ($slabObjActTot[$i], $slabObjAllTot[$i], $slabObjSize[$i],
         $slabSlabActTot[$i], $slabSlabAllTot[$i], $slabPagesPerSlab[$i])=(split(/\s+/, $data))[1..6];
 	 $slabObjPerSlab[$i]=($slabSlabAllTot[$i]) ? $slabObjAllTot[$i]/$slabSlabAllTot[$i] : 0;
      }
      elsif ($SlabVersion=~/^2/)
      {
        ($slabObjActTot[$i], $slabObjAllTot[$i], $slabObjSize[$i], 
         $slabObjPerSlab[$i], $slabPagesPerSlab[$i],
         $slabSlabActTot[$i], $slabSlabAllTot[$i])=(split(/\s+/, $data))[1..5,13,14];
      }

      # Total Sizes of objects and slabs
      $slabObjActTotB[$i]=$slabObjActTot[$i]*$slabObjSize[$i];
      $slabObjAllTotB[$i]=$slabObjAllTot[$i]*$slabObjSize[$i];
      $slabSlabActTotB[$i]=$slabSlabActTot[$i]*$slabPagesPerSlab[$i]*$PageSize;
      $slabSlabAllTotB[$i]=$slabSlabAllTot[$i]*$slabPagesPerSlab[$i]*$PageSize;

      $slabObjAct[$i]= $slabObjActTot[$i]- $slabObjActLast[$i];
      $slabObjAll[$i]= $slabObjAllTot[$i]- $slabObjAllLast[$i];
      $slabSlabAct[$i]=$slabSlabActTot[$i]-$slabSlabActLast[$i];
      $slabSlabAll[$i]=$slabSlabAllTot[$i]-$slabSlabAllLast[$i];

      $slabObjActLast[$i]= $slabObjActTot[$i];
      $slabObjAllLast[$i]= $slabObjAllTot[$i];
      $slabSlabActLast[$i]=$slabSlabActTot[$i];
      $slabSlabAllLast[$i]=$slabSlabAllTot[$i];

      # Changes in total allocation since last one, noting on first pass it's always 0
      my $slabTotMemNow=$slabSlabAllTotB[$i];
      my $slabTotMemLast=(defined($slabTotalMemLast{$name})) ? $slabTotalMemLast{$name} : $slabTotMemNow;
      $slabTotMemChg[$i]=$slabTotMemNow-$slabTotMemLast;
      $slabTotMemPct[$i]=($slabTotMemLast!=0) ? 100*$slabTotMemChg[$i]/$slabTotMemLast : 0;
      $slabTotalMemLast{$name}=$slabTotMemNow;

      # if --slabopt S, only count slabs whose objects or sizes have changed
      # since last interval.
      # note -- this is only if !S and the slabs themselves change
      if ($slabOpts!~/S/ || $slabSlabAct[$i]!=0 || $slabSlabAll[$i]!=0)
      {
        $slabObjActTotal+=  $slabObjActTot[$i];
        $slabObjAllTotal+=  $slabObjAllTot[$i];
        $slabObjActTotalB+= $slabObjActTot[$i]*$slabObjSize[$i];
        $slabObjAllTotalB+= $slabObjAllTot[$i]*$slabObjSize[$i];
        $slabSlabActTotal+= $slabSlabActTot[$i];
        $slabSlabAllTotal+= $slabSlabAllTot[$i];
        $slabSlabActTotalB+=$slabSlabActTot[$i]*$slabPagesPerSlab[$i]*$PageSize;
        $slabSlabAllTotalB+=$slabSlabAllTot[$i]*$slabPagesPerSlab[$i]*$PageSize;
        $slabNumAct++       if $slabSlabAllTot[$i];
        $slabNumTot++;
      }
    }
    else
    {
      # Note as efficient as if..then..elsif..elsif... but a lot more readable
      # and more important, no appreciable difference in processing time
      my ($slabname, $datatype, $value)=split(/\s+/, $data);

      $slabdata{$slabname}->{objsize}=$value     if $datatype=~/^object_/;    # object_size
      $slabdata{$slabname}->{slabsize}=$value    if $datatype=~/^slab_/;      # slab_size  
      $slabdata{$slabname}->{order}=$value       if $datatype=~/^or/;         # order
      $slabdata{$slabname}->{objper}=$value      if $datatype=~/^objs/;       # objs_per_slab
      $slabdata{$slabname}->{objects}=$value     if $datatype=~/^objects/;

      # This is the second of the ('objects','slabs') tuple
      if ($datatype=~/^slabs/)
      { 
        my $numSlabs=$slabdata{$slabname}->{slabs}=$value;

        $interval2Print=1;
        $slabdata{$slabname}->{avail}=$slabdata{$slabname}->{objper}*$numSlabs;

	$slabNumTot+=     $numSlabs;
        $slabObjAvailTot+=$slabdata{$slabname}->{objper}*$numSlabs;
        $slabNumObjTot+=  $slabdata{$slabname}->{objects};
        $slabUsedTot+=    $slabdata{$slabname}->{used}=$slabdata{$slabname}->{slabsize}*$slabdata{$slabname}->{objects};
        $slabTotalTot+=   $slabdata{$slabname}->{total}=$value*($PageSize<<$slabdata{$slabname}->{order});

        # Changes in total allocation since last one, noting on first pass it's always 0
        my $slabTotMemNow=$slabdata{$slabname}->{total};
        my $slabTotMemLast=(defined($slabTotalMemLast{$slabname})) ? $slabTotalMemLast{$slabname} : $slabTotMemNow;
        $slabdata{$slabname}->{memchg}=$slabTotMemNow-$slabTotMemLast;
        $slabdata{$slabname}->{mempct}=($slabTotMemLast!=0) ? 100*$slabdata{$slabname}->{memchg}/$slabTotMemLast : 0;
        $slabTotalMemLast{$slabname}=$slabTotMemNow;
      }
    }
   }
  }

  elsif ($subsys=~/b/i && $type=~/^buddy/)
  {
    my @fields=split(/\s+/, $data);
    $buddyNode[$budIndex]=$fields[1];
    $buddyZone[$budIndex]=$fields[3];
    $buddyNode[$budIndex]=~s/,$//;

    for (my $i=0; $i<11; $i++)
    {  
      $buddyInfo[$budIndex][$i]=$fields[$i+4];
      $buddyInfoTot[$i]+=$fields[$i+4];
    }
    $budIndex++;
  }

  # if user requested -sd, we had to force -sc so we can get 'jiffies'
  # 2.6 disk stats may also need cpu to get jiffies for micro calculations
  elsif ($subsys=~/c|d/i && $type=~/^cpu/)
  {
    $type=~/^cpu(\d*)/;   # can't do above because second "~=" kills $1
    $cpuIndex=($1 ne "") ? $1 : $NumCpus;    # only happens in pre 1.7.4
    $cpuEnabled[$cpuIndex]=1;
    $cpusEnabled++    if $cpuIndex != $NumCpus;
    ($userNow, $niceNow, $sysNow, $idleNow, $waitNow, $irqNow, $softNow, $stealNow)=split(/\s+/, $data);
    $stealNow=0                              if !defined($stealNow);
    if (!defined($idleNow))
    {
      incomplete("CPU", $lastSecs[$rawPFlag]);
      return;
    }

    # we don't care about saving raw seconds other than in 'last' variable
    # Also note that the total number of jiffies may be needed elsewhere (-s p)
    # "wait" doesn't happen unti 2.5, but might as well get ready now.
    $user= fix($userNow-$userLast[$cpuIndex]);
    $nice= fix($niceNow-$niceLast[$cpuIndex]);
    $sys=  fix($sysNow-$sysLast[$cpuIndex]);
    $idle= fix($idleNow-$idleLast[$cpuIndex]);
    $wait= fix($waitNow-$waitLast[$cpuIndex]);
    $irq=  fix($irqNow-$irqLast[$cpuIndex]);
    $soft= fix($softNow-$softLast[$cpuIndex]);
    $steal=fix($stealNow-$stealLast[$cpuIndex]);
    $total=$user+$nice+$sys+$idle+$wait+$irq+$soft+$steal;
    $total=100    if $options=~/n/;    # when normalizing, this cancels '100*'
    $total=1      if !$total;          # has seen to be 0 when interval=0;

    # For disk detail QueueLength and Util we need an accurate interval time when
    # no HiRes timer, and this is a pretty cool way to do it
    $microInterval=$total/$NumCpus    if !$hiResFlag && $cpuIndex==$NumCpus;

    $userP[$cpuIndex]= 100*$user/$total;
    $niceP[$cpuIndex]= 100*$nice/$total;
    $sysP[$cpuIndex]=  100*$sys/$total;
    $idleP[$cpuIndex]= 100*$idle/$total;
    $waitP[$cpuIndex]= 100*$wait/$total;
    $irqP[$cpuIndex]=  100*$irq/$total;
    $softP[$cpuIndex]= 100*$soft/$total;
    $stealP[$cpuIndex]=100*$steal/$total;
    $totlP[$cpuIndex]=$userP[$cpuIndex]+$niceP[$cpuIndex]+
		      $sysP[$cpuIndex]+$irqP[$cpuIndex]+
		      $softP[$cpuIndex]+$stealP[$cpuIndex];

    $userLast[$cpuIndex]= $userNow;
    $niceLast[$cpuIndex]= $niceNow;
    $sysLast[$cpuIndex]=  $sysNow;
    $idleLast[$cpuIndex]= $idleNow;
    $waitLast[$cpuIndex]= $waitNow;
    $irqLast[$cpuIndex]=  $irqNow;
    $softLast[$cpuIndex]= $softNow;
    $stealLast[$cpuIndex]=$stealNow;
  }

  elsif ($subsys=~/c/ && $type=~/^load/)
  {
    ($loadAvg1, $loadAvg5, $loadAvg15, $loadProcs)=split(/\s+/, $data);
    if (!defined($loadProcs))
    {
      incomplete("LOAD", $lastSecs[$rawPFlag]);
      return;
    }

    ($loadRun, $loadQue)=split(/\//, $loadProcs);
    $loadRun--;   # never count ourself!
  }

  elsif ($subsys=~/c/ && $type=~/^procs/)
  {
    # never include ourselves in count of running processes
    $data=(split(/\s+/, $data))[0];
    $procsRun=$data-1     if $type=~/^procs_r/;
    $procsBlock=$data     if $type=~/^procs_b/;
  }

  elsif ($subsys=~/j/i && $type eq 'int')
  {
    # Note that leading space(s) were removed when we split line above
    my ($type, @vals)=split(/\s+/, $data, $cpusEnabled+2);

    # If the number of enabled CPUs different than the total, we'll have one
    # or more missing columns in /proc/interrupts so do a right shift

    if ($cpusEnabled!=$NumCpus)
    {
      # First move the description up to the last position.
      $vals[$NumCpus]=$vals[$cpusEnabled];

      # Now right shift all the data into the correct CPU slot
      my $index=$NumCpus-1;
      for (my $i=$cpusEnabled-1; $i>=0; $i--)
      {
        # if this CPU disabled, just set its count to 0 and move on to next one
        $vals[$index--]=0    if !$cpuEnabled[$index];
        $vals[$index]=$vals[$i];
        $index--;
      }
    }

    #    I n i t i a l i z e    ' l a s t '    v a l u e s

    # Since I'm not sure if new entries can show up dynamically AND because we
    # have to find non-numeric entries so we can initialize them, let's just
    # always do our initialization dynamically instead of in initRecord().
    $type=~s/:$//;
    my $typeSort=($type=~/^\d/) ? sprintf("%03d", $type) : $type;

    if (!defined($intrptType{$typeSort}))
    {
      $intrptType{$typeSort}=1;
      if ($type!~/ERR|MIS/)
      {
	# Pull devicename/time BUT note on earlier kernels for non-numeric types
        # these fields aren't always filled in
        my ($intType, $intDevices)=split(/\s+/, $vals[$NumCpus], 2);
	$intType=''       if !defined($intType);
        $intDevices=''    if !defined($intDevices);

        chomp $intDevices;
        $intName{$typeSort}=sprintf("%-15s %s", $intType, $intDevices);
        if ($type!~/^\d/)
        {
          $intName{$typeSort}="$intType $intDevices";
          $intName{$typeSort}=~s/ interrupts$//;
        }
      }

      if ($type=~/^\d/)
      {
        # We use array for numeric values and a hash for strings as the array
        # access is a little faster expecially as the number of entries grows
        # We're also reformatting the modifier so the devices line up...
        for (my $i=0; $i<$NumCpus; $i++)
        {
          $intrptLast[$type]->[$i]=0;
        }
      }
      else
      {
        for (my $i=0; $i<$NumCpus; $i++)
        {
          $intrptLast{$type}->[$i]=0;
        }
      }
    }

    #    M a t h    h a p p e n s    h e r e

    for (my $i=0; $i<$NumCpus; $i++)
    {
      # If a CPU is disabled, just set it's count to zero.
      if ($subsys=~/c/i && !$cpuEnabled[$i])
      {
        $intrpt[$type]->[$i]=0    if $type=~/^\d/;
        $intrpt{$type}->[$i]=0    if $type!~/^\d/;
	next;
      }

      if ($type=~/^\d/)
      {
        $intrpt[$type]->[$i]=$vals[$i]-$intrptLast[$type]->[$i];
        $intrptLast[$type]->[$i]=$vals[$i];
        $intrptTot[$i]+=$intrpt[$type]->[$i];
      }

      # Not sure if other types that only hit cpu0
      elsif ($i==0 || ($type ne 'ERR' && $type ne 'MIS'))
      {
        $intrpt{$type}->[$i]=$vals[$i]-$intrptLast{$type}->[$i];
        $intrptLast{$type}->[$i]=$vals[$i];
        $intrptTot[$i]+=$intrpt{$type}->[$i];
      }
    }
  }

  elsif ($subsys=~/l/i && $type=~/OST_(\d+)/)
  {
    chomp $data;
    $index=$1;
    ($lustreType, $lustreOps, $lustreBytes)=(split(/\s+/, $data))[0,1,6];
    $index=$OstMap[$index]    if $playback ne '';   # handles remapping is OSTs change position
    #print "IDX: $index, $lustreType, $lustreOps, $lustreBytes\n";

    $lustreBytes=0    if $lustreOps==0;
    if ($lustreType=~/read/)
    {
      $lustreReadOpsNow=            $lustreOps;
      $lustreReadKBytesNow=         $lustreBytes/$OneKB;

      $lustreReadOps[$index]=       fix($lustreReadOpsNow-$lustreReadOpsLast[$index]);
      $lustreReadKBytes[$index]=    fix($lustreReadKBytesNow-$lustreReadKBytesLast[$index]);
      $lustreReadOpsLast[$index]=   $lustreReadOpsNow;
      $lustreReadKBytesLast[$index]=$lustreReadKBytesNow;
      $lustreReadOpsTot+=           $lustreReadOps[$index];
      $lustreReadKBytesTot+=        $lustreReadKBytes[$index];
    }
    else
    {
      $lustreWriteOpsNow=            $lustreOps;
      $lustreWriteKBytesNow=         $lustreBytes/$OneKB;
      $lustreWriteOps[$index]=       fix($lustreWriteOpsNow-$lustreWriteOpsLast[$index]);
      $lustreWriteKBytes[$index]=    fix($lustreWriteKBytesNow-$lustreWriteKBytesLast[$index]);
      $lustreWriteOpsLast[$index]=   $lustreWriteOpsNow;
      $lustreWriteKBytesLast[$index]=$lustreWriteKBytesNow;
      $lustreWriteOpsTot+=           $lustreWriteOps[$index];
      $lustreWriteKBytesTot+=        $lustreWriteKBytes[$index];
    }
  }

  elsif ($subsys=~/l/i && $type=~/OST-b_(\d+):(\d+)/)
  {
    chomp $data;
    $index=$1;
    $bufNum=$2;
    ($lustreBufReadNow, $lustreBufWriteNow)=(split(/\s+/, $data))[1,5];
    $index=$OstMap[$index]    if $playback ne '';

    $lustreBufRead[$index][$bufNum]=fix($lustreBufReadNow-$lustreBufReadLast[$index][$bufNum]);
    $lustreBufWrite[$index][$bufNum]=fix($lustreBufWriteNow-$lustreBufWriteLast[$index][$bufNum]);

    $lustreBufReadTot[$bufNum]+=$lustreBufRead[$index][$bufNum];
    $lustreBufWriteTot[$bufNum]+=$lustreBufWrite[$index][$bufNum];

    $lustreBufReadLast[$index][$bufNum]= $lustreBufReadNow;
    $lustreBufWriteLast[$index][$bufNum]=$lustreBufWriteNow;
  }

  elsif ($subsys=~/l/ && $type=~/MDS/)
  {
    chomp $data;
    ($name, $value)=(split(/\s+/, $data))[0,1];
    # if we ever do mds detail, this goes here!
    #$index=$MdsMap[$index]    if $playback ne '';

    if ($name=~/^mds_getattr$/)
    {
      $lustreMdsGetattr=fix($value-$lustreMdsGetattrLast);
      $lustreMdsGetattrLast=$value;
    }
    elsif ($name=~/^mds_getattr_lock/)
    {
      $lustreMdsGetattrLock=fix($value-$lustreMdsGetattrLockLast);
      $lustreMdsGetattrLockLast=$value;
    }
    elsif ($name=~/^mds_statfs/)
    {
      $lustreMdsStatfs=fix($value-$lustreMdsStatfsLast);
      $lustreMdsStatfsLast=$value;
    }
    elsif ($name=~/^mds_getxattr/)
    {
      $lustreMdsGetxattr=fix($value-$lustreMdsGetxattrLast);
      $lustreMdsGetxattrLast=$value;
    }
    elsif ($name=~/^mds_setxattr/)
    {
      $lustreMdsSetxattr=fix($value-$lustreMdsSetxattrLast);
      $lustreMdsSetxattrLast=$value;
    }
    elsif ($name=~/^mds_sync/)
    {
      $lustreMdsSync=fix($value-$lustreMdsSyncLast);
      $lustreMdsSyncLast=$value;
    } 
    elsif ($name=~/^mds_connect/)
    {
      $lustreMdsConnect=fix($value-$lustreMdsConnectLast);
      $lustreMdsConnectLast=$value;
    } 
    elsif ($name=~/^mds_disconnect/)
    {
      $lustreMdsDisconnect=fix($value-$lustreMdsDisconnectLast);
      $lustreMdsDisconnectLast=$value;
    } 
    elsif ($name=~/^mds_reint$/)
    {
      $lustreMdsReint=fix($value-$lustreMdsReintLast);
      $lustreMdsReintLast=$value;
    }
    # These 5 were added in 1.6.5.1 and are mutually exclusive with mds_reint
    elsif ($name=~/^mds_reint_create/)
    {
      $lustreMdsReintCreate=fix($value-$lustreMdsReintCreateLast);
      $lustreMdsReintCreateLast=$value;
    }
    elsif ($name=~/^mds_reint_link/)
    {
      $lustreMdsReintLink=fix($value-$lustreMdsReintLinkLast);
      $lustreMdsReintLinkLast=$value;
    }
    elsif ($name=~/^mds_reint_setattr/)
    {
      $lustreMdsReintSetattr=fix($value-$lustreMdsReintSetattrLast);
      $lustreMdsReintSetattrLast=$value;
    }
    elsif ($name=~/^mds_reint_rename/)
    {
      $lustreMdsReintRename=fix($value-$lustreMdsReintRenameLast);
      $lustreMdsReintRenameLast=$value;
    }
    elsif ($name=~/^mds_reint_unlink/)
    {
      $lustreMdsReintUnlink=fix($value-$lustreMdsReintUnlinkLast);
      $lustreMdsReintUnlinkLast=$value;
    }
  }

  elsif ($subsys=~/l/i && $type=~/LLITE:(\d+)/)
  {
    $fs=$1;
    chomp $data;
    ($name, $ops, $value)=(split(/\s+/, $data))[0,1,6];
    $fs=$CltFSMap[$fs]    if $playback ne '';

    if ($name=~/dirty_pages_hits/)
    {
      $lustreCltDirtyHits[$fs]=fix($ops-$lustreCltDirtyHitsLast[$fs]);
      $lustreCltDirtyHitsLast[$fs]=$ops;
      $lustreCltDirtyHitsTot+=$lustreCltDirtyHits[$fs];
    }
    elsif ($name=~/dirty_pages_misses/)
    {
      $lustreCltDirtyMiss[$fs]=fix($ops-$lustreCltDirtyMissLast[$fs]);
      $lustreCltDirtyMissLast[$fs]=$ops;
      $lustreCltDirtyMissTot+=$lustreCltDirtyMiss[$fs];
    }
    elsif ($name=~/read/)
    {

      # if brand new fs and no I/0, this field isn't defined.
      $value=0    if !defined($value);
      $lustreCltRead[$fs]=fix($ops-$lustreCltReadLast[$fs]);
      $lustreCltReadLast[$fs]=$ops;
      $lustreCltReadTot+=$lustreCltRead[$fs];
      $lustreCltReadKB[$fs]=fix(($value-$lustreCltReadKBLast[$fs])/$OneKB);
      $lustreCltReadKBLast[$fs]=$value;
      $lustreCltReadKBTot+=$lustreCltReadKB[$fs];
    }
    elsif ($name=~/write/)
    {
      $value=0    if !defined($value);    # same as 'read'
      $lustreCltWrite[$fs]=fix($ops-$lustreCltWriteLast[$fs]);
      $lustreCltWriteLast[$fs]=$ops;
      $lustreCltWriteTot+=$lustreCltWrite[$fs];
      $lustreCltWriteKB[$fs]=fix(($value-$lustreCltWriteKBLast[$fs])/$OneKB);
      $lustreCltWriteKBLast[$fs]=$value;
      $lustreCltWriteKBTot+=$lustreCltWriteKB[$fs];
    }
    elsif ($name=~/open/)
    {
      $lustreCltOpen[$fs]=fix($ops-$lustreCltOpenLast[$fs]);
      $lustreCltOpenLast[$fs]=$ops;
      $lustreCltOpenTot+=$lustreCltOpen[$fs];
    }
    elsif ($name=~/close/)
    {
      $lustreCltClose[$fs]=fix($ops-$lustreCltCloseLast[$fs]);
      $lustreCltCloseLast[$fs]=$ops;
      $lustreCltCloseTot+=$lustreCltClose[$fs];
    }
    elsif ($name=~/seek/)
    {
      $lustreCltSeek[$fs]=fix($ops-$lustreCltSeekLast[$fs]);
      $lustreCltSeekLast[$fs]=$ops;
      $lustreCltSeekTot+=$lustreCltSeek[$fs];
    }
    elsif ($name=~/fsync/)
    {
      $lustreCltFsync[$fs]=fix($ops-$lustreCltFsyncLast[$fs]);
      $lustreCltFsyncLast[$fs]=$ops;
      $lustreCltFsyncTot+=$lustreCltFsync[$fs];
    }
    elsif ($name=~/setattr/)
    {
      $lustreCltSetattr[$fs]=fix($ops-$lustreCltSetattrLast[$fs]);
      $lustreCltSetattrLast[$fs]=$ops;
      $lustreCltSetattrTot+=$lustreCltSetattr[$fs];
    }
    elsif ($name=~/getattr/)
    {
      $lustreCltGetattr[$fs]=fix($ops-$lustreCltGetattrLast[$fs]);
      $lustreCltGetattrLast[$fs]=$ops;
      $lustreCltGetattrTot+=$lustreCltGetattr[$fs];
    }
  }
  elsif ($subsys=~/l/i && $type=~/LLITE_RA:(\d+)/)
  {
    $fs=$1;
    chomp $data;
    $fs=$CltFSMap[$fs]    if $playback ne '';

    if ($data=~/^pending.* (\d+)/)
    {
      # This is NOT a counter but a meter
      $ops=$1;
      $lustreCltRAPending[$fs]=$ops;
      $lustreCltRAPendingTot+=$lustreCltRAPending[$fs];
    }
    elsif ($data=~/^hits.* (\d+)/)
    {
      $ops=$1;
      $lustreCltRAHits[$fs]=fix($ops-$lustreCltRAHitsLast[$fs]);
      $lustreCltRAHitsLast[$fs]=$ops;
      $lustreCltRAHitsTot+=$lustreCltRAHits[$fs];
    }
    elsif ($data=~/^misses.* (\d+)/)
    {
      $ops=$1;
      $lustreCltRAMisses[$fs]=fix($ops-$lustreCltRAMissesLast[$fs]);
      $lustreCltRAMissesLast[$fs]=$ops;
      $lustreCltRAMissesTot+=$lustreCltRAMisses[$fs];
    }
    elsif ($data=~/^readpage.* (\d+)/)
    {
      $ops=$1;
      $lustreCltRANotCon[$fs]=fix($ops-$lustreCltRANotConLast[$fs]);
      $lustreCltRANotConLast[$fs]=$ops;
      $lustreCltRANotConTot+=$lustreCltRANotCon[$fs];
    }
    elsif ($data=~/^miss inside.* (\d+)/)
    {
      $ops=$1;
      $lustreCltRAMisWin[$fs]=fix($ops-$lustreCltRAMisWinLast[$fs]);
      $lustreCltRAMisWinLast[$fs]=$ops;
      $lustreCltRAMisWinTot+=$lustreCltRAMisWin[$fs];
    }
    elsif ($data=~/^failed grab.* (\d+)/)
    {
      $ops=$1;
      $lustreCltRAFalGrab[$fs]=fix($ops-$lustreCltRAFalGrabLast[$fs]);
      $lustreCltRAFalGrabLast[$fs]=$ops;
      $lustreCltRAFalGrabTot+=$lustreCltRAFalGrab[$fs];
    }
    elsif ($data=~/^failed lock.* (\d+)/)
    {
      $ops=$1;
      $lustreCltRALckFail[$fs]=fix($ops-$lustreCltRALckFailLast[$fs]);
      $lustreCltRALckFailLast[$fs]=$ops;
      $lustreCltRALckFailTot+=$lustreCltRALckFail[$fs];
    }
    elsif ($data=~/^read but.* (\d+)/)
    {
      $ops=$1;
      $lustreCltRAReadDisc[$fs]=fix($ops-$lustreCltRAReadDiscLast[$fs]);
      $lustreCltRAReadDiscLast[$fs]=$ops;
      $lustreCltRAReadDiscTot+=$lustreCltRAReadDisc[$fs];
    }
    elsif ($data=~/^zero length.* (\d+)/)
    {
      $ops=$1;
      $lustreCltRAZeroLen[$fs]=fix($ops-$lustreCltRAZeroLenLast[$fs]);
      $lustreCltRAZeroLenPLast[$fs]=$ops;
      $lustreCltRAZeroLenTot+=$lustreCltRAZeroLen[$fs];
    }
    elsif ($data=~/^zero size.* (\d+)/)
    {
      $ops=$1;
      $lustreCltRAZeroWin[$fs]=fix($ops-$lustreCltRAZeroWinLast[$fs]);
      $lustreCltRAZeroWinLast[$fs]=$ops;
      $lustreCltRAZeroWinTot+=$lustreCltRAZeroWin[$fs];
    }
    elsif ($data=~/^read-ahead.* (\d+)/)
    {
      $ops=$1;
      $lustreCltRA2Eof[$fs]=fix($ops-$lustreCltRA2EofLast[$fs]);
      $lustreCltRA2EofLast[$fs]=$ops;
      $lustreCltRA2EofTot+=$lustreCltRA2Eof[$fs];
    }
    elsif ($data=~/^hit max.* (\d+)/)
    {
      $ops=$1;
      $lustreCltRAHitMax[$fs]=fix($ops-$lustreCltRAHitMaxLast[$fs]);
      $lustreCltRAHitMaxLast[$fs]=$ops;
      $lustreCltRAHitMaxTot+=$lustreCltRAHitMax[$fs];
    }
    elsif ($data=~/^wrong.* (\d+)/)
    {
      $ops=$1;
      $lustreCltRAWrong[$fs]=fix($ops-$lustreCltRAWrongLast[$fs]);
      $lustreCltRAWrong[$fs]=$ops;
      $lustreCltRAWrongTot+=$lustreCltRAWrong[$fs];
    }
  }

  elsif ($subsys=~/l/i && $type=~/LLITE_RPC:(\d+):(\d+)/)
  {
    chomp $data;
    $index=$1;
    $bufNum=$2;

    ($lustreCltRpcReadNow, $lustreCltRpcWriteNow)=(split(/\s+/, $data))[1,5];
    $index=$CltOstMap[$index]    if $playback ne '';

    $lustreCltRpcRead[$index][$bufNum]= fix($lustreCltRpcReadNow-$lustreCltRpcReadLast[$index][$bufNum]);
    $lustreCltRpcWrite[$index][$bufNum]=fix($lustreCltRpcWriteNow-$lustreCltRpcWriteLast[$index][$bufNum]);

    $lustreCltRpcReadTot[$bufNum]+= $lustreCltRpcRead[$index][$bufNum];
    $lustreCltRpcWriteTot[$bufNum]+=$lustreCltRpcWrite[$index][$bufNum];

    $lustreCltRpcReadLast[$index][$bufNum]= $lustreCltRpcReadNow;
    $lustreCltRpcWriteLast[$index][$bufNum]=$lustreCltRpcWriteNow;
  }

  elsif ($subsys=~/l/i && $type=~/LLDET:(\d+)/)
  {
    $ost=$1;
    chomp $data;
    ($name, $ops, $value)=(split(/\s+/, $data))[0,1,6];
    $ost=$CltOstMap[$ost]    if $playback ne '';

    if ($name=~/^read_bytes|ost_r/)
    {
      $lustreCltLunRead[$ost]=fix($ops-$lustreCltLunReadLast[$ost]);
      $lustreCltLunReadLast[$ost]=$ops;
      if (defined($value))  # not always defined
      {
        $lustreCltLunReadKB[$ost]=fix(($value-$lustreCltLunReadKBLast[$ost])/$OneKB);
        $lustreCltLunReadKBLast[$ost]=$value;
      }
    }
    elsif ($name=~/^write_bytes|ost_w/)
    {
      $lustreCltLunWrite[$ost]=fix($ops-$lustreCltLunWriteLast[$ost]);
      $lustreCltLunWriteLast[$ost]=$ops;
      if (defined($value))  # not always defined
      {
        $lustreCltLunWriteKB[$ost]=(fix($value-$lustreCltLunWriteKBLast[$ost])/$OneKB);
        $lustreCltLunWriteKBLast[$ost]=$value;
      }
    }
  }

  # disk stats apply to both MDS and OSTs
  elsif ($subsys=~/l/i && $type=~/LUS-d_(\d+):(\d+)/)
  {
    $lusDisk=$1;
    $bufNum= $2;

    # The units of 'readB/writeB' are number of 512 byte blocks
    # in case partial table [rare], make sure totals go in last bucket.
    chomp $data;
    ($size, $reads, $readB, $writes, $writeB)=split(/\s+/, $data);
    $bufNum=$LusMaxIndex    if $size=~/^total/;

    # Numbers for individual disks
    $lusDiskReads[$lusDisk][$bufNum]= fix($reads-$lusDiskReadsLast[$lusDisk][$bufNum]);
    $lusDiskReadB[$lusDisk][$bufNum]= fix($readB-$lusDiskReadBLast[$lusDisk][$bufNum]);
    $lusDiskWrites[$lusDisk][$bufNum]=fix($writes-$lusDiskWritesLast[$lusDisk][$bufNum]);
    $lusDiskWriteB[$lusDisk][$bufNum]=fix($writeB-$lusDiskWriteBLast[$lusDisk][$bufNum]);
    #print "BEF DISKTOT[$bufNum]  R: $lusDiskReadsTot[$bufNum]  W: $lusDiskWritesTot[$bufNum]\n";

    # Numbers for ALL disks
    $lusDiskReadsTot[$bufNum]+= $lusDiskReads[$lusDisk][$bufNum];
    $lusDiskReadBTot[$bufNum]+= $lusDiskReadB[$lusDisk][$bufNum];
    $lusDiskWritesTot[$bufNum]+=$lusDiskWrites[$lusDisk][$bufNum];
    $lusDiskWriteBTot[$bufNum]+=$lusDiskWriteB[$lusDisk][$bufNum];
    #print "AFT DISKTOT[$bufNum]  R: $lusDiskReadsTot[$bufNum]  W: $lusDiskWritesTot[$bufNum]\n";

    $lusDiskReadsLast[$lusDisk][$bufNum]= $reads;
    $lusDiskReadBLast[$lusDisk][$bufNum]= $readB;
    $lusDiskWritesLast[$lusDisk][$bufNum]=$writes;
    $lusDiskWriteBLast[$lusDisk][$bufNum]=$writeB;
    #print "DISK[$lusDisk][$bufNum]  R: $lusDiskReads[$lusDisk][$bufNum]  W: $lusDiskWrites[$lusDisk][$bufNum]\n";
  }

  elsif ($subsys=~/c/ && $type=~/^intr/)
  {
    $intrptNow=$data;
    $intrpt=fix($intrptNow-$intrptLast);
    $intrptLast=$intrptNow;
  }

  elsif ($subsys=~/c/ && $type=~/^ctx/)
  {
    $ctxtNow=$data;
    $ctxt=fix($ctxtNow-$ctxtLast);
    $ctxtLast=$ctxtNow;
  }

  elsif ($subsys=~/c/ && $type=~/^proce/)
  {
    $procNow=$data;
    $proc=fix($procNow-$procLast);
    $procLast=$procNow;
  }

  elsif ($subsys=~/E/ && $type=~/^ipmi/)
  {
    $interval3Print=1;
    my @fields=split(/,/, $data);

    # This very first set removes any entries that are to be ignored, even if valid
    for (my $i=0; $i<scalar(@{$ipmiFile->{ignore}}); $i++)
    {
      my $f1=$ipmiFile->{ignore}->[$i]->{f1};
      if ($data=~/$f1/)
      {
        print "Ignore: $data\n"    if $envDebug;
	return;
      }
    }

    # These are applied BEFORE the pattern match below
    print "$data\n"    if $envDebug;
    my $premap=$fields[0];
    $fields[0]=~s/\.|\///g;    # get rid of any '.'s or '/'s
    for (my $i=0; $i<scalar(@{$ipmiFile->{pre}}); $i++)
    {
      my $f1=$ipmiFile->{pre}->[$i]->{f1};
      my $f2=$ipmiFile->{pre}->[$i]->{f2};
      print "/$f1/$f2/\n"    if $envDebug;

      # No need paying the price of an eval if not symbols to interpret
      if ($f2!~/\$/)
      {
	$fields[0]=~s/$f1/$f2/;
      }
      else
      {
	eval "\$fields[0]=~s/$f1/$f2/";
      }
      print "  Pre-Remapped '$premap' to '$fields[0]'\n"
	    if $premap ne $fields[0] && $envDebug;
    }

    # matches: Virtual Fan | Fan n | Fans | xxx FANn | Power Meter
    # Not really sure why I need the '\s*' but it won't work without it!
    if ($fields[0]=~/^(.*)(fan.*?|temp.*?|power meter.*?)\s*(\d*)(.*)$/i)
    {
      $prefix=  defined($1) ? $1 : '';
      $name=$2;
      $instance=defined($3) ? $3 : '';
      $suffix=  defined($4) ? $4 : '';
      printf "  Prefix: %s  Name: %s  Instance: %s  Suffix: %s\n",
		$prefix, $name, $instance, $suffix    if $envDebug;

      $name=~s/Power Meter/Power/;
      $type='fan'      if $name=~/fan/i;
      $type='temp'     if $name=~/temp/i;
      $type='power'    if $name=~/power/i;
      $name=~s/\s+$//;

      # If a pattern such as 'Fan1A (xxx)', the suffix will actually be set to '1 (xxx)' so
      # make 'xxx' the prefix and everything after the '1' will be dropped later anyway
      # Power doesn't have a prefix, at least I haven't found any that do yet.
      $prefix=$1    if $fields[0]=~/(^fan|^temp)/i && $suffix=~/\((.*)\)/;

      # If an instance, append the first 'word' of the suffix as a modifier
      if ($instance ne '')
      {
        $instance.=$suffix;
        $instance=~s/\s.*//;
      }

      # If a pattern like 'Fan xxx' (note the check for NOT starting with a digit),
      # there is no prefix or instance so make it start with 'xxx Fan' for which
      # we already have logic for checking  it for an instance later on.
      $prefix=$1    if $prefix eq '' && $instance eq '' && $suffix=~/(^\D+\S+)/;

      # If a prefix, typically something like cpu, sys, virtual, etc.,
      # prepend the first letter to the name.  If it contains any digits 
      # and we don't yet have an instance, use that as well.
      if ($prefix ne '')
      {
        $prefix=~/(.{1})[a-z]*(\d*)/i;
        $name="$1$name";
        $instance=$2    if $instance eq '';
      }

      # Remove all whitespace
      $name=~s/\s+//g;

      my $postmap=$fields[0];
      for (my $i=0; $i<scalar(@{$ipmiFile->{post}}); $i++)
      {
        my $f1=$ipmiFile->{post}->[$i]->{f1};
        my $f2=$ipmiFile->{post}->[$i]->{f2};
        print "  Post-Remapped '$postmap' to '$name'\n"
	    if $name=~s/$f1/$f2/ && $envDebug;
      }

      my $index;
      $index=$envFanIndex++     if $type eq 'fan';
      $index=$envTempIndex++    if $type eq 'temp';
      $index=0                  if $type eq 'power';
      $fields[1]=-1             if $fields[1] eq '' || $fields[1] eq 'no reading';

      # If any last minute name remapping, this is the place for it
      for (my $i=0; defined(@$ipmiRemap) && $i<@{$ipmiRemap}; $i++)
      {
        my $p1=$ipmiRemap->[$i]->[1];
        my $p2=$ipmiRemap->[$i]->[2];
        $name=~s/$p1/$p2/;
      }

      $ipmiData->{$type}->[$index]->{name}=  $name;
      $ipmiData->{$type}->[$index]->{inst}=  $instance;
      $ipmiData->{$type}->[$index]->{value}= ($fields[1]!~/h$/) ? $fields[1] : $fields[3];
      $ipmiData->{$type}->[$index]->{status}=$fields[3];

      # we may need to convert temperatures, but be sure it ignore negative values
      if ($name=~/Temp/ && $envOpts=~/[CF]/ && ($ipmiData->{$type}->[$index]->{value} != -1))
      {
        $ipmiData->{$type}->[$index]->{value}= $ipmiData->{$type}->[$index]->{value}*1.8+32      if $envOpts=~/F/ && $fields[2]=~/C$/;
        $ipmiData->{$type}->[$index]->{value}= ($ipmiData->{$type}->[$index]->{value}-32)*5/9    if $envOpts=~/C/ && $fields[2]=~/F$/;
      }

      # finally, if 'T', truncate final value
      $ipmiData->{$type}->[$index]->{value}=int($ipmiData->{$type}->[$index]->{value})    if $envOpts=~/T/;
    }
  }

  elsif ($subsys=~/d/i && $type=~/^disk/)
  {
    ($major, $minor, $diskName, @dskFields)=split(/\s+/, $data);

    $diskName=~s/cciss\///;
    if (!defined($disks{$diskName}))
    {
      $dskChangeFlag|=1;    # new disk found

      # if available indexes use one of them otherwise generate a new one.
      if (@dskIndexAvail>0)
      { $dskIndex=pop @dskIndexAvail;}
      else
      { $dskIndex=$dskIndexNext++; }
      $disks{$diskName}=$dskIndex;
      print "new disk $diskName [$major,$minor] with index $dskIndex\n"    if !$firstPass && $debug & 1;

      # add to ordered list of disks if seen for first time
      my $newDisk=1;
      foreach my $dsk (@dskOrder)
      {
        $newDisk=0    if $diskName eq $dsk;
      }
      push @dskOrder, $diskName    if $newDisk;

      # by initializing the 'last' variable to the current value, we're assured to report 0s for the first
      # interval while teeing up the correct last value for the next interval.
      for (my $i=0; $i<11; $i++)
      { $dskFieldsLast[$dskIndex][$i]=$dskFields[$i]; }
    }
    $dskIndex=$disks{$diskName};
    $dskSeen[$dskIndex]=$diskName;
    $dskSeenCount++;    # faster than looping through to count

    # Clarification of field definitions:
    # Excellent reference: http://cvs.sourceforge.net/viewcvs.py/linux-vax
    #                               /kernel-2.5/Documentation/iostats.txt?rev=1.1.1.2
    #   ticks - time in jiffies doing I/O (some utils call it 'r/w-use')
    #   inprog - I/O's in progress (some utils call it 'running')
    #   ticks - time actually spent doing I/O (some utils call it 'use')
    #   aveque - average time in queue (some utils call it 'aveq' or even 'ticks')
    $dskRead[$dskIndex]=      fix($dskFields[0]-$dskFieldsLast[$dskIndex][0]);
    $dskReadMrg[$dskIndex]=   fix($dskFields[1]-$dskFieldsLast[$dskIndex][1]);
    $dskReadKB[$dskIndex]=    fix($dskFields[2]-$dskFieldsLast[$dskIndex][2])/2;
    $dskReadTicks[$dskIndex]= fix($dskFields[3]-$dskFieldsLast[$dskIndex][3]);
    $dskWrite[$dskIndex]=     fix($dskFields[4]-$dskFieldsLast[$dskIndex][4]);
    $dskWriteMrg[$dskIndex]=  fix($dskFields[5]-$dskFieldsLast[$dskIndex][5]);
    $dskWriteKB[$dskIndex]=   fix($dskFields[6]-$dskFieldsLast[$dskIndex][6])/2;
    $dskWriteTicks[$dskIndex]=fix($dskFields[7]-$dskFieldsLast[$dskIndex][7]);
    $dskInProg[$dskIndex]=    $dskFieldsLast[$dskIndex][8];
    $dskTicks[$dskIndex]=     fix($dskFields[9]-$dskFieldsLast[$dskIndex][9]);

    # according to the author of iostat this field can sometimes be negative
    # so handle the same way he does
    $dskWeighted[$dskIndex]=($dskFields[10]>=$dskFieldsLast[$dskIndex][10]) ?
	         fix($dskFields[10]-$dskFieldsLast[$dskIndex][10]) :
		 fix($dskFieldsLast[$dskIndex][10]-$dskFields[10]);

    # If read/write had bogus value, reset ALL current values for this disk to 0, noting that 1st pass
    # is initialization and numbers NOT valid so don't generate message
    if ($DiskMaxValue>0 && ($dskReadKB[$dskIndex]>$DiskMaxValue || $dskWriteKB[$dskIndex]>$DiskMaxValue))
      {
        logmsg('E', "One of ReadKB/WriteKB of '$dskRead[$dskIndex]/$dskWriteKB[$dskIndex]' > '$DiskMaxValue' for '$diskName'")
		    if !$firstPass;
        logmsg('W', "Resetting all current performance values for this disk to 0");

        $dskOps[$dskIndex]=$dskRead[$dskIndex]=$dskReadKB[$dskIndex]=$dskWrite[$dskIndex]=$dskWriteKB[$dskIndex]=0;
        $dskReadMrg[$dskIndex]=$dskWriteMrg[$dskIndex]=$dskWriteTicks[$dskIndex]=0;
	$dskInProg[$dskIndex]=$dskTicks[$dskIndex]=$dskWeighted[$dskIndex]=0;
      }

    # Apply filters to summary totals, explicitly ignoring those we don't want
    if ($diskName!~/^dm-|^psv/ && ($dskFilt eq '' || $diskName!~/$dskFiltIgnore/))
    {
      # if some explicitly named to keep, keep only those
      if ($dskFiltKeep eq '' || $diskName=~/$dskFiltKeep/)
      {
        $dskReadTot+=      $dskRead[$dskIndex];
        $dskReadMrgTot+=   $dskReadMrg[$dskIndex];
        $dskReadKBTot+=    $dskReadKB[$dskIndex];
        $dskReadTicksTot+= $dskReadTicks[$dskIndex];
        $dskWriteTot+=     $dskWrite[$dskIndex];
        $dskWriteMrgTot+=  $dskWriteMrg[$dskIndex];
        $dskWriteKBTot+=   $dskWriteKB[$dskIndex];
        $dskWriteTicksTot+=$dskWriteTicks[$dskIndex];
      }
    }

    # needed for compatibility with 2.4 in -P output
    $dskOpsTot=$dskReadTot+$dskWriteTot;

    # though we almost never need these when not doing detail reporting, a plugin might
    # if doing hires time, we need the interval duration and unfortunately at
    # this point in time $intSecs has not been set so we can't use it
    $microInterval=($fullTime-$lastSecs[$rawPFlag])*100    if $hiResFlag;

    $numIOs=$dskRead[$dskIndex]+$dskWrite[$dskIndex];
    $dskRqst[$dskIndex]=   $numIOs ? ($dskReadKB[$dskIndex]+$dskWriteKB[$dskIndex])/$numIOs : 0;
    $dskQueLen[$dskIndex]= $dskTicks[$dskIndex] ? $dskWeighted[$dskIndex]/$dskTicks[$dskIndex] : 0;
    $dskWait[$dskIndex]=   $numIOs ? ($dskReadTicks[$dskIndex]+$dskWriteTicks[$dskIndex])/$numIOs : 0;
    $dskSvcTime[$dskIndex]=$numIOs ? $dskTicks[$dskIndex]/$numIOs : 0;
    $dskUtil[$dskIndex]=   $dskTicks[$dskIndex]*10/$microInterval;

    # note fieldsLast[8] ignored
    for ($i=0; $i<11; $i++)
    {
      $dskFieldsLast[$dskIndex][$i]=$dskFields[$i];
    }
    $dskIndex++;
  }

  elsif ($subsys=~/i/ && $type=~/^fs-/)
  {
    if ($type=~/^fs-ds/)
    {
      ($dentryNum, $dentryUnused)=(split(/\s+/, $data))[0,1];
    }
    elsif ($type=~/^fs-fnr/)
    {
      ($filesAlloc, $filesMax)=(split(/\s+/, $data))[0,2];
    }
    elsif ($type=~/^fs-is/)
    {
      ($inodeMax, $inodeUsed)=split(/\s+/, $data);
      $inodeUsed=$inodeMax-$inodeUsed;
    }
  }

  # Only if collecting nfs server data
  elsif ($subsys=~/f/i && $type=~/^nfs(.?)-net/)
  {
    # for earlier versions we've already know this is server data
    # but for newer ones we collectl both
    my $nfsType=($1 ne '') ? $1 : 's';

    ($nfsPktsNow, $nfsUdpNow, $nfsTcpNow, $nfsTcpConnNow)=split(/\s+/, $data);
    if (!defined($nfsTcpConnNow))
    {
      incomplete("NFS-NET", $lastSecs[$rawPFlag]);
      return;
    }

    # only look at the data for servers
    if ($nfsType eq 's')
    {
      $nfsPkts=   fix($nfsPktsNow-$nfsPktsLast);
      $nfsUdp=    fix($nfsUdpNow-$nfsUdpLast);
      $nfsTcp=    fix($nfsTcpNow-$nfsTcpLast);
      $nfsTcpConn=fix($nfsTcpConnNow-$nfsTcpConnLast);

      $nfsPktsLast=   $nfsPktsNow;
      $nfsUdpLast=    $nfsUdpNow;
      $nfsTcpLast=    $nfsTcpNow;
      $nfsTcpConnLast=$nfsTcpConnNow;

      $nfsUdpTot+=$nfsUdp;
      $nfsTcpTot+=$nfsTcp;
      $nfsTcpConnsTot+=$nfsTcpConn;
    }
  }

  # nfs rpc for server doesn't use fields 2/5
  elsif ($subsys=~/f/i && $type=~/^nfs(.?)-rpc/)
  {
    # For earlier versions, we've already set the client/server flag
    my $nfsType=($nfsCFlag) ? 'c' : 's';
    $nfsType=$1    if $1 ne '';

    my (@rpcFields)=split(/\s+/, $data);
    if (($nfsType eq 'c' && !defined($rpcFields[2])) || ($nfsType eq 's' && !defined($rpcFields[4])))
    {
      incomplete("RPC", $lastSecs[$rawPFlag]);
      return;
    }

    # NOTE - 'calls' common to both clients and servers
    if ($nfsType eq 's' && $nfsSFlag)
    {
      $rpcCallsNow=  $rpcFields[0];
      $rpcBadAuthNow=$rpcFields[2];
      $rpcBadClntNow=$rpcFields[3];

      $rpcSCalls=  fix($rpcCallsNow-$rpcSCallsLast);
      $rpcBadAuth= fix($rpcBadAuthNow-$rpcBadAuthLast);
      $rpcBadClnt= fix($rpcBadClntNow-$rpcBadClntLast);

      $rpcSCallsLast= $rpcCallsNow;
      $rpcBadAuthLast=$rpcBadAuthNow;
      $rpcBadClntLast=$rpcBadClntNow;
    }
    elsif ($nfsCFlag)
    {
      $rpcCallsNow=  $rpcFields[0];
      $rpcRetransNow=$rpcFields[1];
      $rpcCredRefNow=$rpcFields[2];

      $rpcCCalls= fix($rpcCallsNow-$rpcCCallsLast);
      $rpcRetrans=fix($rpcRetransNow-$rpcRetransLast);
      $rpcCredRef=fix($rpcCredRefNow-$rpcCredRefLast);

      $rpcCCallsLast= $rpcCallsNow;
      $rpcRetransLast=$rpcRetransNow;
      $rpcCredRefLast=$rpcCredRefNow;
    }

    $rpcBadAuthTot+=$rpcBadAuth;
    $rpcBadClntTot+=$rpcBadClnt;
    $rpcRetransTot+=$rpcRetrans;
    $rpcCredRefTot+=$rpcCredRef;
  }

  elsif ($subsys=~/f/i && $type=~/^nfs(.?)-proc2/ && $nfs2Flag)
  {
    # For earlier versions, we've already set the client/server flag
    my $nfsType=($nfsCFlag) ? 'c' : 's';
    $nfsType=$1    if $1 ne '';

    # field 0 is field count, which we know to be 18
    @nfsValuesNow=(split(/\s+/, $data))[1..18];
    if (scalar(@nfsValuesNow)<18)
    {
      incomplete("NFS2", $lastSecs[$rawPFlag]);
      return;
    }

    # Until we've seen a non-zero read/write counter for clients/servers
    # we won't even look at or report the other fields
    if ($nfsValuesNow[6] || $nfsValuesNow[8])
    {
      $nfs2CSeen=1    if $nfsType eq 'c';
      $nfs2SSeen=1    if $nfsType eq 's';
    }

    if ($nfsType eq 'c' && $nfs2CFlag && $nfs2CSeen)
    {
      for ($i=0; $i<18; $i++)
      {
        $nfs2CValue[$i]=fix($nfsValuesNow[$i]-$nfs2CValuesLast[$i]);
        $nfs2CValuesLast[$i]=$nfsValuesNow[$i];
      }

      $nfs2CNull=   $nfs2CValue[0];    $nfs2CGetattr= $nfs2CValue[1];
      $nfs2CSetattr=$nfs2CValue[2];    $nfs2CRoot=    $nfsC2Value[3];
      $nfs2CLookup= $nfs2CValue[4];    $nfs2CReadlink=$nfs2CValue[5];
      $nfs2CRead=   $nfs2CValue[6];    $nfs2CWrcache= $nfs2CValue[7];
      $nfs2CWrite=  $nfs2CValue[8];    $nfs2CCreate=  $nfs2CValue[9];
      $nfs2CRemove= $nfs2CValue[10];   $nfs2CRename=  $nfs2CValue[11];
      $nfs2CLink=   $nfs2CValue[12];   $nfs2CSymlink= $nfs2CValue[13];
      $nfs2CMkdir=  $nfs2CValue[14];   $nfs2CRmdir=   $nfs2CValue[15];
      $nfs2CReaddir=$nfs2CValue[16];   $nfs2CFsstat=  $nfs2CValue[17];
      $nfs2CMeta=$nfs2CLookup+$nfs2CSetattr+$nfs2CGetattr+$nfs2CReaddir;

      $nfsReadsTot+=  $nfs2CRead;
      $nfsCReadsTot+= $nfs2CRead;
      $nfsWritesTot+= $nfs2CWrite;
      $nfsCWritesTot+=$nfs2CWrite;
      $nfsMetaTot+=   $nfs2CMeta;
      $nfsCMetaTot+=  $nfs2CMeta;
    }
    elsif ($nfsType eq 's' && $nfs2SFlag && $nfs2SSeen)
    {
      for ($i=0; $i<18; $i++)
      {
        $nfs2SValue[$i]=fix($nfsValuesNow[$i]-$nfs2SValuesLast[$i]);
        $nfs2SValuesLast[$i]=$nfsValuesNow[$i];
      }

      $nfs2SNull=   $nfs2SValue[0];    $nfs2SGetattr= $nfs2SValue[1];
      $nfs2SSetattr=$nfs2SValue[2];    $nfs2SRoot=    $nfs2SValue[3];
      $nfs2SLookup= $nfs2SValue[4];    $nfs2SReadlink=$nfs2SValue[5];
      $nfs2SRead=   $nfs2SValue[6];    $nfs2SWrcache= $nfs2SValue[7];
      $nfs2SWrite=  $nfs2SValue[8];    $nfs2SCreate=  $nfs2SValue[9];
      $nfs2SRemove= $nfs2SValue[10];   $nfs2SRename=  $nfs2SValue[11];
      $nfs2SLink=   $nfs2SValue[12];   $nfs2SSymlink= $nfs2SValue[13];
      $nfs2SMkdir=  $nfs2SValue[14];   $nfs2SRmdir=   $nfs2SValue[15];
      $nfs2SReaddir=$nfs2SValue[16];   $nfs2SFsstat=  $nfs2SValue[17];
      $nfs2SMeta=$nfs2SLookup+$nfs2SSetattr+$nfs2SGetattr+$nfs2SReaddir;

      $nfsReadsTot+=  $nfs2SRead;
      $nfsSReadsTot+= $nfs2SRead;
      $nfsWritesTot+= $nfs2SWrite;
      $nfsSWritesTot+=$nfs2SWrite;
      $nfsMetaTot+=   $nfs2SMeta;
      $nfsSMetaTot+=  $nfs2SMeta;
    }
  }
  
  elsif ($subsys=~/f/i && $type=~/^nfs(.?)-proc3/ && $nfs3Flag)
  {
    # For earlier versions, we've already set the client/server flag
    my $nfsType=($nfsCFlag) ? 'c' : 's';
    $nfsType=$1    if $1 ne '';

    # field 0 is field count
    @nfsValuesNow=(split(/\s+/, $data))[1..22];
    if (scalar(@nfsValuesNow)<22)
    {
      incomplete("NFS3", $lastSecs[$rawPFlag]);
      return;
    }

    if ($nfsValuesNow[6] || $nfsValuesNow[7])
    {
      $nfs3CSeen=1    if $nfsType eq 'c';
      $nfs3SSeen=1    if $nfsType eq 's';
    }

    if ($nfsType eq 'c' && $nfs3CFlag && $nfs3CSeen)
    {
      for ($i=0; $i<22; $i++)
      {
        $nfs3CValue[$i]=fix($nfsValuesNow[$i]-$nfs3CValuesLast[$i]);
        $nfs3CValuesLast[$i]=$nfsValuesNow[$i];
      }

      $nfs3CNull=    $nfs3CValue[0];   $nfs3CGetattr=    $nfs3CValue[1];
      $nfs3CSetattr= $nfs3CValue[2];   $nfs3CLookup=     $nfs3CValue[3];
      $nfs3CAccess=  $nfs3CValue[4];   $nfs3CReadlink=   $nfs3CValue[5];
      $nfs3CRead=    $nfs3CValue[6];   $nfs3CWrite=      $nfs3CValue[7];
      $nfs3CCreate=  $nfs3CValue[8];   $nfs3CMkdir=      $nfs3CValue[9];
      $nfs3CSymlink= $nfs3CValue[10];  $nfs3CMknod=      $nfs3CValue[11];
      $nfs3CRemove=  $nfs3CValue[12];  $nfs3CRmdir=      $nfs3CValue[13];
      $nfs3CRename=  $nfs3CValue[14];  $nfs3CLink=       $nfs3CValue[15];
      $nfs3CReaddir= $nfs3CValue[16];  $nfs3CReaddirplus=$nfs3CValue[17];
      $nfs3CFsstat=  $nfs3CValue[18];  $nfs3CFsinfo=     $nfs3CValue[19];
      $nfs3CPathconf=$nfs3CValue[20];  $nfs3CCommit=     $nfs3CValue[21];
      $nfs3CMeta=$nfs3CLookup+$nfs3CAccess+$nfs3CSetattr+$nfs3CGetattr+$nfs3CReaddir+$nfs3CReaddirplus;

      $nfsReadsTot+=  $nfs3CRead;
      $nfsCReadsTot+= $nfs3CRead;
      $nfsWritesTot+= $nfs3CWrite;
      $nfsCWritesTot+=$nfs3CWrite;
      $nfsCommitTot+= $nfs3CCommit;
      $nfsCCommitTot+=$nfs3CCommit;
      $nfsMetaTot+=   $nfs3CMeta;
      $nfsCMetaTot+=  $nfs3CMeta;
    }
    elsif ($nfsType eq 's' && $nfs3SFlag && $nfs3SSeen)
    {
      for ($i=0; $i<22; $i++)
      {
        $nfs3SValue[$i]=fix($nfsValuesNow[$i]-$nfs3SValuesLast[$i]);
        $nfs3SValuesLast[$i]=$nfsValuesNow[$i];
      }

      $nfs3SNull=    $nfs3SValue[0];   $nfs3SGetattr=    $nfs3SValue[1];
      $nfs3SSetattr= $nfs3SValue[2];   $nfs3SLookup=     $nfs3SValue[3];
      $nfs3SAccess=  $nfs3SValue[4];   $nfs3SReadlink=   $nfs3SValue[5];
      $nfs3SRead=    $nfs3SValue[6];   $nfs3SWrite=      $nfs3SValue[7];
      $nfs3SCreate=  $nfs3SValue[8];   $nfs3SMkdir=      $nfs3SValue[9];
      $nfs3SSymlink= $nfs3SValue[10];  $nfs3SMknod=      $nfs3SValue[11];
      $nfs3SRemove=  $nfs3SValue[12];  $nfs3SRmdir=      $nfs3SValue[13];
      $nfs3SRename=  $nfs3SValue[14];  $nfs3SLink=       $nfs3SValue[15];
      $nfs3SReaddir= $nfs3SValue[16];  $nfs3SReaddirplus=$nfs3SValue[17];
      $nfs3SFsstat=  $nfs3SValue[18];  $nfs3SFsinfo=     $nfs3SValue[19];
      $nfs3SPathconf=$nfs3SValue[20];  $nfs3SCommit=     $nfs3SValue[21];
      $nfs3SMeta=$nfs3SLookup+$nfs3SAccess+$nfs3SSetattr+$nfs3SGetattr+$nfs3SReaddir+$nfs3SReaddirplus;

      $nfsReadsTot+=  $nfs3SRead;
      $nfsSReadsTot+= $nfs3SRead;
      $nfsWritesTot+= $nfs3SWrite;
      $nfsSWritesTot+=$nfs3SWrite;
      $nfsCommitTot+= $nfs3SCommit;
      $nfsSCommitTot+=$nfs3SCommit;
      $nfsMetaTot+=   $nfs3SMeta;
      $nfsSMetaTot+=  $nfs3SMeta;
    }
  }

  # A little trickier because proc4 has client data but proc4ops has server data
  elsif ($subsys=~/f/i && $type=~/^nfs(.?)-proc4/ && $nfs4Flag)
  {
    # For earlier versions, we've already set the client/server flag
    my $nfsType=($nfsCFlag) ? 'c' : 's';
    $nfsType=$1    if $1 ne '';

    # field 0 is field count
    ($numFields,@nfsValuesNow)=split(/\s+/, $data);
    if (scalar(@nfsValuesNow)<$numFields)
    {
      incomplete("NFS4", $lastSecs[$rawPFlag]);
      return;
    }

    # I can't believe they didn't use the same field numbers for clients/servers
    $nfs4CSeen=1    if $nfsType eq 'c' &&  ($nfsValuesNow[1] || $nfsValuesNow[2]);
    $nfs4SSeen=1    if $nfsType eq 's' && ($nfsValuesNow[25] || $nfsValuesNow[38]);

    if ($nfsType eq 'c' && $nfs4CFlag && $nfs4CSeen)
    { 
      for ($i=0; $i<$numFields; $i++)
      {
        $nfs4CValue[$i]=fix($nfsValuesNow[$i]-$nfs4CValuesLast[$i]);
        $nfs4CValuesLast[$i]=$nfsValuesNow[$i];
      }

      # Not Used: Mkdir Mknod Readdirplus Fsstat Rmdir
      $nfs4CNull=    $nfs4CValue[0];   $nfs4CRead=    $nfs4CValue[1];
      $nfs4CWrite=   $nfs4CValue[2];   $nfs4CCommit=  $nfs4CValue[3];
      $nfs4CSetattr= $nfs4CValue[9];   $nfs4CFsinfo=  $nfs4CValue[10];
      $nfs4CAccess=  $nfs4CValue[17];  $nfs4CGetattr= $nfs4CValue[18];
      $nfs4CLookup=  $nfs4CValue[19];  $nfs4CRemove=  $nfs4CValue[21];
      $nfs4CRename=  $nfs4CValue[22];  $nfs4CLink=    $nfs4CValue[23];
      $nfs4CSymlink= $nfs4CValue[24];  $nfs4CCreate=  $nfs4CValue[25];
      $nfs4CPathconf=$nfs4CValue[26];  $nfs4CReadlink=$nfs4CValue[28];
      $nfs4CReaddir= $nfs4CValue[29];
      $nfs4CMeta=$nfs4CLookup+$nfs4CAccess+$nfs4CSetattr+$nfs4CGetattr+$nfs4CReaddir;

      $nfsReadsTot+=  $nfs4CRead;
      $nfsCReadsTot+= $nfs4CRead;
      $nfsWritesTot+= $nfs4CWrite;
      $nfsCWritesTot+=$nfs4CWrite;
      $nfsCommitTot+= $nfs4CCommit;
      $nfsCCommitTot+=$nfs4CCommit;
      $nfsMetaTot+=   $nfs4CMeta;
      $nfsCMetaTot+=  $nfs4CMeta;
    }
    elsif ($type=~/^nfs(.?)-proc4ops/ && $nfs4SFlag && $nfs4SSeen)
    {
      for ($i=0; $i<$numFields; $i++)
      {
        $nfs4SValue[$i]=fix($nfsValuesNow[$i]-$nfs4SValuesLast[$i]);
        $nfs4SValuesLast[$i]=$nfsValuesNow[$i];
      }

      # Not Used: Null Pathconf Mkdir Mknod Readdirplus Fsinfo Fsstat Symlink Rmdir
      $nfs4SAccess=  $nfs4SValue[3];   $nfs4SCommit=  $nfs4SValue[5];
      $nfs4SCreate=  $nfs4SValue[6];   $nfs4SGetattr= $nfs4SValue[9];
      $nfs4SLink=    $nfs4SValue[11];  $nfs4SLookup=  $nfs4SValue[15];
      $nfs4SRead=    $nfs4SValue[25];  $nfs4SReaddir= $nfs4SValue[26];
      $nfs4SReadlink=$nfs4SValue[27];  $nfs4SRemove=  $nfs4SValue[28]; 
      $nfs4SRename=  $nfs4SValue[29];  $nfs4SSetattr= $nfs4SValue[34];
      $nfs4SWrite=   $nfs4SValue[38];
      $nfs4SMeta=$nfs4SLookup+$nfs4SAccess+$nfs4SSetattr+$nfs4SGetattr+$nfs4SReaddir;

      $nfsReadsTot+=  $nfs4SRead;
      $nfsSReadsTot+= $nfs4SRead;
      $nfsWritesTot+= $nfs4SWrite;
      $nfsSWritesTot+=$nfs4SWrite;
      $nfsCommitTot+= $nfs4SCommit;
      $nfsSCommitTot+=$nfs4SCommit;
      $nfsMetaTot+=   $nfs4SMeta;
      $nfsSMetaTot+=  $nfs4SMeta;
    }
  }

  #    M e m o r y    S t a t s

  elsif ($subsys=~/m/i && $type=~/^pg|^pswp/)
  {
    if ($type=~/^pgpgin/)
    {
      $pageinNow=$data;
      $pagein=fix($pageinNow-$pageinLast);
      $pageinLast=$pageinNow;
    }
    elsif ($type=~/^pgpgout/)
    {
      $pageoutNow=$data;
      $pageout=fix($pageoutNow-$pageoutLast);
      $pageoutLast=$pageoutNow;
    }
    elsif ($type=~/^pgfault/)
    {
      $pagefaultNow=$data;
      $pagefault=fix($pagefaultNow-$pagefaultLast);
      $pagefaultLast=$pagefaultNow;
    }
    elsif ($type=~/^pgmaj/)
    {
      $pagemajfaultNow=$data;
      $pagemajfault=fix($pagemajfaultNow-$pagemajfaultLast);
      $pagemajfaultLast=$pagemajfaultNow;
    }
    elsif ($type=~/^pswpin/)
    {
      $swapinNow=$data;
      $swapin=fix($swapinNow-$swapinLast);
      $swapinLast=$swapinNow;
    }
    elsif ($type=~/^pswpout/)
    {
      $swapoutNow=$data;
      $swapout=fix($swapoutNow-$swapoutLast);
      $swapoutLast=$swapoutNow;
    }

    if ($memOpts=~/p/)
    {
      $pageAllocDma=$data        if $type=~/^pgalloc_dma$/;
      $pageAllocDma32=$data      if $type=~/^pgalloc_dma32/;
      $pageAllocNormal=$data     if $type=~/^pgalloc_normal/;
      $pageAllocMove=$data       if $type=~/^pgalloc_move/;

      $pageRefillDma=$data       if $type=~/^pgrefill_dma$/;
      $pageRefillDma32=$data     if $type=~/^pgrefill_dma32/;    
      $pageRefillNormal=$data    if $type=~/^pgrefill_normal/;
      $pageRefillMove=$data      if $type=~/^pgrefill_move/;

      $pageFree=$data            if $type=~/^pgfree/;
      $pageActivate=$data        if $type=~/^pgactivate/;
    }

    if ($memOpts=~/s/)
    {
      $pageStealDma=$data        if $type=~/^pgsteal_dma$/;
      $pageStealDma32=$data      if $type=~/^pgsteal_dma32/;
      $pageStealNormal=$data     if $type=~/^pgsteal_normal/;
      $pageStealMove=$data       if $type=~/^pgsteal_move/;

      $pageKSwapDma=$data        if $type=~/^pgscan_kswapd_dma$/;
      $pageKSwapDma32=$data      if $type=~/^pgscan_kswapd_dma32/;
      $pageKSwapNormal=$data     if $type=~/^pgscan_kswapd_normal/;
      $pageKSwapMove=$data       if $type=~/^pgscan_kswapd_move/;

      $pageDirectDma=$data       if $type=~/^pgscan_direct_dma$/;
      $pageDirectDma32=$data     if $type=~/^pgscan_direct_dma32/;
      $pageDirectNormal=$data    if $type=~/^pgscan_direct_normal/;
      $pageDirectMove=$data      if $type=~/^pgscan_direct_move/;
    }
  }

  elsif ($subsys=~/m/i && $type=~/^Mem/)
  {
    $data=(split(/\s+/, $data))[0];
    $memTot= $data    if $type=~/^MemTotal/;

    if ($type=~/^MemFree/)
    {
      $memFree=$data;
      $memFreeC=$memFree-$memFreeLast;
      $memFreeLast=$memFree;
    }
  }

  elsif ($subsys=~/m/i && $type=~/^Buffers|^Cached|^Dirty|^Active|^Inactive|^AnonPages|^Mapped|^Slab:|^Committed_AS:|^Huge|^SUnreclaim|^Mloc/)
  {
    $data=(split(/\s+/, $data))[0];
    $memBuf=$data             if $type=~/^Buf/;
    $memCached=$data          if $type=~/^Cac/;
    $memDirty=$data           if $type=~/^Dir/;
    $memAct=$data             if $type=~/^Act/;
    $memInact=$data           if $type=~/^Ina/;
    $memSlab=$data            if $type=~/^Sla/;
    $memAnon=$data            if $type=~/^Anon/;
    $memMap=$data             if $type=~/^Map/;
    $memLocked=$data          if $type=~/^Mlocked/;
    $memCommit=$data          if $type=~/^Com/;
    $memHugeTot=$data         if $type=~/^HugePages_T/;
    $memHugeFree=$data        if $type=~/^HugePages_F/;
    $memHugeRsvd=$data        if $type=~/^HugePages_R/;
    $memSUnreclaim=$data      if $type=~/^SUnreclaim/;

    # These are 'changes' since last interval, both positive/negative
    # but we only want to do when last one in list seen.
    if ($type=~/^Com/)
    {
      $memBufC=   $memBuf-$memBufLast;
      $memCachedC=$memCached-$memCachedLast;
      $memInactC= $memInact-$memInactLast;
      $memSlabC=  $memSlab-$memSlabLast;
      $memMapC=   $memMap-$memMapLast;
      $memAnonC=  $memAnon-$memAnonLast;
      $memCommitC=$memCommit-$memCommitLast;
      $memLockedC=$memLocked-$memLockedLast;

      $memBufLast=   $memBuf;
      $memCachedLast=$memCached;
      $memInactLast= $memInact;
      $memSlabLast=  $memSlab;
      $memMapLast=   $memMap;
      $memAnonLast=  $memAnon;
      $memCommitLast=$memCommit;
      $memLockedLast=$memLocked;
    }
  }

  elsif ($subsys=~/m/i && $type=~/^Swap/)
  {
    $data=(split(/\s+/, $data))[0];
    $swapTotal=$data    if $type=~/^SwapT/;

    if ($type=~/^SwapF/)
    {
      $swapFree=$data;
      $swapFreeC=$swapFree-$swapFreeLast;
      $swapFreeLast=$swapFree;
    }
  }

  elsif ($subsys=~/m/i && $type=~/^numa(\S)/)
  {
    my $statsType=$1;

    $data=~/Node (\d+) (\S+?):*\s+(\d+)/;
    my $node=$1;
    my $name=$2;
    my $value=$3;

    if ($statsType eq 'i')
    {
      if ($name=~/^MemFree/)
      { $numaMem[$node]->{free}=$value; }
      elsif ($name=~/^MemUsed/)
      { $numaMem[$node]->{used}=$value; }
      elsif ($name=~/^Active$/)             # equal to Active(anon) + Active(file)
      { $numaMem[$node]->{act}=$value; }
      elsif ($name=~/^Inactive$/)           # equal to Inactive(anon) + Inactive(file)
      { $numaMem[$node]->{inact}=$value; }
      elsif ($name=~/^Mapped/)
      { $numaMem[$node]->{map}=$value; }
      elsif ($name=~/^Anon/)
      { $numaMem[$node]->{anon}=$value; }
      elsif ($name=~/^Mlock/)
      { $numaMem[$node]->{lock}=$value; }

      # currently the last entry read...
      elsif ($name=~/^Slab/)
      {
        $numaMem[$node]->{slab}=$value;

        # these are changed since all last seen
        if ($memOpts=~/R/)
        {
          $numaMem[$node]->{freeC}= $numaMem[$node]->{free}- $numaMem[$node]->{freeLast};
          $numaMem[$node]->{usedC}= $numaMem[$node]->{used}- $numaMem[$node]->{usedLast};
          $numaMem[$node]->{actC}=  $numaMem[$node]->{act}-  $numaMem[$node]->{actLast};
          $numaMem[$node]->{inactC}=$numaMem[$node]->{inact}-$numaMem[$node]->{inactLast};
          $numaMem[$node]->{mapC}=  $numaMem[$node]->{map}-  $numaMem[$node]->{mapLast};
          $numaMem[$node]->{anonC}= $numaMem[$node]->{anon}- $numaMem[$node]->{anonLast};
          $numaMem[$node]->{lockC}= $numaMem[$node]->{lock}- $numaMem[$node]->{lockLast};
          $numaMem[$node]->{slabC}= $numaMem[$node]->{slab}- $numaMem[$node]->{slabLast};

          $numaMem[$node]->{freeLast}= $numaMem[$node]->{free};
          $numaMem[$node]->{usedLast}= $numaMem[$node]->{used};
          $numaMem[$node]->{actLast}=  $numaMem[$node]->{act};
          $numaMem[$node]->{inactLast}=$numaMem[$node]->{inact};
          $numaMem[$node]->{mapLast}=  $numaMem[$node]->{map};
          $numaMem[$node]->{anonLast}= $numaMem[$node]->{anon};
          $numaMem[$node]->{lockLast}= $numaMem[$node]->{lock};
          $numaMem[$node]->{slabLast}= $numaMem[$node]->{slab};
        }
      }
    }
    else
    {
      if ($name=~/^numa_hit/)
      { $numaStat[$node]->{hitsNow}=$value; }
      elsif ($name=~/^numa_miss/)
      { $numaStat[$node]->{missNow}=$value; }

      # currently last entry processed
      elsif ($name=~/^numa_foreign/)
      {
        $numaStat[$node]->{forNow}=$value;

        $numaStat[$node]->{hits}=$numaStat[$node]->{hitsNow}-$numaStat[$node]->{hitsLast};
        $numaStat[$node]->{miss}=$numaStat[$node]->{missNow}-$numaStat[$node]->{missLast};
        $numaStat[$node]->{for}=$numaStat[$node]->{forNow}-$numaStat[$node]->{forLast};

        $numaStat[$node]->{hitsLast}=$numaStat[$node]->{hitsNow};
        $numaStat[$node]->{missLast}=$numaStat[$node]->{missNow};
        $numaStat[$node]->{forLast}=$numaStat[$node]->{forNow};
      }
    }
  }

  #    S o c k e t    S t a t s

  elsif ($subsys=~/s/ && $type=~/^sock/)
  {
    if ($data=~/^sock/)
    {
      $data=~/(\d+)$/;
      $sockUsed=$1;
    }
    elsif ($data=~/^TCP/)
    {
      ($sockTcp, $sockOrphan, $sockTw, $sockAlloc, $sockMem)=
		(split(/\s+/, $data))[2,4,6,8,10];
    }
    elsif ($data=~/^UDP/)
    {
      $data=~/(\d+)$/;
      $sockUdp=$1;
    }
    elsif ($data=~/^RAW/)
    {
      $data=~/(\d+)$/;
      $sockRaw=$1;
    }
    elsif ($data=~/^FRAG/)
    {
      $data=~/(\d+).*(\d)$/;
      $sockFrag=$1;
      $sockFragM=$1;
    }
  }

  #    N e t w o r k    S t a t s

  # a few design notes...
  # - %networks is the name of all the networks
  # - @netOrder is the discovery order
  # - @netIndexAvail is a stack of available, previously used indexes
  # - $netIndex is the index assigned the current network being processed
  # - $netIndexNext is next available index NOT on @netIndexAvail
  # - @netSeen is list of networks seen this interval
  # - $netSeenCount is the number of entries in @netSeen
  # - $netSeenLast save number seen in last interval
  elsif ($subsys=~/n/i && $type=~/^Net/)
  {
    # insert space after interface if none already there
    $data=~s/:(\d)/: $1/;
    undef @fields;
    @fields=split(/\s+/, $data);
    if (@fields<17)
    {
      incomplete("NET:".$fields[0], $lastSecs[$rawPFlag]);
      return;
    }

    #    N e w    N e t    S e e n

    my $netName=$fields[0];
    $netName=~s/://;
    if (!defined($networks{$netName}))
    {
      $netChangeFlag|=1;    # could be useful to external modules
      print "new network found: $netName\n"    if !$firstPass && $debug & 1;

      # if available indexes use one of them otherwise generate a new one
      if (@netIndexAvail>0)
      { $netIndex=pop @netIndexAvail;}
      else
      { $netIndex=$netIndexNext++; }
      $networks{$netName}=$netIndex;
      print "new network $netName with index $netIndex\n"    if $debug & 1;

      # add to ordered list of networks if seen for first time
      my $newNet=1;
      foreach my $net (@netOrder)
      {
        $net=~s/:.*//;
        $newNet=0    if $netName eq $net;
      }
      push @netOrder, $netName    if $newNet;

      # by initializing the 'last' variable to the current value, we're assured to report 0s for the first
      # interval while teeing up the correct last value for the next interval.
      $netRxKBLast[$netIndex]=  $fields[1];
      $netRxPktLast[$netIndex]= $fields[2];
      $netRxErrLast[$netIndex]= $fields[3];
      $netRxDrpLast[$netIndex]= $fields[4];
      $netRxFifoLast[$netIndex]=$fields[5];
      $netRxFraLast[$netIndex]= $fields[6];
      $netRxCmpLast[$netIndex]= $fields[7];
      $netRxMltLast[$netIndex]= $fields[8];

      $netTxKBLast[$netIndex]=  $fields[9];
      $netTxPktLast[$netIndex]= $fields[10];
      $netTxErrLast[$netIndex]= $fields[11];
      $netTxDrpLast[$netIndex]= $fields[12];
      $netTxFifoLast[$netIndex]=$fields[13];
      $netTxCollLast[$netIndex]=$fields[14];
      $netTxCarLast[$netIndex]= $fields[15];
      $netTxCmpLast[$netIndex]= $fields[16];

      # won't do anything with speed until we create a new file, but then we'll get a new header
      my $line=`find /sys/devices/ 2>&1 | grep net | grep $netName | grep speed`;
      $netSpeeds{$netName}='??';
      if ($line ne '')
      {
        $speed=`cat $line 2>&1`;
        chomp $speed;
        $line=~/.*\/(\S+)\/speed/;
        my $netName=$1;
        $netSpeeds{$netName}=$speed    if $speed=~/Invalid/;
      }

      # user for bogus speed checks
      my $netspeed=($netSpeeds{$netName} ne '??') ? $netSpeeds{$netName} : $DefNetSpeed;
      $NetMaxTraffic[$netIndex]=2*$interval*$netspeed*125;
    }
    $netIndex=$networks{$netName};
    $netSeen[$netIndex]=$netName;
    $netSeenCount++;

    $netNameNow=  $fields[0];
    $netRxKBNow=  $fields[1];
    $netRxPktNow= $fields[2];
    $netRxErrNow= $fields[3];
    $netRxDrpNow= $fields[4];
    $netRxFifoNow=$fields[5];
    $netRxFraNow= $fields[6];
    $netRxCmpNow= $fields[7];
    $netRxMltNow= $fields[8];

    $netTxKBNow=  $fields[9];
    $netTxPktNow= $fields[10];
    $netTxErrNow= $fields[11];
    $netTxDrpNow= $fields[12];
    $netTxFifoNow=$fields[13];
    $netTxCollNow=$fields[14];
    $netTxCarNow= $fields[15];
    $netTxCmpNow= $fields[16];

    $netRxKB[$netIndex]= fix($netRxKBNow-$netRxKBLast[$netIndex])/1024;
    $netTxKB[$netIndex]= fix($netTxKBNow-$netTxKBLast[$netIndex])/1024;
    $netRxPkt[$netIndex]=fix($netRxPktNow-$netRxPktLast[$netIndex]);
    $netTxPkt[$netIndex]=fix($netTxPktNow-$netTxPktLast[$netIndex]);

    # extended/errors
    $netRxErr[$netIndex]= fix($netRxErrNow- $netRxErrLast[$netIndex]);
    $netRxDrp[$netIndex]= fix($netRxDrpNow- $netRxDrpLast[$netIndex]);
    $netRxFifo[$netIndex]=fix($netRxFifoNow-$netRxFifoLast[$netIndex]);
    $netRxFra[$netIndex]= fix($netRxFraNow- $netRxFraLast[$netIndex]);
    $netRxCmp[$netIndex]= fix($netRxCmpNow- $netRxCmpLast[$netIndex]);
    $netRxMlt[$netIndex]= fix($netRxMltNow- $netRxMltLast[$netIndex]);
    $netTxErr[$netIndex]= fix($netTxErrNow- $netTxErrLast[$netIndex]);
    $netTxDrp[$netIndex]= fix($netTxDrpNow- $netTxDrpLast[$netIndex]);
    $netTxFifo[$netIndex]=fix($netTxFifoNow-$netTxFifoLast[$netIndex]);
    $netTxColl[$netIndex]=fix($netTxCollNow-$netTxCollLast[$netIndex]);
    $netTxCar[$netIndex]= fix($netTxCarNow- $netTxCarLast[$netIndex]);
    $netTxCmp[$netIndex]= fix($netTxCmpNow- $netTxCmpLast[$netIndex]);

    # It has occasionally been observed that bogus data is returned for some networks.
    # If we see anything that looks like twice the typical speed, ignore it but remember
    # that during the very first interval this data should be bogus!  Also, set ALL data
    # points to 0 since we can't trust any of them.  Note that the bogus value is now in
    # the 'last' variable and so the next valid value will be bogus relative to it, but
    # then its value will become 'last' and the following values should be 'happy'.
    if ($DefNetSpeed>0 && $intFirstSeen &&
         ($netRxKB[$netIndex]>$NetMaxTraffic[$netIndex] || $netTxKB[$netIndex]>$NetMaxTraffic[$netIndex]))
    {
      # we're going through some extra pain to make error messages very explicit.  we also can't use
      # int() because some bogus values are too big, especially if data collectl on 64 bit machine
      # and processed on 32 bit one.
      $netTxKB[$netIndex]=~s/\..*//;
      $netRxKB[$netIndex]=~s/\..*//;
      incomplete("NET:".$netNameNow, $lastSecs[$rawPFlag], 'Bogus');
      logmsg('I', "Network speed threshhold: $NetMaxTraffic[$netIndex]  Bogus Value(s) - TX: $netTxKB[$netIndex]KB  RX: $netRxKB[$netIndex]KB");

      my $i=$netIndex;
      $netRxKB[$i]=$netTxKB[$i]=$netRxPkt[$i]=$netTxPkt[$i]=0;
      $netRxErr[$i]=$netRxDrp[$i]=$netRxFifo[$i]=$netRxFra[$i]=$netRxCmp[$i]=$netRxMlt[$i]=0;
      $netTxErr[$i]=$netTxDrp[$i]=$netTxFifo[$i]=$netTxColl[$i]=$netTxCar[$i]=$netTxCmp[$i]=0;
    }

    # these are derived for simplicity of plotting
    $netRxErrs[$netIndex]=$netRxErr[$netIndex]+$netRxDrp[$netIndex]+
			  $netRxFifo[$netIndex]+$netRxFra[$netIndex];
    $netTxErrs[$netIndex]=$netTxErr[$netIndex]+$netTxDrp[$netIndex]+
			  $netTxFifo[$netIndex]+$netTxColl[$netIndex]+
			  $netTxCar[$netIndex];

    # Ethernet totals only, but no longer using anywhere
    if ($netNameNow=~/eth/)
    {
      $netEthRxKBTot+= $netRxKB[$netIndex];
      $netEthRxPktTot+=$netRxPkt[$netIndex];
      $netEthTxKBTot+= $netTxKB[$netIndex];
      $netEthTxPktTot+=$netTxPkt[$netIndex];
    }

    # at least for now, we're only worrying about totals on real network
    # first, always ignore those in ignore list
    if ($netNameNow!~/^lo|^sit|^bond|^vmnet|^vlan/ && ($netFilt eq '' || $netNameNow!~/$netFiltIgnore/))
    {
      # if filter specified, only include those we want.
      # NOTE - we >>>never<<< include aliased networks in the summary calculations
      if ($netNameNow!~/\./ && ($netFiltKeep eq '' || $netNameNow=~/$netFiltKeep/))
      {
        $netRxKBTot+= $netRxKB[$netIndex];
        $netRxPktTot+=$netRxPkt[$netIndex];
        $netTxKBTot+= $netTxKB[$netIndex];
        $netTxPktTot+=$netTxPkt[$netIndex];

        $netRxErrTot+= $netRxErr[$netIndex];
        $netRxDrpTot+= $netRxDrp[$netIndex];
        $netRxFifoTot+=$netRxFifo[$netIndex];
        $netRxFraTot+= $netRxFra[$netIndex];
        $netRxCmpTot+= $netRxCmp[$netIndex];
        $netRxMltTot+= $netRxMlt[$netIndex];
        $netTxErrTot+= $netTxErr[$netIndex];
        $netTxDrpTot+= $netTxDrp[$netIndex];
        $netTxFifoTot+=$netTxFifo[$netIndex];
        $netTxCollTot+=$netTxColl[$netIndex];
        $netTxCarTot+= $netTxCar[$netIndex];
        $netTxCmpTot+= $netTxCmp[$netIndex];

        $netRxErrsTot+=$netRxErrs[$netIndex];
        $netTxErrsTot+=$netTxErrs[$netIndex];
      }
    }

    $netName[$netIndex]=     $netNameNow;
    $netRxKBLast[$netIndex]= $netRxKBNow;
    $netRxPktLast[$netIndex]=$netRxPktNow;
    $netTxKBLast[$netIndex]= $netTxKBNow;
    $netTxPktLast[$netIndex]=$netTxPktNow;

    $netRxErrLast[$netIndex]=$netRxErrNow;
    $netRxDrpLast[$netIndex]=$netRxDrpNow;
    $netRxFifoLast[$netIndex]=$netRxFifoNow;
    $netRxFraLast[$netIndex]=$netRxFraNow;
    $netRxCmpLast[$netIndex]=$netRxCmpNow;
    $netRxMltLast[$netIndex]=$netRxMltNow;
    $netTxErrLast[$netIndex]=$netTxErrNow;
    $netTxDrpLast[$netIndex]=$netTxDrpNow;
    $netTxFifoLast[$netIndex]=$netTxFifoNow;
    $netTxCollLast[$netIndex]=$netTxCollNow;
    $netTxCarLast[$netIndex]=$netTxCarNow;
    $netTxCmpLast[$netIndex]=$netTxCmpNow;
  }

  #    N e t w o r k    S t a c k    S t a t s

  # note that even though each line type IS already unique, by including our own type
  # we get to skip a bunch of compares when not doing -st
  # also note the older versions ignored the IpExt data even though collected so I am too.
  elsif ($subsys=~/t/i && $type=~/^tcp-|^Tcp/)
  {
    # Data comes in pairs, the first line being the headers and the second the data.
    # if 'tcp-' present, this is V3.6.4 or more and by removing, we assure old/new data looks the same
    # but also, the earlier versions didn't write headers which can change from kernel to kernel!!!
    $type=~s/^tcp-//;
    $type=~s/:$//;

    # NEW TCP STATS
    if ($playback eq '' || $recVersion ge '3.6.4')
    {
      #  type always precedes data
      if ($data=~/^\d/)
      {
        my @vals=split(/\s+/, $data);

        # init 'last' variables here because we don't know how may there are in the normal init section of code
	# and since $intFirstSeen does't get cleared until second pass we also need to see if already defined
        for (my $i=0; !$intFirstSeen && $i<@vals; $i++)
        { $tcpData{$type}->{last}->[$i]=0    if !defined($tcpData{$type}->{last}->[$i]); }

        for (my $i=0; $i<@vals; $i++)
        {
          my $name=$tcpData{$type}->{hdr}->[$i];
          my $value=$vals[$i]-$tcpData{$type}->{last}->[$i];
          #print "Seen: $intFirstSeen Type: $type  Name: $name  I: $i  Val: $vals[$i] Last: $tcpData{$type}->{last}->[$i]\n"  if $i==0 && $type=~/Icmp/;

          $tcpData{$type}->{$name}=$value;
          $tcpData{$type}->{last}->[$i]=$vals[$i];
        }

    	# Error summaries for brief/plot data, nothing nothing for IpExt.
        if ($briefFlag || $plotFlag ne '')
        {
          $ipErrors=   $tcpData{Ip}->{InHdrErrors}+$tcpData{Ip}->{InAddrErrors}+
		       $tcpData{Ip}->{InUnknownProtos}+$tcpData{Ip}->{InDiscards}+
	   	       $tcpData{Ip}->{OutDiscards}+ $tcpData{Ip}->{ReasmFails}+
		       $tcpData{Ip}->{FragFails}					if $type eq 'Ip';
          $tcpErrors=  $tcpData{Tcp}->{AttemptFails}+$tcpData{Tcp}->{InErrs}	        if $type eq 'Tcp';
          $udpErrors=  $tcpData{Udp}->{NoPorts}+$tcpData{Udp}->{InErrors}		if $type eq 'Udp';
          $icmpErrors= $tcpData{Icmp}->{InErrors}+$tcpData{Icmp}->{InDestUnreachs}+
		       $tcpData{Icmp}->{OutErrors}				        if $type eq 'Icmp';
          $tcpExErrors=$tcpData{TcpExt}->{TCPLoss}+$tcpData{TcpExt}->{TCPFastRetrans}   if $type eq 'TcpExt';
        }
      }

      # header: only need to grab on the first interval we see
      elsif (!$intFirstSeen)
      {
        my @headers=split(/\s+/, $data);
        for (my $i=0; $i<@headers; $i++)
        { $tcpData{$type}->{hdr}->[$i]=$headers[$i]; }
      }
    }

    # OLD TCP STATS
    elsif ($type=~/^TcpExt/)    # this is the old way, IP header, but no TCP one
    {
      chomp $data;
      @tcpFields=split(/ /, $data);
      for ($i=0; $i<$NumTcpFields; $i++)
      {
        $tcpValue[$i]=fix($tcpFields[$i]-$tcpLast[$i]);
        $tcpLast[$i]=$tcpFields[$i];
        #print "$i: $tcpValue[$i] ";
      }

      # store old version data in new version structures even though the positions
      # may be wrong for some kernels.
      $tcpData{TcpExt}->{TCPPureAcks}=   $tcpValue[27];
      $tcpData{TcpExt}->{TCPHPAcks}=     $tcpValue[28];
      $tcpData{TcpExt}->{TCPLoss}=       $tcpValue[40];
      $tcpData{TcpExt}->{TCPFastRetrans}=$tcpValue[45];
    }
  }

  #    E L A N    S t a t s

  # we have to test the subsys first becaue $1 gets trashed if first
  elsif ($subsys=~/x/i && $type=~/^Elan(\d+)/)
  {
    $i=$1;
    if ($XVersion lt '5.20.0')
    {
      ($name, $value)=(split(/\s+/, $data))[0,1]    if $XVersion;
    }
    else
    {
      ($value, $name)=(split(/\s+/, $data))[0,1]    if $XVersion;
    }

    if ($value=~/^Send/ || $name=~/^Send/)
    {
      ($elanSendFail, $elanNeterrAtomic, $elanNeterrDma)=(split(/\s+/, $data))[1,3,5];
      $elanSendFail[$i]=    fix($elanSendFail-$elanSendFailLast[$i]);
      $elanNeterrAtomic[$i]=fix($elanNeterrAtomic-$elanNeterrAtomicLast[$i]);
      $elanNeterrDma[$i]=   fix($elanNeterrDma-$elanNeterrDmaLast[$i]);

      $elanSendFailTot+=    $elanSendFail[$i];
      $elanNeterrAtomicTot+=$elanNeterrAtomic[$i];
      $elanNeterrDmaTot+=   $elanNeterrDma[$i];

      $elanSendFailLast[$i]=    $elanSendFail;
      $elanNeterrAtomicLast[$i]=$elanNeterrAtomic;
      $elanNeterrDmaLast[$i]=   $elanNeterrDma;
    }
    elsif ($name=~/^Rx/)
    {  
      $elanRx[$i]=    fix($value-$elanRxLast[$i]);
      $elanRxLast[$i]=$value;
      $elanRxTot=     $elanRx[$i];
      $elanRxFlag=1;
      $elanTxFlag=$elanPutFlag=$elanGetFlag=$elanCompFlag=0;
    }
    elsif ($name=~/^Tx/)
    {
      $elanTx[$i]=    fix($value-$elanTxLast[$i]);
      $elanTxLast[$i]=$value;
      $elanTxTot=     $elanTx[$i];
      $elanTxFlag=1;
      $elanRxFlag=$elanPutFlag=$elanGetFlag=$elanCompFlag=0;
    }
    elsif ($name=~/^Put/)
    {
      $elanPut[$i]=    fix($value-$elanPutLast[$i]);
      $elanPutLast[$i]=$value;
      $elanPutTot=     $elanPut[$i];
      $elanPutFlag=1;
      $elanTxFlag=$elanRxFlag=$elanGetFlag=$elanCompFlag=0;
    }
    elsif ($name=~/^Get/)
    {
      $elanGet[$i]=    fix($value-$elanGetLast[$i]);
      $elanGetLast[$i]=$value;
      $elanGetTot=     $elanGet[$i];
      $elanGetFlag=1;
      $elanTxFlag=$elanRxFlag=$elanPutFlag=$elanCompFlag=0;
    }
    elsif ($name=~/^Comp/)
    {
      $elanComp[$i]=    fix($value-$elanCompLast[$i]);
      $elanCompLast[$i]=$value;
      $elanCompTot=     $elanComp[$i];
      $elanCompFlag=1;
      $elanTxFlag=$elanRxFlag=$elanPutFlag=$elanGetFlag=0;
    }
    elsif ($name=~/^MB/)
    {
      # NOTE - elan reports data in MB but we want it in KB to be
      #        consistent with other interconects
      if ($elanRxFlag)
      {      
        $elanRxMB=        fix($value-$elanRxMBLast[$i], $OneMB);
        $elanRxMBLast[$i]=$value;
        $elanRxKB[$i]=    $elanRxMB*1024;
        $elanRxKBTot=     $elanRxKB[$i];
      }
      elsif ($elanTxFlag)
      {
        $elanTxMB=        fix($value-$elanTxMBLast[$i], $OneMB);
        $elanTxMBLast[$i]=$value;
	$elanTxKB[$i]=    $elanTxMB*1024;
        $elanTxKBTot=     $elanTxKB[$i];
      }
      elsif ($elanPutFlag)
      {      
        $elanPutMB=        fix($value-$elanPutMBLast[$i], $OneMB);
        $elanPutMBLast[$i]=$value;
        $elanPutKB[$i]=    $elanPutMB*1024;
        $elanPutKBTot=     $elanPutKB[$i];
      }
      elsif ($elanGetFlag)
      {      
        $elanGetMB=        fix($value-$elanGetMBLast[$i], $OneMB);
        $elanGetMBLast[$i]=$value;
        $elanGetKB[$i]=    $elanGetMB*1024;
        $elanGetKBTot=     $elanGetKB[$i];
      }
      elsif ($elanCompFlag)
      {      
        $elanCompMB=        fix($value-$elanCompMBLast[$i], $OneMB);
        $elanCompMBLast[$i]=$value;
        $elanCompKB[$i]=    $elanCompMB*1024;
        $elanCompKBTot=     $elanCompKB[$i];
      }
      else
      {
        logmsg("W", "### Found elan MB without type flag set");
      }
    }
  }

  #    I n f i n i b a n d    S t a t s

  # we have to test the subsys first becaue $1 gets trashed if first
  elsif ($subsys=~/x/i && $type=~/^ib(\d+)/)
  {
    $i=$1;
    my ($port, @fieldsNow)=(split(/\s+/, $data))[0,4..19];

    # Only 1 of the two ports are actually active at any one time
    if ($HCAPorts[$i][$port])
    {
      # Remember which port is active.
      $HCAPortActive=$port;

      # Calculate values for each field based on 'last' values.
      $ibErrorsTot[$i]=0;
      for ($j=0; $j<16; $j++)
      {
        $fields[$j]=fix($fieldsNow[$j]-$ibFieldsLast[$i][$port][$j]);
        $ibFieldsLast[$i][$port][$j]=$fieldsNow[$j];

        # the first 12 are accumulated as a single error count and ultimately
        # reporting as anbsolute number and NOT a rate so don't use 'last'
        $ibErrorsTot[$i]+=$fieldsNow[$j]    if $j<12;
      }

      # Do individual counters, noting that the open fabric one has '-port' appended
      # and that their values are alredy absolute and not incrementing counters that
      # that need to be adjusted agaist previous versions
      if ($type=~/^ib(\d+)-(\d)/)
      {
        $ibTxKB[$i]=$fieldsNow[12]/256;
        $ibTx[$i]=  $fieldsNow[14];
        $ibRxKB[$i]=$fieldsNow[13]/256;
        $ibRx[$i]=  $fieldsNow[15];
      }
      else
      {
        $ibTxKB[$i]=$fields[12]/256;
        $ibTx[$i]=  $fields[14];
        $ibRxKB[$i]=$fields[13]/256;
        $ibRx[$i]=  $fields[15];
      }

      $ibTxKBTot+=$ibTxKB[$i];
      $ibTxTot+=  $ibTx[$i];
      $ibRxKBTot+=$ibRxKB[$i];
      $ibRxTot+=  $ibRx[$i];
      $ibErrorsTotTot+=$ibErrorsTot[$i];
    }
  }
}

# headers for plot formatted data
sub printPlotHeaders
{
  my $i;

  ##############################
  #    Core Plot Format Headers
  ##############################

  $headersAll='';
  $datetime=(!$utcFlag) ? "#Date${SEP}Time${SEP}" : "#UTC${SEP}";
  $headers=($filename ne '') ? "$commonHeader$datetime" : $datetime;

  if ($subsys=~/c/)
  {
    $headers.="[CPU]User%${SEP}[CPU]Nice%${SEP}[CPU]Sys%${SEP}[CPU]Wait%${SEP}";
    $headers.="[CPU]Irq%${SEP}[CPU]Soft%${SEP}[CPU]Steal%${SEP}[CPU]Idle%${SEP}[CPU]Totl%${SEP}";
    $headers.="[CPU]Intrpt$rate${SEP}[CPU]Ctx$rate${SEP}[CPU]Proc$rate${SEP}";
    $headers.="[CPU]ProcQue${SEP}[CPU]ProcRun${SEP}[CPU]L-Avg1${SEP}[CPU]L-Avg5${SEP}[CPU]L-Avg15${SEP}";
    $headers.="[CPU]RunTot${SEP}[CPU]BlkTot${SEP}";
  }

  if ($subsys=~/m/)
  {
    $headers.="[MEM]Tot${SEP}[MEM]Used${SEP}[MEM]Free${SEP}[MEM]Shared${SEP}[MEM]Buf${SEP}[MEM]Cached${SEP}";
    $headers.="[MEM]Slab${SEP}[MEM]Map${SEP}[MEM]Anon${SEP}[MEM]Commit${SEP}[MEM]Locked${SEP}";    # always from V1.7.5 forward
    $headers.="[MEM]SwapTot${SEP}[MEM]SwapUsed${SEP}[MEM]SwapFree${SEP}[MEM]SwapIn${SEP}[MEM]SwapOut${SEP}";
    $headers.="[MEM]Dirty${SEP}[MEM]Clean${SEP}[MEM]Laundry${SEP}[MEM]Inactive${SEP}";
    $headers.="[MEM]PageIn${SEP}[MEM]PageOut${SEP}[MEM]PageFaults${SEP}[MEM]PageMajFaults${SEP}";
    $headers.="[MEM]HugeTotal${SEP}[MEM]HugeFree${SEP}[MEM]HugeRsvd${SEP}[MEM]SUnreclaim${SEP}";
  }

  if ($subsys=~/s/)
  {
    $headers.="[SOCK]Used${SEP}[SOCK]Tcp${SEP}[SOCK]Orph${SEP}[SOCK]Tw${SEP}[SOCK]Alloc${SEP}";
    $headers.="[SOCK]Mem${SEP}[SOCK]Udp${SEP}[SOCK]Raw${SEP}[SOCK]Frag${SEP}[SOCK]FragMem${SEP}";
  }

  if ($subsys=~/n/)
  {
    $headers.="[NET]RxPktTot${SEP}[NET]TxPktTot${SEP}[NET]RxKBTot${SEP}[NET]TxKBTot${SEP}";
    $headers.="[NET]RxCmpTot${SEP}[NET]RxMltTot${SEP}[NET]TxCmpTot${SEP}";
    $headers.="[NET]RxErrsTot${SEP}[NET]TxErrsTot${SEP}";
  }

  if ($subsys=~/d/)
  {
    $headers.="[DSK]ReadTot${SEP}[DSK]WriteTot${SEP}[DSK]OpsTot${SEP}";
    $headers.="[DSK]ReadKBTot${SEP}[DSK]WriteKBTot${SEP}[DSK]KbTot${SEP}";
    $headers.="[DSK]ReadMrgTot${SEP}[DSK]WriteMrgTot${SEP}[DSK]MrgTot${SEP}";
  }

  if ($subsys=~/i/)
  {
    $headers.="[INODE]NumDentry${SEP}[INODE]openFiles${SEP}[INODE]MaxFile%${SEP}[INODE]used${SEP}";
  }

  if ($subsys=~/f/)
  {
    # Alway write client/server fields
    $headers.="[NFS]ReadsS${SEP}[NFS]WritesS${SEP}[NFS]MetaS${SEP}[NFS]CommitS${SEP}";
    $headers.="[NFS]Udp${SEP}[NFS]Tcp${SEP}[NFS]TcpConn${SEP}[NFS]BadAuth${SEP}[NFS]BadClient${SEP}";
    $headers.="[NFS]ReadsC${SEP}[NFS]WritesC${SEP}[NFS]MetaC${SEP}[NFS]CommitC${SEP}";
    $headers.="[NFS]Retrans${SEP}[NFS]AuthRef${SEP}";
  }

  if ($subsys=~/l/)
  {
    if ($reportMdsFlag)
    {
      $headers.="[MDS]Getattr${SEP}[MDS]GetattrLock${SEP}[MDS]Statfs${SEP}[MDS]Sync${SEP}";
      $headers.="[MDS]Getxattr${SEP}[MDS]Setxattr${SEP}[MDS]Connect${SEP}[MDS]Disconnect${SEP}";
      $headers.="[MDS]Reint${SEP}[MDS]Create${SEP}[MDS]Link${SEP}[MDS]Setattr${SEP}";
      $headers.="[MDS]Rename${SEP}[MDS]Unlink${SEP}";
    }

    if ($reportOstFlag)
    {
      # We always report basic I/O independent of what user selects with --lustopts
      $headers.="[OST]Read${SEP}[OST]ReadKB${SEP}[OST]Write${SEP}[OST]WriteKB${SEP}";
      if ($lustOpts=~/B/)
      {
        foreach my $i (@brwBuckets)
        { $headers.="[OSTB]r${i}P${SEP}"; }
        foreach my $i (@brwBuckets)
        { $headers.="[OSTB]w${i}P${SEP}"; }
      }
    }
    if ($lustOpts=~/D/)
    {
      $headers.="[OSTD]Rds${SEP}[OSTD]Rdk${SEP}[OSTD]Wrts${SEP}[OSTD]Wrtk${SEP}";
      foreach my $i (@diskBuckets)
      { $headers.="[OSTD]r${i}K${SEP}"; }
      foreach my $i (@diskBuckets)
      { $headers.="[OSTD]w${i}K${SEP}"; }
    }

    if ($reportCltFlag)
    {
      # 4 different sizes based on whether which value for --lustopts chosen
      # NOTE - order IS critical
      $headers.="[CLT]Reads${SEP}[CLT]ReadKB${SEP}[CLT]Writes${SEP}[CLT]WriteKB${SEP}";
      $headers.="[CLTM]Open${SEP}[CLTM]Close${SEP}[CLTM]GAttr${SEP}[CLTM]SAttr${SEP}[CLTM]Seek${SEP}[CLTM]FSync${SEP}[CLTM]DrtHit${SEP}[CLTM]DrtMis${SEP}"
		    if $lustOpts=~/M/;
      $headers.="[CLTR]Pend${SEP}[CLTR]Hits${SEP}[CLTR]Misses${SEP}[CLTR]NotCon${SEP}[CLTR]MisWin${SEP}[CLTR]FalGrab${SEP}[CLTR]LckFal${SEP}[CLTR]Discrd${SEP}[CLTR]ZFile${SEP}[CLTR]ZerWin${SEP}[CLTR]RA2Eof${SEP}[CLTR]HitMax${SEP}[CLTR]Wrong${SEP}"
		    if $lustOpts=~/R/;
      if ($lustOpts=~/B/)
      {
        foreach my $i (@brwBuckets)
        { $headers.="[CLTB]r${i}P${SEP}"; }
        foreach my $i (@brwBuckets)
        { $headers.="[CLTB]w${i}P${SEP}"; }
      }
    }
  }

  if ($subsys=~/x/)
  {
    my $int=($NumXRails) ? 'ELAN' : 'IB';
    $headers.="[$int]InPkt${SEP}[$int]OutPkt${SEP}[$int]InKB${SEP}[$int]OutKB${SEP}[$int]Err${SEP}";
  }

  if ($subsys=~/t/)
  {
    # fixed size easier for plotting, keeping Loss & FTrans for historical reasons...
    $headers.="[TCP]IpErr${SEP}[TCP]TcpErr${SEP}[TCP]UdpErr${SEP}[TCP]IcmpErr${SEP}[TCP]Loss${SEP}[TCP]FTrans${SEP}";
  }

  if ($subsys=~/y/)
  {
    $headers.="[SLAB]ObjInUse${SEP}[SLAB]ObjInUseB${SEP}[SLAB]ObjAll${SEP}[SLAB]ObjAllB${SEP}";
    $headers.="[SLAB]InUse${SEP}[SLAB]InUseB${SEP}[SLAB]All${SEP}[SLAB]AllB${SEP}[SLAB]CacheInUse${SEP}[SLAB]CacheTotal${SEP}";
  }

  if ($subsys=~/b/)
  {
    for (my $i=0; $i<11; $i++)
    {
      $headers.=sprintf("[BUD]%dPage%s$SEP", 2**$i, $i==0 ? '' : 's');
    }
  }

  # custom import headers get appended here if doing summary data.
  for (my $i=0; $impSummaryFlag && $i<$impNumMods; $i++)
  {
    &{$impPrintPlot[$i]}(1, \$headers)    if $impOpts[$i]=~/s/;
  }

  # only if at least one core subsystem selected.  if not, make sure
  # $headersAll contains the date/time in case writing to the terminal
  writeData(0, '', \$headers, $LOG, $ZLOG, 'log', \$headersAll)    if $coreFlag || $impSummaryFlag;
  $headersAll=$headers    if !$coreFlag;

  #################################
  #    Non-Core Plot Format Headers
  #################################

  # here's the deal with these.  if writing to files, each file always gets
  # their own headers.  However, if writing to the terminal we want one long
  # string begining with a single date/time AND we don't bother with the 
  # common header.

  $cpuHeaders=$dskHeaders=$envHeaders=$nfsHeaders=$netHeaders='';
  $ostHeaders=$mdsHeaders=$cltHeaders=$tcpHeaders=$elanHeaders='';

  # Whenever we print a header to a file, we do both the common header
  # and date/time.  Remember, if we're printing the terminal, this is
  # completely ignored by writeData().
  $ch=($filename ne '') ? "$commonHeader$datetime" : $datetime;

  if ($subsys=~/C/)
  { 
    for ($i=0; $i<$NumCpus; $i++)
    {
      $cpuHeaders.="[CPU:$i]User%${SEP}[CPU:$i]Nice%${SEP}[CPU:$i]Sys%${SEP}";
      $cpuHeaders.="[CPU:$i]Wait%${SEP}[CPU:$i]Irq%${SEP}[CPU:$i]Soft%${SEP}";
      $cpuHeaders.="[CPU:$i]Steal%${SEP}[CPU:$i]Idle%${SEP}[CPU:$i]Totl%${SEP}";
      $cpuHeaders.="[CPU:$i]Intrpt${SEP}";
    }
    writeData(0, $ch, \$cpuHeaders, CPU, $ZCPU, 'cpu', \$headersAll);
  }

  if ($subsys=~/D/ && $options!~/x/)
  {
    for (my $i=0; $i<@dskOrder; $i++)
    {
      $dskName=$dskOrder[$i];
      next    if ($dskFiltKeep eq '' && $dskName=~/$dskFiltIgnore/) || ($dskFiltKeep ne '' && $dskName!~/$dskFiltKeep/);

      $temp= "[DSK]Name${SEP}[DSK]Reads${SEP}[DSK]RMerge${SEP}[DSK]RKBytes${SEP}";
      $temp.="[DSK]Writes${SEP}[DSK]WMerge${SEP}[DSK]WKBytes${SEP}[DSK]Request${SEP}";
      $temp.="[DSK]QueLen${SEP}[DSK]Wait${SEP}[DSK]SvcTim${SEP}[DSK]Util${SEP}";
      $temp=~s/DSK/DSK:$dskName/g;
      $temp=~s/cciss\///g;
      $dskHeaders.=$temp;
    }
    writeData(0, $ch, \$dskHeaders, DSK, $ZDSK, 'dsk', \$headersAll);
  }

  if ($subsys=~/E/)
  {
    foreach $key (sort keys %$ipmiData)
    {
      for (my $i=0; $i<scalar(@{$ipmiData->{$key}}); $i++)
      {
        my $name=$ipmiData->{$key}->[$i]->{name};
        my $inst=($key!~/power/ && $ipmiData->{$key}->[$i]->{inst} ne '-1') ? $ipmiData->{$key}->[$i]->{inst} : '';
        $envHeaders.=sprintf("[ENV:$name$inst]Speed$SEP")   if $key=~/fan/;
        $envHeaders.=sprintf("[ENV:$name$inst]Temp$SEP")    if $key=~/temp/;
        $envHeaders.=sprintf("[ENV:$name]Watts$SEP")        if $key=~/power/;
      }
    }
    writeData(0, $ch, \$envHeaders, ENV, $ZENV, 'env', \$headersAll);
  }

  if ($subsys=~/F/)
  {
    if ($nfs2CFlag)
    {
      my $type='NFS:2cd';
      $nfsHeaders.="[$type]Read${SEP}[$type]Write${SEP}[$type]Lookup${SEP}[$type]Getattr${SEP}[$type]Setattr${SEP}[$type]Readdir${SEP}";
      $nfsHeaders.="[$type]Create${SEP}[$type]Remove${SEP}[$type]Rename${SEP}[$type]Link${SEP}[$type]ReadLink${SEP}[$type]Null${SEP}";
      $nfsHeaders.="[$type]Symlink${SEP}[$type]Mkdir${SEP}[$type]Rmdir${SEP}[$type]Fsstat${SEP}";
    }

    if ($nfs2SFlag)
    {
      my $type='NFS:2sd';
      $nfsHeaders.="[$type]Read${SEP}[$type]Write${SEP}[$type]Lookup${SEP}[$type]Getattr${SEP}[$type]Setattr${SEP}[$type]Readdir${SEP}";
      $nfsHeaders.="[$type]Create${SEP}[$type]Remove${SEP}[$type]Rename${SEP}[$type]Link${SEP}[$type]ReadLink${SEP}[$type]Null${SEP}";
      $nfsHeaders.="[$type]Symlink${SEP}[$type]Mkdir${SEP}[$type]Rmdir${SEP}[$type]Fsstat${SEP}";
    }

    if ($nfs3CFlag)
    {
      my $type='NFS:3cd';
      $nfsHeaders.="[$type]Read${SEP}[$type]Write${SEP}[$type]Commit${SEP}[$type]Lookup${SEP}";
      $nfsHeaders.="[$type]Access${SEP}[$type]Getattr${SEP}[$type]Setattr${SEP}[$type]Readdir${SEP}";
      $nfsHeaders.="[$type]Create${SEP}[$type]Remove${SEP}[$type]Rename${SEP}[$type]Link${SEP}[$type]ReadLink${SEP}[$type]Null${SEP}";
      $nfsHeaders.="[$type]Symlink${SEP}[$type]Mkdir${SEP}[$type]Rmdir${SEP}[$type]Fsstat${SEP}";
      $nfsHeaders.="[$type]Fsinfo${SEP}[$type]Pathconf${SEP}[$type]Mknod${SEP}[$type]Readdirplus${SEP}";
    }

    if ($nfs3SFlag)
    {
      my $type='NFS:3sd';
      $nfsHeaders.="[$type]Read${SEP}[$type]Write${SEP}[$type]Commit${SEP}[$type]Lookup${SEP}";
      $nfsHeaders.="[$type]Access${SEP}[$type]Getattr${SEP}[$type]Setattr${SEP}[$type]Readdir${SEP}";
      $nfsHeaders.="[$type]Create${SEP}[$type]Remove${SEP}[$type]Rename${SEP}[$type]Link${SEP}[$type]ReadLink${SEP}[$type]Null${SEP}";
      $nfsHeaders.="[$type]Symlink${SEP}[$type]Mkdir${SEP}[$type]Rmdir${SEP}[$type]Fsstat${SEP}";
      $nfsHeaders.="[$type]Fsinfo${SEP}[$type]Pathconf${SEP}[$type]Mknod${SEP}[$type]Readdirplus${SEP}";
    }

    if ($nfs4CFlag)
    {
      my $type='NFS:4cd';
      $nfsHeaders.="[$type]Read${SEP}[$type]Write${SEP}[$type]Commit${SEP}[$type]Lookup${SEP}";
      $nfsHeaders.="[$type]Access${SEP}[$type]Getattr${SEP}[$type]Setattr${SEP}[$type]Readdir${SEP}";
      $nfsHeaders.="[$type]Create${SEP}[$type]Remove${SEP}[$type]Rename${SEP}[$type]Link${SEP}[$type]ReadLink${SEP}[$type]Null${SEP}";
      $nfsHeaders.="[$type]Symlink${SEP}[$type]Fsinfo${SEP}[$type]Pathconf${SEP}";
    }

    if ($nfs4SFlag)
    {
      my $type='NFS:4sd';
      $nfsHeaders.="[$type]Read${SEP}[$type]Write${SEP}[$type]Commit${SEP}[$type]Lookup${SEP}";
      $nfsHeaders.="[$type]Access${SEP}[$type]Getattr${SEP}[$type]Setattr${SEP}[$type]Readdir${SEP}";
      $nfsHeaders.="[$type]Create${SEP}[$type]Remove${SEP}[$type]Rename${SEP}[$type]Link${SEP}[$type]ReadLink${SEP}";
    }

    writeData(0, $ch, \$nfsHeaders, NFS, $ZNFS, 'nfs', \$headersAll);
   }

  if ($subsys=~/M/)
  {
    $numaHeaders='';
    for ($i=0; $i<$CpuNodes; $i++)
    {
      $numaHeaders.="[NUMA:$i]Used${SEP}[NUMA:$i]Free${SEP}[NUMA:$i]Slab${SEP}[NUMA:$i]Mapped${SEP}";
      $numaHeaders.="[NUMA:$i]Anon${SEP}[NUMA:$i]Inactive${SEP}[NUMA:$i]Hits${SEP}";
    }
    writeData(0, $ch, \$numaHeaders, NUMA, $ZNUMA, 'numa', \$headersAll);
  }

  if ($subsys=~/N/)
  {
    for (my $i=0; $i<@netOrder; $i++)
    {
      # remember, order include net speed
      $netName=$netOrder[$i];
      $netName=~s/:.*//;
      next    if ($netFiltKeep eq '' && $netName=~/$netFiltIgnore/) || ($netFiltKeep ne '' && $netName!~/$netFiltKeep/);

      $temp= "[NET]Name${SEP}[NET]RxPkt${SEP}[NET]TxPkt${SEP}[NET]RxKB${SEP}[NET]TxKB${SEP}";
      $temp.="[NET]RxErr${SEP}[NET]RxDrp${SEP}[NET]RxFifo${SEP}[NET]RxFra${SEP}[NET]RxCmp${SEP}[NET]RxMlt${SEP}";
      $temp.="[NET]TxErr${SEP}[NET]TxDrp${SEP}[NET]TxFifo${SEP}[NET]TxColl${SEP}[NET]TxCar${SEP}";
      $temp.="[NET]TxCmp${SEP}[NET]RxErrs${SEP}[NET]TxErrs${SEP}";
      $temp=~s/NET/NET:$netName/g;
      $temp=~s/:]/]/g;
      $netHeaders.=$temp;
    }
    writeData(0, $ch, \$netHeaders, NET, $ZNET, 'net', \$headersAll);
  }

  if ($subsys=~/L/)
  {
    if ($reportOstFlag)
    {
      # We always start with this section
      # BRW stats are optional, but if there group them together separately.

      for ($i=0; $i<$NumOst; $i++)
      { 
        $inst=$lustreOsts[$i];
        $ostHeaders.="[OST:$inst]Ost${SEP}[OST:$inst]Read${SEP}[OST:$inst]ReadKB${SEP}[OST:$inst]Write${SEP}[OST:$inst]WriteKB${SEP}";
      }

      for ($i=0; $lustOpts=~/B/ && $i<$NumOst; $i++)
      { 
        $inst=$lustreOsts[$i];
        foreach my $j (@brwBuckets)
        { $ostHeaders.="[OSTB:$inst]r$j${SEP}"; }
        foreach my $j (@brwBuckets)
        { $ostHeaders.="[OSTB:$inst]w$j${SEP}"; }
      }
      writeData(0, $ch, \$ostHeaders, OST, $ZOST, 'ost', \$headersAll);
    }

    if ($reportCltFlag)
    {
      $temp='';
      if ($lustOpts=~/O/)  # client OST details
      {
	# we always record I/O in one chunk
	for ($i=0; $i<$NumLustreCltOsts; $i++)
        {
          $inst=$lustreCltOsts[$i];
          $temp.="[CLT:$inst]FileSys${SEP}[CLT:$inst]Ost${SEP}[CLT:$inst]Reads${SEP}[CLT:$inst]ReadKB${SEP}[CLT:$inst]Writes${SEP}[CLT:$inst]WriteKB${SEP}";
        }

	# and if specified, brw stats follow
        if ($lustOpts=~/B/)
        {
  	  for ($i=0; $i<$NumLustreCltOsts; $i++)
          {
            $inst=$lustreCltOsts[$i];
            foreach my $j (@brwBuckets)
            { $temp.="[CLTB:$inst]r${j}P${SEP}"; }
            foreach my $j (@brwBuckets)
            { $temp.="[CLTB:$inst]w${j}P${SEP}"; }
	  }
	}
      }
      else  # just fs details
      {
	# just like with --lustopts O, these three follow each other in groups
	for ($i=0; $i<$NumLustreFS; $i++)
        {
          $inst=$lustreCltFS[$i];
          $temp.="[CLT:$inst]FileSys${SEP}[CLT:$inst]Reads${SEP}[CLT:$inst]ReadKB${SEP}[CLT:$inst]Writes${SEP}[CLT:$inst]WriteKB${SEP}";
        }
	for ($i=0; $lustOpts=~/M/ && $i<$NumLustreFS; $i++)
        {
          $inst=$lustreCltFS[$i];
	  $temp.="[CLTM:$inst]Open${SEP}[CLTM:$inst]Close${SEP}[CLTM:$inst]GAttr${SEP}[CLTM:$inst]SAttr${SEP}";
          $temp.="[CLTM:$inst]Seek${SEP}[CLTM:$inst]Fsync${SEP}[CLTM:$inst]DrtHit${SEP}[CLTM:$inst]DrtMis${SEP}";
        }
        for ($i=0; $lustOpts=~/R/ && $i<$NumLustreFS; $i++)
        {
          $inst=$lustreCltFS[$i];
          $temp.="[CLTR:$inst]Pend${SEP}[CLTR:$inst]Hits${SEP}[CLTR:$inst]Misses${SEP}[CLTR:$inst]NotCon${SEP}[CLTR:$inst]MisWin${SEP}[CLTR:$inst]FalGrab${SEP}[CLTR:$inst]LckFal${SEP}";
          $temp.="[CLTR:$inst]Discrd${SEP}[CLTR:$inst]ZFile${SEP}[CLTR:$inst]ZerWin${SEP}[CLTR:$inst]RA2Eof${SEP}[CLTR:$inst]HitMax${SEP}[CLTR:$inst]WrongMax${SEP}";
	}
      }
      $cltHeaders.=$temp;
      writeData(0, $ch, \$cltHeaders, CLT, $ZCLT, 'clt', \$headersAll);
    }

    if ($lustOpts=~/D/)
    {
      $rdHeader="[OSTD]rds${SEP}[OSTD]rdkb${SEP}";
      $wrHeader="[OSTD]wrs${SEP}[OSTD]wrkb${SEP}";
      foreach my $i (@diskBuckets)
      { $rdHeader.="[OSTD]r${i}K${SEP}"; }
      foreach my $i (@diskBuckets)
      { $wrHeader.="[OSTD]w${i}K${SEP}"; }

      for ($i=0; $i<$NumLusDisks; $i++)
      {
        $temp="[OSTD]Disk${SEP}$rdHeader${SEP}$wrHeader";
        $temp=~s/OSTD/OSTD:$LusDiskNames[$i]/g;
	$blkHeaders.="$temp${SEP}";
      }
      writeData(0, $ch, \$blkHeaders, BLK, $ZBLK, 'blk', \$headersAll);
    }
  }

  if ($subsys=~/T/)
  {
    # This is going to be big!!! 
    for my $type ('Ip', 'Tcp', 'Udp', 'Icmp', 'IpExt', 'TcpExt')
    {
      next    if $type eq 'Ip'     && $tcpFilt!~/i/;
      next    if $type eq 'Tcp'    && $tcpFilt!~/t/;
      next    if $type eq 'Udp'    && $tcpFilt!~/u/;
      next    if $type eq 'Icmp'   && $tcpFilt!~/c/;
      next    if $type eq 'IpExt'  && $tcpFilt!~/I/;
      next    if $type eq 'TcpExt' && $tcpFilt!~/T/;

      foreach my $header (@{$tcpData{$type}->{hdr}})
      { $tcpHeaders.="[TCPD]$header$SEP"; }
    }
    writeData(0, $ch, \$tcpHeaders, TCP, $ZTCP, 'tcp', \$headersAll);
  }

  if ($subsys=~/X/ && $NumXRails)
  {
    for ($i=0; $i<$NumXRails; $i++)
    {
      $elanHeaders.="[ELAN:$i]Rail${SEP}[ELAN:$i]Rx${SEP}[ELAN:$i]Tx${SEP}[ELAN:$i]RxKB${SEP}[ELAN:$i]TxKB${SEP}[ELAN:$i]Get${SEP}[ELAN:$i]Put${SEP}[ELAN:$i]GetKB${SEP}[ELAN:$i]PutKB${SEP}[ELAN:$i]Comp${SEP}[ELAN:$i]CompKB${SEP}[ELAN:$i]SendFail${SEP}[ELAN:$i]Atomic${SEP}[ELAN:$i]DMA${SEP}";
    }
    writeData(0, $ch, \$elanHeaders, ELN, $ZELN, 'eln', \$headersAll);
  }

  if ($subsys=~/X/ && $NumHCAs)
  {
    for ($i=0; $i<$NumHCAs; $i++)
    {
      $ibHeaders.="[IB:$i]HCA${SEP}[IB:$i]InPkt${SEP}[IB:$i]OutPkt${SEP}[IB:$i]InKB${SEP}[IB:$i]OutKB${SEP}[IB:$i]Err${SEP}";
    }
    writeData(0, $ch, \$ibHeaders, IB, $ZIB, 'ib', \$headersAll);
  }

  $budHeaders='';
  if ($subsys=~/B/)
  {
    for (my $i=0; $i<$NumBud; $i++)
    {
      my $buddyName="$buddyZone[$i]-$buddyNode[$i]";
      $budHeaders.="[BUD:$buddyName]Node${SEP}[BUD:$buddyName]Zone${SEP}";
      for (my $j=0; $j<11; $j++)
      {
        $budHeaders.=sprintf("[BUD:$buddyName]%dPage%s$SEP", 2**$j, $j==0 ? '' : 's');
      }
    }
    writeData(0, $ch, \$budHeaders, BUD, $ZBUD, 'bud', \$headersAll);
  }

  # only make call(s) if respective modules if detail reporting has been requested
  for (my $i=0; $impDetailFlag && $i<$impNumMods; $i++)
  {
    if ($impOpts[$i]=~/d/)
    {
      my $impHeaders='';
      &{$impPrintPlot[$i]}(2, \$impHeaders);
      writeData(0, $ch, \$impHeaders, $impText[$i], $impGz[$i], 'imp-$i', \$headersAll);
    }
  }

  # When going to the terminal OR socket we need a final call with no 'data' 
  # to write.  Also note that there is a final separator that needs to be removed.
  # It also turns out if doing --export -P, THAT module is responsible for sending
  # data over the socket and the plot data ONLY gets written locally.
  # Finally, if there is an error writing to a socket, stop trying to record anything else
  # as it's probably a broken socket and '!$doneFlag' has been set and we'll exit cleanly
  $headersAll=~s/$SEP$//;
  if (!$logToFileFlag || ($sockFlag && $export eq ''))
  {
    return    if writeData(1, '', undef, $LOG, undef, undef, \$headersAll)==0;
  }

  #################################
  #    Exception File Headers
  #################################

  if ($options=~/x/i)
  {
    if ($subsys=~/D/)
    {
      $dskHeaders="Num${SEP}";
      $dskHeaders.="[DISKX]Name${SEP}[DISKX]Reads${SEP}[DISKX]Merged${SEP}[DISKX]KBytes${SEP}[DISKX]Writes${SEP}[DISKX]Merged${SEP}";
      $dskHeaders.="[DISKX]KBytes${SEP}[DISKX]Request${SEP}[DISKX]QueLen${SEP}[DISKX]Wait${SEP}[DISKX]SvcTim${SEP}[DISKX]Util\n";

      # Since we never write exception data over a socket the last parameter is undef.
      writeData(0, $ch, \$dskHeaders, DSKX, $ZDSKX, 'dskx', undef);
    }
  }
  $headersPrinted=1;
}

sub intervalPrint
{
  my $seconds=shift;

  # If seconds end in .000, $seconds comes across as integer with no $usecs!
  ($seconds, $usecs)=split(/\./, $seconds);
  $usecs='000'    if !defined($usecs);    # in case user specifies -om
  if ($hiResFlag)
  {
    $usecs=substr("${usecs}00", 0, 3);
    $seconds.=".$usecs";
  }

  # This is causing confusion because this ALWAYS gets incremented even if no
  # output, such as when we only interval2 data
  $totalCounter++;

  my $tempSubsys=$subsys;
  $tempSubsys=~s/Y//    if $slabAnalOnlyFlag;
  $tempSubsys=~s/Z//    if $procAnalOnlyFlag;

  printPlot($seconds, $usecs)     if  $plotFlag && ($tempSubsys ne '' || $import ne '');
  printTerm($seconds, $usecs)     if !$plotFlag && $expName eq '';
  procAnalyze($seconds, $usecs)   if  $procAnalFlag && $interval2Print;
  slabAnalyze($seconds, $usecs)   if  $slabAnalFlag && $interval2Print;

  if ($expName ne '')
  {
    logdiag('export data')    if $utimeMask & 1;
    &$expName($expOpts);
    exit(0)    if $showColFlag;    
  }
}

# anything that needs to be derived should be done only once and this is the place
sub derived
{
  $swapUsed=$swapTotal-$swapFree;
  $swapUsedC=$swapUsed-$swapUsedLast;
  $swapUsedLast=$swapUsed;

  $memUsed=$memTot-$memFree;
  $memUsedC=$memUsed-$memUsedLast;
  $memUsedLast=$memUsed;
}

###########################
#    P l o t    F o r m a t
###########################

sub printPlot
{
  my $seconds=shift;
  my $usecs=  shift;
  my ($datestamp, $time, $hh, $mm, $ss, $mday, $mon, $year, $i, $j);

  # We always print some form of date and time in plot format and in the case of
  # --utc, it's a single value.  Now that I'm pulling out usecs for utc we
  # probably don't have to pass it as the second parameter.
  $utcSecs=(split(/\./, $seconds))[0];
  ($ss, $mm, $hh, $mday, $mon, $year)=localtime($seconds);
  $date=($options=~/d/) ?
         sprintf("%02d/%02d", $mon+1, $mday) :
         sprintf("%d%02d%02d", $year+1900, $mon+1, $mday);
  $time= sprintf("%02d:%02d:%02d", $hh, $mm, $ss);
  my $datetime=(!$utcFlag) ? "$date$SEP$time": $utcSecs;
  $datetime.=".$usecs"    if $options=~/m/;

  # slab detail and processes have their own print routines because they
  # do multiple lines of output and can't be mixed with anything else.
  # Furthermore, if we're doing -rawtoo, we DON'T generate these files since
  # the data is already being recorded in the raw file and we don't want to do
  # both

  if (!$rawtooFlag && $subsys=~/[YZ]/ && $interval2Print)
  {
    printPlotSlab($date, $time)    if $subsys=~/Y/ && !$slabAnalOnlyFlag;
    printPlotProc($date, $time)    if $subsys=~/Z/ && !$procAnalOnlyFlag;
    return    if $subsys=~/^[YZ]$/;    # we're done if ONLY printing slabs or processes
  }

  # Print headers noting that by default $headerRepeat set to 0 for -P.  Also note we have to
  # get more elaborate for terminal/file-based plot data.  On the terminal when HR is 0, we only
  # want one header but when going to files we ALWAYS want a new header each day when 
  # $headersPrinted gets reset to 0.
  $interval1Counter++;
  printPlotHeaders()    if ($headerRepeat==0 && $filename eq '' && $interval1Counter==1) ||
                           ($headerRepeat==0 && $filename ne '' && !$headersPrinted) ||
                           ($headerRepeat>0  && ($interval1Counter % $headerRepeat)==1);
  exit(0)    if $showColFlag;

  #######################
  #    C O R E    D A T A
  #######################

  my $netErrors=0;
  $plot=$oneline='';
  if ($coreFlag || $impSummaryFlag)
  {
    # CPU Data cols
    if ($subsys=~/c/)
    {
      $i=$NumCpus;
      $plot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
                $userP[$i], $niceP[$i], $sysP[$i], $waitP[$i],
                $irqP[$i], $softP[$i], $stealP[$i], $idleP[$i], $totlP[$i]);
      $plot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%4.2f$SEP%4.2f$SEP%4.2f$SEP%d$SEP%d",
                $intrpt/$intSecs, $ctxt/$intSecs, $proc/$intSecs,
                $loadQue, $loadRun, $loadAvg1, $loadAvg5, $loadAvg15, $procsRun, $procsBlock);
    }

    # MEM
    if ($subsys=~/m/)
    {
      $plot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
                $memTot, $memUsed, $memFree, $memShared, $memBuf, $memCached); 
      $plot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS", $memSlab, $memMap, $memAnon, $memCommit, $memLocked);   # Always from V1.7.5 forward
      $plot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
                $swapTotal, $swapUsed, $swapFree, $swapin/$intSecs, $swapout/$intSecs,
                $memDirty, $clean, $laundry, $memInact,
                $pagein/$intSecs, $pageout/$intSecs, $pagefault/$intSecs, $pagemajfault/$intSecs);
      $plot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS", $memHugeTot, $memHugeFree, $memHugeRsvd, $memSUnreclaim);
    }

    # SOCKETS
    if ($subsys=~/s/)
    {
      $plot.="$SEP$sockUsed$SEP$sockTcp$SEP$sockOrphan$SEP$sockTw$SEP$sockAlloc";
      $plot.="$SEP$sockMem$SEP$sockUdp$SEP$sockRaw$SEP$sockFrag$SEP$sockFragM";
    }

    # NETWORKS
    if ($subsys=~/n/)
    {
      # NOTE - rx/tx errs are the totals of all error counters
      $plot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
                $netRxPktTot/$intSecs, $netTxPktTot/$intSecs,
                $netRxKBTot/$intSecs,  $netTxKBTot/$intSecs,
                $netRxCmpTot/$intSecs, $netRxMltTot/$intSecs,
                $netTxCmpTot/$intSecs, $netRxErrsTot/$intSecs,
                $netTxErrsTot/$intSecs);
      $netErrors=$netRxErrsTot+$netTxErrsTot;
    }

    # DISKS
    if ($subsys=~/d/)
    {
      $plot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
                $dskReadTot/$intSecs,    $dskWriteTot/$intSecs,    $dskOpsTot/$intSecs,
                $dskReadKBTot/$intSecs,  $dskWriteKBTot/$intSecs,  ($dskReadKBTot+$dskWriteKBTot)/$intSecs,
                $dskReadMrgTot/$intSecs, $dskWriteMrgTot/$intSecs, ($dskReadMrgTot+$dskWriteMrgTot)/$intSecs);
    }

    # INODES
    if ($subsys=~/i/)
    {
      $plot.=sprintf("$SEP%d$SEP%d$SEP%$FS$SEP%d",
        $dentryNum, $filesAlloc,  $filesMax ? $filesAlloc*100/$filesMax : 0, $inodeUsed);
    }

    # NFS
    if ($subsys=~/f/)
    {
      $plot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
            $nfsSReadsTot/$intSecs,  $nfsSWritesTot/$intSecs, $nfsSMetaTot/$intSecs, 
            $nfsSCommitTot/$intSecs, $nfsUdpTot/$intSecs,     $nfsTcpTot/$intSecs, 
            $nfsTcpConnTot/$intSecs, $rpcBadAuthTot/$intSecs, $rpcBadClntTot/$intSecs);
      $plot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
            $nfsCReadsTot/$intSecs,  $nfsCWritesTot/$intSecs, $nfsCMetaTot/$intSecs,
            $nfsCCommitTot/$intSecs, $rpcRetransTot/$intSecs, $rpcCredRefTot/$intSecs);
    }

    # Lustre
    if ($subsys=~/l/)
    {
      # MDS goes first since for detail, the OST is variable and if we ever
      # do both we want consistency of order.  Also note that by reporting all 6
      # reints we assure consisency across lustre versions
      if ($reportMdsFlag)
      {
        $mdsReint=$lustreMdsReintCreate+$lustreMdsReintLink+
                  $lustreMdsReintSetattr+$lustreMdsReintRename+$lustreMdsReintUnlink
			if $cfsVersion lt '1.6.5';

        $plot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
            $lustreMdsGetattr/$intSecs,  $lustreMdsGetattrLock/$intSecs,
            $lustreMdsStatfs/$intSecs,   $lustreMdsSync/$intSecs,
            $lustreMdsGetxattr/$intSecs, $lustreMdsSetxattr/$intSecs,
            $lustreMdsConnect/$intSecs,  $lustreMdsDisconnect/$intSecs,
            $lustreMdsReint/$intSecs,
	    $lustreMdsReintCreate/$intSecs,  $lustreMdsReintLink/$intSecs, 
	    $lustreMdsReintSetattr/$intSecs, $lustreMdsReintRename/$intSecs,
	    $lustreMdsReintUnlink/$intSecs);
      }

      if ($reportOstFlag)
      {
	# We always do this...
        $plot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
           $lustreReadOpsTot/$intSecs,  $lustreReadKBytesTot/$intSecs,
           $lustreWriteOpsTot/$intSecs, $lustreWriteKBytesTot/$intSecs);

        if ($lustOpts=~/B/)
        {
          for ($j=0; $j<$numBrwBuckets; $j++)
          {
            $plot.=sprintf("$SEP%$FS", $lustreBufReadTot[$j]/$intSecs);
          }
          for ($j=0; $j<$numBrwBuckets; $j++)
          {
            $plot.=sprintf("$SEP%$FS", $lustreBufWriteTot[$j]/$intSecs);
          }
        }
      }

      # Disk Block Level Stats can apply to both MDS and OST
      if ($lustOpts=~/D/)
      {
        $plot.=sprintf("$SEP%d$SEP%d$SEP%d$SEP%d",
	       $lusDiskReadsTot[$LusMaxIndex]/$intSecs, 
               $lusDiskReadBTot[$LusMaxIndex]*0.5/$intSecs,
	       $lusDiskWritesTot[$LusMaxIndex]/$intSecs, 
               $lusDiskWriteBTot[$LusMaxIndex]*0.5/$intSecs);
        for ($i=0; $i<$LusMaxIndex; $i++)
        { $plot.=sprintf("$SEP%d", $lusDiskReadsTot[$i]/$intSecs); }
        for ($i=0; $i<$LusMaxIndex; $i++)
        { $plot.=sprintf("$SEP%d", $lusDiskWritesTot[$i]/$intSecs); }
      }

      if ($reportCltFlag)
      {
	# There are actually 3 different formats depending on --lustopts
	$plot.=sprintf("$SEP%d$SEP%d$SEP%d$SEP%d",
	    $lustreCltReadTot/$intSecs,      $lustreCltReadKBTot/$intSecs,
	    $lustreCltWriteTot/$intSecs,     $lustreCltWriteKBTot/$intSecs);
        $plot.=sprintf("$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d",
	    $lustreCltOpenTot/$intSecs,      $lustreCltCloseTot/$intSecs, 
	    $lustreCltGetattrTot/$intSecs,   $lustreCltSetattrTot/$intSecs, 
	    $lustreCltSeekTot/$intSecs,      $lustreCltFsyncTot/$intSecs,  
            $lustreCltDirtyHitsTot/$intSecs, $lustreCltDirtyMissTot/$intSecs)
		if $lustOpts=~/M/;
        $plot.=sprintf("$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d",
            $lustreCltRAPendingTot,  $lustreCltRAHitsTot,     $lustreCltRAMissesTot, 
            $lustreCltRANotConTot,   $lustreCltRAMisWinTot,   $lustreCltRAFalGrabTot,
            $lustreCltRALckFailTot,  $lustreCltRAReadDiscTot, $lustreCltRAZeroLenTot, 
            $lustreCltRAZeroWinTot,  $lustreCltRA2EofTot,     $lustreCltRAHitMaxTot,
	    $lustreCltRAWrongTot)
		if $lustOpts=~/R/;

        if ($lustOpts=~/B/) {
          for ($i=0; $i<$numBrwBuckets; $i++) {
            $plot.=sprintf("$SEP%d", $lustreCltRpcReadTot[$i]/$intSecs);
          }
          for ($i=0; $i<$numBrwBuckets; $i++) {
            $plot.=sprintf("$SEP%d", $lustreCltRpcWriteTot[$i]/$intSecs);
          }
        }
      }
    }

    #ELAN
    if ($subsys=~/x/ && $NumXRails)
    {
      $elanErrors=$elanSendFailTot+$elanNeterrAtomicTot+$elanNeterrDmaTot;
      $plot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
		$elanRxTot/$intSecs,   $elanTxTot/$intSecs,
		$elanRxKBTot/$intSecs, $elanTxKBTot/$intSecs,
		$elanErrors/$intSecs);
    }

    # INFINIBAND
    # Now if 'x' specified and neither ELAN or IB, we still want to print all 0s so lets
    # do it here (we could have done it in the ELAN routines is we wanted to).
    if ($subsys=~/x/ && ($NumHCAs || ($NumHCAs==0 && $NumXRails==0)))
    {
      $plot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
		$ibRxTot/$intSecs,   $ibTxTot/$intSecs,
		$ibRxKBTot/$intSecs, $ibTxKBTot/$intSecs,
                $ibErrorsTotTot);
    }

    # TCP
    if ($subsys=~/t/)
    {
      # while tempted to control printing via $tcpFilt, by doing them all, we have a more
      # consistent file that is easier to plot and not much more expensive in size
      $plot.=sprintf("$SEP%$FS ", $ipErrors/$intSecs);
      $plot.=sprintf("$SEP%$FS ", $tcpErrors/$intSecs);
      $plot.=sprintf("$SEP%$FS ", $udpErrors/$intSecs);
      $plot.=sprintf("$SEP%$FS ", $icmpErrors/$intSecs);
      $plot.=sprintf("$SEP%$FS ", $tcpData{TcpExt}->{TCPLoss}/$intSecs);
      $plot.=sprintf("$SEP%$FS ", $tcpData{TcpExt}->{TCPFastRetrans}/$intSecs);
    }

    # SLAB
    if ($subsys=~/y/)
    {
      $plot.=sprintf("$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d",
	$slabObjActTotal,  $slabObjActTotalB,  $slabObjAllTotal,  $slabObjAllTotalB,
	$slabSlabActTotal, $slabSlabActTotalB, $slabSlabAllTotal, $slabSlabAllTotalB,
   	$slabNumAct,       $slabNumTot,6);
    }

    # BUDDYINFO
    if ($subsys=~/b/)
    {
      for (my $i=0; $i<11; $i++)
      {
        $plot.=sprintf("$SEP%d", $buddyInfoTot[$i]);
      }
    }

    # only if summary data
    for (my $i=0; $impSummaryFlag && $i<$impNumMods; $i++)
    {
      &{$impPrintPlot[$i]}(3, \$plot)    if $impOpts[$i]=~/s/;
    }

    writeData(0, $datetime, \$plot, $LOG, $ZLOG, 'log', \$oneline)    if $netOpts!~/E/ || $netErrors;
  }

  ###############################
  #    N O N - C O R E    D A T A
  ###############################

  if ($subsys=~/C/)
  {
    $cpuPlot='';
    for ($i=0; $i<$NumCpus; $i++)
    {
      $cpuPlot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
                $userP[$i], $niceP[$i],  $sysP[$i],  $waitP[$i], $irqP[$i],  
                $softP[$i], $stealP[$i], $idleP[$i], $totlP[$i], $intrptTot[$i]/$intSecs);
    }
    writeData(0, $datetime, \$cpuPlot, CPU, $ZCPU, 'cpu', \$oneline);
  }

  #####################
  #    D S K    F i l e
  #####################

  if ($subsys=~/D/)
  {
    $dskPlot='';
    for (my $i=0; $i<@dskOrder; $i++)
    {
      $dskName=$dskOrder[$i];
      next    if ($dskFiltKeep eq '' && $dskName=~/$dskFiltIgnore/) || ($dskFiltKeep ne '' && $dskName!~/$dskFiltKeep/);

      if (defined($disks{$dskName}))
      {
        my $i=$disks{$dskName};
        $dskRecord=sprintf("%s$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
                $dskName,
                $dskRead[$i]/$intSecs,    $dskReadMrg[$i]/$intSecs,  $dskReadKB[$i]/$intSecs,
                $dskWrite[$i]/$intSecs,   $dskWriteMrg[$i]/$intSecs, $dskWriteKB[$i]/$intSecs,
                $dskRqst[$i], $dskQueLen[$i], $dskWait[$i], $dskSvcTime[$i], $dskUtil[$i]);
      }
      else
      {
        $dskRecord=sprintf("%s$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
		$dskName, 0,0,0,0,0,0,0,0,0,0,0);
      }

      # If exception processing in effect and writing to a file, make sure this entry
      # qualities

      if ($options=~/x/i)
      {
        # All we care about for I/O rates is if one is greater than exception.
        $ios=$dskRead[$i]/$intSecs>=$limIOS || $dskWrite[$i]/$intSecs>=$limIOS;
        $svc=$dskSvcTime[$i]*100;

        # Either both tests are > limits or just one, depending on whether AND or OR
        writeData(0, $datetime, \$dskRecord, DSKX, $ZDSKX, 'dskx', undef)
	        if ($limBool && $ios && $svc>=$limSVC) || (!$limBool && ($ios || $svc>=$limSVC));
      }

      # If not doing x-exception reporting, just build one long string
      $dskPlot.="$SEP$dskRecord"    if $options!~/x/;
    }

    # we only write DSK data when NOT doing x type execption processing
    writeData(0, $datetime, \$dskPlot, DSK, $ZDSK, 'dsk', \$oneline)    if $options!~/x/;
  }

  ###############################
  #    E N V I R O N M E N T A L
  ###############################

  if ($subsys=~/E/ && $interval3Print)
  {
    $envPlot='';
    foreach $key (sort keys %$ipmiData)
    {
      for (my $i=0; $i<scalar(@{$ipmiData->{$key}}); $i++)
      {
        my $name=  $ipmiData->{$key}->[$i]->{name};
        my $inst=  $ipmiData->{$key}->[$i]->{inst};
        my $value= $ipmiData->{$key}->[$i]->{value};
        my $status=$ipmiData->{$key}->[$i]->{status};
        $value=0    if $value eq '';
        $envPlot.="$SEP$value";
      }
    }
    writeData(0, $datetime, \$envPlot, ENV, $ZENV, 'env', \$oneline);
  }

  ##########################################
  #    L U S T R E    D E T A I L    F i l e
  ##########################################

  if ($subsys=~/L/)
  {
    if ($reportOstFlag)
    {
      # Basic I/O always there and grouped together
      $ostPlot='';
      for ($i=0; $i<$NumOst; $i++)
      {
        $ostPlot.=sprintf("$SEP%s$SEP%d$SEP%d$SEP%d$SEP%d",
	    $lustreOsts[$i],
            $lustreReadOps[$i]/$intSecs,  $lustreReadKBytes[$i]/$intSecs,
            $lustreWriteOps[$i]/$intSecs, $lustreWriteKBytes[$i]/$intSecs);
      }

      # These guys are optional and follow ALL the basic stuff     
      for ($i=0; $lustOpts=~/B/ && $i<$NumOst; $i++)
      {
        for ($j=0; $j<$numBrwBuckets; $j++)
        { $ostPlot.=sprintf("$SEP%d", $lustreBufRead[$i][$j]/$intSecs); }
        for ($j=0; $j<$numBrwBuckets; $j++)
        { $ostPlot.=sprintf("$SEP%d", $lustreBufWrite[$i][$j]/$intSecs); }
      } 
      writeData(0, $datetime, \$ostPlot, OST, $ZOST, 'ost', \$oneline);
    }

    if ($lustOpts=~/D/)
    {
      $blkPlot='';
      for ($i=0; $i<$NumLusDisks; $i++)
      {
        $blkPlot.=sprintf("$SEP%s$SEP%d$SEP%d",
		 	  $LusDiskNames[$i], 
	     		  $lusDiskReads[$i][$LusMaxIndex]/$intSecs, 
             		  $lusDiskReadB[$i][$LusMaxIndex]*0.5/$intSecs);
        for ($j=0; $j<$LusMaxIndex; $j++)
        {
	  $temp=(defined($lusDiskReads[$i][$j])) ? $lusDiskReads[$i][$j]/$intSecs : 0;
          $blkPlot.=sprintf("$SEP%d", $temp);
        }
        $blkPlot.=sprintf("$SEP%d$SEP%d",
	     	   	  $lusDiskWrites[$i][$LusMaxIndex]/$intSecs, 
             		  $lusDiskWriteB[$i][$LusMaxIndex]*0.5/$intSecs);
        for ($j=0; $j<$LusMaxIndex; $j++)
        {
	  $temp=(defined($lusDiskWrites[$i][$j])) ? $lusDiskWrites[$i][$j]/$intSecs : 0;
          $blkPlot.=sprintf("$SEP%d", $temp);
        }
      }
      writeData(0, $datetime, \$blkPlot, BLK, $ZBLK, 'blk', \$online);
    }

    if ($reportCltFlag)
    {
      $cltPlot='';
      if ($lustOpts=~/O/)    # either OST details or FS details but not both
      {
        for ($i=0; $i<$NumLustreCltOsts; $i++)
        {
          # when lustre first starts up none of these have values
          $cltPlot.=sprintf("$SEP%s$SEP%s$SEP%d$SEP%d$SEP%d$SEP%d",
              $lustreCltOstFS[$i], $lustreCltOsts[$i],
	      defined($lustreCltLunRead[$i])    ? $lustreCltLunRead[$i]/$intSecs : 0,
	      defined($lustreCltLunReadKB[$i])  ? $lustreCltLunReadKB[$i]/$intSecs : 0,
	      defined($lustreCltLunWrite[$i])   ? $lustreCltLunWrite[$i]/$intSecs : 0, 
	      defined($lustreCltLunWriteKB[$i]) ? $lustreCltLunWriteKB[$i]/$intSecs : 0);
        }
        for ($i=0; $lustOpts=~/B/ && $i<$NumLustreCltOsts; $i++)
        {
          for ($j=0; $j<$numBrwBuckets; $j++)
          {
	    $cltPlot.=sprintf("$SEP%3d", $lustreCltRpcRead[$i][$j]/$intSecs);
          }
          for ($j=0; $j<$numBrwBuckets; $j++)
          {
	    $cltPlot.=sprintf("$SEP%3d", $lustreCltRpcWrite[$i][$j]/$intSecs);
          }
        }
      }
      else    # must be FS
      {
        for ($i=0; $i<$NumLustreFS; $i++)
        {
          $cltPlot.=sprintf("$SEP%s$SEP%d$SEP%d$SEP%d$SEP%d",
	    $lustreCltFS[$i],
	    $lustreCltRead[$i]/$intSecs,      $lustreCltReadKB[$i]/$intSecs,   
	    $lustreCltWrite[$i]/$intSecs,     $lustreCltWriteKB[$i]/$intSecs);
	}
        for ($i=0; $lustOpts=~/M/ && $i<$NumLustreFS; $i++)
        {
          $cltPlot.=sprintf("$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d",
	    $lustreCltOpen[$i]/$intSecs,      $lustreCltClose[$i]/$intSecs, 
	    $lustreCltGetattr[$i]/$intSecs,   $lustreCltSetattr[$i]/$intSecs, 
	    $lustreCltSeek[$i]/$intSecs,      $lustreCltFsync[$i]/$intSecs,  
            $lustreCltDirtyHits[$i]/$intSecs, $lustreCltDirtyMiss[$i]/$intSecs);
	}
        for ($i=0; $lustOpts=~/R/ && $i<$NumLustreFS; $i++)
        {
          $cltPlot.=sprintf("$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d",
            $lustreCltRAPendingTot,  $lustreCltRAHitsTot,     $lustreCltRAMissesTot, 
            $lustreCltRANotConTot,   $lustreCltRAMisWinTot,   $lustreCltRAFalGrabTot,
            $lustreCltRALckFailTot,  $lustreCltRAReadDiscTot, $lustreCltRAZeroLenTot, 
            $lustreCltRAZeroWinTot,  $lustreCltRA2EofTot,     $lustreCltRAHitMaxTot,
	    $lustreCltRAWrongTot);
        }
      }
      writeData(0, $datetime, \$cltPlot, CLT, $ZCLT, 'clt', \$oneline);
    }
  }

  #########################
  #    N  U M A    F i l e
  #########################

  if ($subsys=~/M/)
  {
    my $numaPlot='';
    for (my $i=0; $i<$CpuNodes; $i++)
    {
        # don't see how total can ever be 0, but let's be careful anyways
        my $misses=$numaStat[$i]->{for}+$numaStat[$i]->{miss};
        my $hitrate=($misses) ? $numaStat[$i]->{hits}/($numaStat[$i]->{hits}+$misses)*100/$intSecs : 100;

	$numaPlot.=sprintf("$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%4.1f",
	                $numaMem[$i]->{used}, $numaMem[$i]->{free}, $numaMem[$i]->{slab},
        	        $numaMem[$i]->{map},  $numaMem[$i]->{anon},
                	$numaMem[$i]->{inact}, $hitrate);
    }
    writeData(0, $datetime, \$numaPlot, NUMA, $ZNUMA, 'numa', \$oneline);
  }

  #####################
  #    N F S    F i l e
  #####################

  if ($subsys=~/F/)
  {
    $nfsPlot='';
    if ($nfs2CFlag)
    {
      $nfsPlot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
            $nfs2CRead/$intSecs,    $nfs2CWrite/$intSecs,   $nfs2CLookup/$intSecs,   $nfs2CGetattr/$intSecs, 
            $nfs2CSetattr/$intSecs, $nfs2CReaddir/$intSecs, $nfs2CCreate/$intSecs,   $nfs2CRemove/$intSecs,);
      $nfsPlot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
            $nfs2CRename/$intSecs,  $nfs2CLink/$intSecs,    $nfs2CReadlink/$intSecs, $nfs2CNull/$intSecs,
            $nfs2CSymlink/$intSecs, $nfs2CMkdir/$intSecs,   $nfs2CRmdir/$intSecs,    $nfs2CFsstat/$intSecs);
    }

    if ($nfs2SFlag)
    {
      $nfsPlot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
            $nfs2SRead/$intSecs,    $nfs2SWrite/$intSecs,   $nfs2SLookup/$intSecs,   $nfs2SGetattr/$intSecs, 
            $nfs2SSetattr/$intSecs, $nfs2SReaddir/$intSecs, $nfs2SCreate/$intSecs,   $nfs2SRemove/$intSecs);
      $nfsPlot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
            $nfs2SRename/$intSecs,  $nfs2SLink/$intSecs,    $nfs2SReadlink/$intSecs, $nfs2SNull/$intSecs,
            $nfs2SSymlink/$intSecs, $nfs2SMkdir/$intSecs,   $nfs2SRmdir/$intSecs,    $nfs2SFsstat/$intSecs);
    }

    if ($nfs3CFlag)
    {
      $nfsPlot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
            $nfs3CRead/$intSecs,     $nfs3CWrite/$intSecs,   $nfs3CCommit/$intSecs,  $nfs3CLookup/$intSecs,   
            $nfs3CAccess/$intSecs,   $nfs3CGetattr/$intSecs, $nfs3CSetattr/$intSecs, $nfs3CReaddir/$intSecs, 
	    $nfs3CCreate/$intSecs,   $nfs3CRemove/$intSecs,  $nfs3CRename/$intSecs,  $nfs3CLink/$intSecs);

      $nfsPlot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
            $nfs3CReadlink/$intSecs, $nfs3CNull/$intSecs,    $nfs3CSymlink/$intSecs, $nfs3CMkdir/$intSecs,
            $nfs3CRmdir/$intSecs,    $nfs3CFsstat/$intSecs,  $nfs3CFsinfo/$intSecs,  $nfs3CPathconf/$intSecs,
            $nfs3CMknod/$intSecs,    $nfs3CReaddirplus/$intSecs);
    }

    if ($nfs3SFlag)
    {
      $nfsPlot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
            $nfs3SRead/$intSecs,     $nfs3SWrite/$intSecs,   $nfs3SCommit/$intSecs,  $nfs3SLookup/$intSecs,   
            $nfs3SAccess/$intSecs,   $nfs3SGetattr/$intSecs, $nfs3SSetattr/$intSecs, $nfs3SReaddir/$intSecs, 
	    $nfs3SCreate/$intSecs,   $nfs3SRemove/$intSecs,  $nfs3SRename/$intSecs,  $nfs3SLink/$intSecs);

      $nfsPlot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
            $nfs3SReadlink/$intSecs, $nfs3SNull/$intSecs,    $nfs3SSymlink/$intSecs, $nfs3SMkdir/$intSecs,
            $nfs3SRmdir/$intSecs,    $nfs3SFsstat/$intSecs,  $nfs3SFsinfo/$intSecs,  $nfs3SPathconf/$intSecs,
            $nfs3SMknod/$intSecs,    $nfs3SReaddirplus/$intSecs);
    }

    if ($nfs4CFlag)
    {
      $nfsPlot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
            $nfs4CRead/$intSecs,     $nfs4CWrite/$intSecs,   $nfs4CCommit/$intSecs,  $nfs4CLookup/$intSecs,   
            $nfs4CAccess/$intSecs,   $nfs4CGetattr/$intSecs, $nfs4CSetattr/$intSecs, $nfs4CReaddir/$intSecs, 
	    $nfs4CCreate/$intSecs,   $nfs4CRemove/$intSecs,  $nfs4CRename/$intSecs,  $nfs4CLink/$intSecs);

      $nfsPlot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
            $nfs4CReadlink/$intSecs, $nfs4CNull/$intSecs,    $nfs4CSymlink/$intSecs, $nfs4CFsinfo/$intSecs,
            $nfs4CPathconf/$intSecs);
    }

    if ($nfs4SFlag)
    {
      $nfsPlot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
            $nfs4SRead/$intSecs,     $nfs4SWrite/$intSecs,   $nfs4SCommit/$intSecs,  $nfs4SLookup/$intSecs,   
            $nfs4SAccess/$intSecs,   $nfs4SGetattr/$intSecs, $nfs4SSetattr/$intSecs, $nfs4SReaddir/$intSecs, 
	    $nfs4SCreate/$intSecs,   $nfs4SRemove/$intSecs,  $nfs4SRename/$intSecs,  $nfs4SLink/$intSecs,
            $nfs4SReadlink/$intSecs);
    }
    writeData(0, $datetime, \$nfsPlot, NFS, $ZNFS, 'nfs', \$oneline);
  }

  #####################
  #    N E T    F i l e
  #####################

  if ($subsys=~/N/)
  {
    $netPlot='';
    for (my $i=0; $i<@netOrder; $i++)
    {
      # remember the order includes the speed
      $netName=$netOrder[$i];
      $netName=~s/:.*//;
      next    if ($netFiltKeep eq '' && $netName=~/$netFiltIgnore/) || ($netFiltKeep ne '' && $netName!~/$netFiltKeep/);

      # remember 'err' is a single error counter and 'errs' is the total of those counters
      # we also have to be sure to preseve network order
      if (defined($networks{$netName}))
      {
        my $i=$networks{$netName};
        $netPlot.=sprintf("$SEP%s$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
                  $netName,
                  $netRxPkt[$i]/$intSecs, $netTxPkt[$i]/$intSecs,
                  $netRxKB[$i]/$intSecs,  $netTxKB[$i]/$intSecs,
                  $netRxErr[$i]/$intSecs, $netRxDrp[$i]/$intSecs,
                  $netRxFifo[$i]/$intSecs,$netRxFra[$i]/$intSecs,
                  $netRxCmp[$i]/$intSecs, $netRxMlt[$i]/$intSecs,
                  $netTxErr[$i]/$intSecs, $netTxDrp[$i]/$intSecs,
                  $netTxFifo[$i]/$intSecs,$netTxColl[$i]/$intSecs,
                  $netTxCar[$i]/$intSecs, $netTxCmp[$i]/$intSecs,
                  $netRxErrs[$i]/$intSecs,$netTxErrs[$i]/$intSecs);
        $netErrors+=$netRxErrs[$i]+$netTxErrs[$i];
      }
      else
      {
        $netPlot.=sprintf("$SEP%s$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS", $netName, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
      }
    }

    # since we can't have holes in a line, with --netopts E we print ALL interfaces in the offending interval
    writeData(0, $datetime, \$netPlot, NET, $ZNET, 'net', \$oneline)    if $netOpts!~/E/ || $netErrors;
  }

  ############################
  #    I n t e r c o n n e c t
  ############################

  # Quadrics
  if ($subsys=~/X/ && $NumXRails)
  {
    $elanPlot='';
    for ($i=0; $i<$NumXRails; $i++)
    {
      $elanPlot.=sprintf("$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
	$elanRx[$i], $elanTx[$i], $elanRxKB[$i], $elanTxKB[$i],
	$elanGet[$i], $elanPut[$i], $elanGetKB[$i], $elanPutKB[$i], 
	$elanComp[$i], $elanCompKB[$i],
	$elanSendFail[$i], $elanNeterrAtomic[$i], $elanNeterrDma[$i]);
    }
    writeData(0, $datetime, \$elanPlot, ELN, $ZELN, 'eln', \$oneline);
  }

  # INFINIBAND
  if ($subsys=~/X/ && $NumHCAs)
  {
    $ibPlot='';
    for ($i=0; $i<$NumHCAs; $i++)
    {
      $ibPlot.=sprintf("$SEP%d$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS$SEP%$FS",
	  $i,
	  $ibRx[$i]/$intSecs,   $ibTx[$i]/$intSecs,
	  $ibRxKB[$i]/$intSecs, $ibTxKB[$i]/$intSecs,
          $ibErrorsTot[$i]);
    }
    writeData(0, $datetime, \$ibPlot, IB, $ZIB, 'ib', \$oneline);
  }

  #######################
  #    T C P    F i l e
  #######################

  if ($subsys=~/T/)
  {
    # This is going to be big!!! 
    $tcpPlot='';
    for my $type ('Ip', 'Tcp', 'Udp', 'Icmp', 'IpExt', 'TcpExt')
    {
      next    if $type eq 'Ip'     && $tcpFilt!~/i/;
      next    if $type eq 'Tcp'    && $tcpFilt!~/t/;
      next    if $type eq 'Udp'    && $tcpFilt!~/u/;
      next    if $type eq 'Icmp'   && $tcpFilt!~/c/;
      next    if $type eq 'IpExt'  && $tcpFilt!~/I/;
      next    if $type eq 'TcpExt' && $tcpFilt!~/T/;

      # unfortunately the data is indexed by header name so we need an extra hop to get to it
      foreach my $header (@{$tcpData{$type}->{hdr}})
      { $tcpPlot.=sprintf("$SEP%d", $tcpData{$type}->{$header}/$intSecs); }
    }
    writeData(0, $datetime, \$tcpPlot, TCP, $ZTCP, 'tcp', \$oneline);
  }

  #########################
  #    B U D D Y I N F O
  #########################

  if ($subsys=~/B/)
  {
    $budPlot='';
    for (my $i=0; $i<$NumBud; $i++)
    {
      $budPlot.="$SEP$buddyNode[$i]$SEP$buddyZone[$i]";
      for (my $j=0; $j<11; $j++)
      {
        $budPlot.=sprintf("$SEP%d", $buddyInfo[$i][$j]);
      }
    }
    writeData(0, $datetime, \$budPlot, BUD, $ZBUD, 'bud', \$oneline);
  }

  #####################
  #    I M P O R T S
  #####################

  # only if detail data
  for (my $i=0; $impDetailFlag && $i<$impNumMods; $i++)
  {
    if ($impOpts[$i]=~/d/)
    {
      $impPlot='';
      &{$impPrintPlot[$i]}(4, \$impPlot); 
      if ($impPlot ne '')
      {
        $impDetFlag[$i]++;
        writeData(0, $datetime, \$impPlot, , $impText[$i], $impGz[$i], $impKey[$i], \$oneline);
      }
    }
  }

  #    F i n a l    w r i t e

  # we can't have holes in line so if --netopts E and no errors, do NOT print line to terminal or file.
  return    if $netOpts=~/E/ && !$netErrors;

  # This write is necessary to write complete record to terminal or socket.
  # Note if there is a socket error we're returning to the caller anyway;
  writeData(1, $datetime, undef, $LOG, undef, undef, \$oneline)
	if !$logToFileFlag || ($sockFlag && $export eq '');
}

# First and foremost, this is ONLY used to plot data.  It will send it to the terminal,
# a socket, a data file or a combination of socket and data file.
# Secondly, we only call after processing a complete subsystem so in the case of
# core ones there's a single call but for detail subsystems one per.
# Therefore, when writing to a file, we write the whole string we're passed, but when 
# writing to a terminal or socket, we build up one long string and write it on the
# last call.  Since we can write to any combinations we need to handle them all.
sub writeData
{
  my $eolFlag= shift;
  my $datetime=shift;
  my $string=  shift;
  my $file=    shift;
  my $zfile=   shift;
  my $errtxt=  shift;
  my $strall=  shift;

  # The very last call is special so handle it elsewhere
  if (!$eolFlag)
  {
    # If writing to the terminal or a socket, just concatenate
    # the strings together until the last call.
    if (!$logToFileFlag || $sockFlag)
    {
      $$strall.=$$string;
    }

    # However, we might also be writing to a file as well as a socket
    # and so need second test like this.
    if ($logToFileFlag)
    {
      # Since we get called with !$eolFlag with partial lines, we always
      # have a separator at the end of the line, so remove it before write.
      my $localCopy=$$string;
      $localCopy=~s/$SEP$//;

      # Each record gets a timestamp and a newline.  In the case of a file
      # header, this will be null and the data will be the header!
      $zfile->gzwrite("$datetime$localCopy\n") or 
	     writeError($errtxt, $zfile)       if  $zFlag;
      print {$file} "$datetime$localCopy\n"    if !$zFlag;
    }
    return(1);
  }

  # Final Write!!!
  # Doing these two writes this way will allow writing to the
  # terminal AND a socket if we ever want to.
  # NOTE - in virtually all cases there will be data to write.  However when collecting
  # data at different intervals, say with a custom import, there may not be data every
  # time and we don't want to write empty records.
  if ($$strall ne '')
  {
    if (!$sockFlag)
    {
      # final write to terminal
      print "$datetime$$strall\n";
    }

    # write to socket but ONLY if we're not shutting down
    if ($sockFlag && scalar(@sockets) && !$doneFlag)
    {
      # If a data line, preface with timestamp
      $$strall="$datetime$$strall"    if $strall!~/^#/;

      # If we're not running a server, make sure each line begins 
      # with hostname and write to socket
      $$strall=~s/^(.*)$/$Host $1/mg    if !$serverFlag;

      # we need to write to each listening socket, though there are probably rarely
      # more than 1
      $$strall.="\n";
      foreach my $socket (@sockets)
      {
        my $length=length($$strall);
        for (my $offset=0; $offset<$length;)
        {
          # Note - if there is a socket write error, writeData returns 0, but we're
          # exiting this routine anyway and since '$doneFlag' is hopefully set because
          # of a broken socket, the calling routines should exit cleanly.
          # BUT only log error if in server mode, since normal as client
          my $bytes=syswrite($socket, $$strall, $length, $offset);
          if (!defined($bytes))
          {
            logmsg('E', "Error '$!' writing to socket")    if $serverFlag;
            return(0);
          }
          $offset+=$bytes;
          $length-=$bytes;
        }
      }
    }
  }
  return(1);
}

######################################
#    T e r m i n a l     F o r m a t s
######################################

sub printTerm
{
  local $seconds=shift;
  local $usecs=  shift;
  my ($ss, $mm, $hh, $mday, $mon, $year, $line, $i, $j);

  # if someone wants to look at procs with --home and NOT --top, let them!
  print "$clscr"   if !$numTop && $homeFlag;

  # There are a couple of things we want to do in interactive --top mode regardless
  # of --brief or --verbose
  if ($numTop && $playback eq '')
  {
    print $clscr    if !$printTermFirst;
    if ($printTermFirst)   # --brief OR single subsys --verbose
    {
      # move the cursor to the correct location for ALL cases
      if ($subsys ne 'Z')
      {
        my $lineNum=$totalCounter+2;
        $lineNum=$scrollEnd    if $lineNum>$scrollEnd;
        $lineNum=0             if !$sameColsFlag || $detailFlag;
        printf "%c[%d;H", 27, $lineNum;
      }

      # We only want to clear the screen once and print the header once
      # the first time through and then just overpaint starting with data,
      # unless of course we have details in which case we always print it.
      $clscr=$home;
      $headerRepeat=0    if !$detailFlag;
    }
    $printTermFirst=1;
  }

  # if we're including date and/or time, do once for whole interval
  $line=$datetime='';
  if ($miniDateFlag || $miniTimeFlag)
  {
    ($ss, $mm, $hh, $mday, $mon, $year)=localtime($seconds);
    $datetime=sprintf("%02d:%02d:%02d", $hh, $mm, $ss);
    $datetime=sprintf("%02d/%02d %s", $mon+1, $mday, $datetime)                   if $options=~/d/;
    $datetime=sprintf("%04d%02d%02d %s", $year+1900, $mon+1, $mday, $datetime)    if $options=~/D/;
    $datetime.=".$usecs"                                                          if ($options=~/m/);
    $datetime.=" ";
  }

  ################
  #    B r i e f  
  ################

  if ($briefFlag)
  {
    # This always goes to terminal or socket and is never compressed so we don't need
    # all the options of writeData() [yet].
    printBrief();

    # --top mode requires process data too but only if interactive OR we're in playback
    # mode and processing a file with process data in it
    if ($numTop && ($playback eq '' || (($playback{$prefix}->{flags} & 1)==0) || $rawPFlag))
    {
      printTermProc()    if $topProcFlag;
      printTermSlab()    if $topSlabFlag;
      $headerRepeat=-1 && $playback eq '';    # only print header once interactively
    }
    return;
  }

  ############################
  #    V e r b o s e
  ############################

  # These interval counters will always match the interval we're about to print
  $interval1Counter++    if $i1DataFlag;
  $interval2Counter++    if $i2DataFlag && $interval2Print;
  $interval3Counter++    if $i3DataFlag && $interval3Print;

  # we usually want record break separators (with timestamps) except in a few cases which 
  $separatorHeaderPrinted=0;

  if ($subsys=~/c/)
  {
    $i=$NumCpus;
    if (printHeader())
    {
      printText("\n")    if !$homeFlag;
      printText("# CPU$Hyper SUMMARY (INTR, CTXSW & PROC $rate)$cpuDisabledMsg\n");
      printText("#$miniDateTime User  Nice   Sys  Wait   IRQ  Soft Steal  Idle  CPUs  Intr  Ctxsw  Proc  RunQ   Run   Avg1  Avg5 Avg15 RunT BlkT\n");
      exit(0)    if $showColFlag;
    }
    $line=sprintf("$datetime  %4d  %4d  %4d  %4d  %4d  %4d  %4d  %4d  %4d  %4s   %4s  %4d  %4d  %4d  %5.2f %5.2f %5.2f %4d %4d\n",
	    $userP[$i], $niceP[$i], $sysP[$i],   $waitP[$i],
            $irqP[$i],  $softP[$i], $stealP[$i], $idleP[$i], 
            $cpusEnabled,
	    cvt($intrpt/$intSecs), cvt($ctxt/$intSecs), $proc/$intSecs,
	    $loadQue, $loadRun, $loadAvg1, $loadAvg5, $loadAvg15, $procsRun, $procsBlock);
    printText($line);
  }

  if ($subsys=~/C/)
  {
    if (printHeader())
    {
      printText("\n")    if !$homeFlag;
      printText("# SINGLE CPU$Hyper STATISTICS$cpuDisabledMsg\n");
      my $intrptText=($subsys=~/j/i) ? ' INTRPT' : '';
      printText("#$miniDateTime   Cpu  User Nice  Sys Wait IRQ  Soft Steal Idle$intrptText\n");
      exit(0)    if $showColFlag;
    }

    # if not recorded and user chose -s C don't print line items
    if (defined($userP[0]))
    {
      for ($i=0; $i<$NumCpus; $i++)
      {
        # skip idle CPUs if --cpuopts z specified.  I'm rather check for idle==100% but some kernels don't
	# always increment counts and there are actually idle cpus with values of 0 here.
        next    if $cpuOpts=~/z/ && $userP[$i]+$niceP[$i]+$sysP[$i]+$waitP[$i]+$irqP[$i]+$softP[$i]+$stealP[$i]==0;
        $line=sprintf("$datetime   %4d   %3d  %3d  %3d  %3d  %3d  %3d   %3d  %3d",
           $i, 
           $userP[$i], $niceP[$i], $sysP[$i],   $waitP[$i], 
	   $irqP[$i],  $softP[$i], $stealP[$i], $idleP[$i]);
        $line.=sprintf(" %6d", $intrptTot[$i]/$intSecs)    if $subsys=~/j/i;
	printText("$line\n");
      }
    } 
  }

  # Only meaningful when Interrupts not combined with -sC
  if ($subsys=~/j/ && !$CFlag)
  {
    if (printHeader())
    {
      printText("\n")    if !$homeFlag;
      printText("# INTERRUPT SUMMARY$cpuDisabledMsg\n");
      my $oneline="#$miniDateTime ";
      for (my $i=0; $i<$NumCpus; $i++)
      {
        my $cpuname=($cpuEnabled[$i]) ? "Cpu$i" : "CpuX";
        $oneline.=sprintf(" %6s", $cpuname);
      }
      printText("$oneline\n");
      exit(0)    if $showColFlag;
    }

    my $oneline="$datetime  ";
    for (my $i=0; $i<$NumCpus; $i++)
    {
      $oneline.=sprintf(" %6d", $intrptTot[$i]);
    }
    printText("$oneline\n");
    exit(0)    if $showColFlag;
  }

  if ($subsys=~/J/)
  {
    if (printHeader())
    {
      printText("\n")    if !$homeFlag;
      printText("# INTERRUPT DETAILS$cpuDisabledMsg\n");
      my $oneline="#$miniDateTime Int ";

      for (my $i=0; $i<$NumCpus; $i++)
      {
        my $cpuname=($cpuEnabled[$i] || $subsys!~/c/i) ? "Cpu$i" : "CpuX";
        $oneline.=sprintf(" %6s", $cpuname);
      }
      $oneline.=sprintf("   %-15s %s\n", 'Type', 'Device(s)');
      printText($oneline);
      exit(0)    if $showColFlag;
    }

    foreach my $key (sort keys %intrptType)
    {
      my $linetot=0;
      my $oneline="$datetime  $key  ";
      for (my $i=0; $i<$NumCpus; $i++)
      {
        next    if $key eq 'ERR' || $key eq 'MIS';

        my $ints=($key=~/^\d/) ? $intrpt[$key]->[$i]/$intSecs : $intrpt{$key}->[$i]/$intSecs;
        $oneline.=sprintf("%6d ", $ints);
        $linetot+=$ints;
      }
      $oneline.=sprintf("  %s", $intName{$key})    if $key!~/ERR|MIS/;
      printText("$oneline\n")    if $linetot;
    }
  }

  if ($subsys=~/d/)
  {
    if (printHeader())
    {
      printText("\n")    if !$homeFlag;
      printText("# DISK SUMMARY ($rate)\n");
      printText("#${miniDateTime}KBRead RMerged  Reads SizeKB  KBWrite WMerged Writes SizeKB\n");
      exit(0)    if $showColFlag;
    }

    $line=sprintf("$datetime %6d  %6d %6d %6d   %6d  %6d %6d %6d\n",
                $dskReadKBTot/$intSecs,  $dskReadMrgTot/$intSecs,  $dskReadTot/$intSecs,
	        $dskReadTot ? $dskReadKBTot/$dskReadTot : 0,
                $dskWriteKBTot/$intSecs, $dskWriteMrgTot/$intSecs, $dskWriteTot/$intSecs,
		$dskWriteTot ? $dskWriteKBTot/$dskWriteTot : 0);
    printText($line);
  }

  if ($subsys=~/D/)
  {
    # deal with --dskopts f format here
    if (!defined($dskhdr1Format))
    {
      if ($dskOpts!~/f/)
      {
        $dskhdr1Format="<---------reads---------><---------writes---------><--------averages--------> Pct\n";
	$dskhdr2Format="     KBytes Merged  IOs Size  KBytes Merged  IOs Size  RWSize  QLen  Wait SvcTim Util\n";
        $dskdetFormat="%s%-11s %6d %6d %4s %4s  %6d %6d %4s %4s   %5d %5d  %4d   %4d  %3d\n";
      }
      else
      {
        $dskhdr1Format="<---------reads----------><---------writes---------><---------averages----------> Pct\n";
        $dskhdr2Format="      KBytes Merged  IOs Size   KBytes Merged  IOs Size  RWSize   QLen   Wait SvcTim Util\n";
	$dskdetFormat="%s%-11s %7.1f %6.0f %4s %4s  %7.1f %6.0f %4s %4s  %6.1f %6.1f %6.1f %6.1f  %3.0f\n";
      }
    }

    if (printHeader())
    {
      printText("\n")    if !$homeFlag;
      printText("# DISK STATISTICS ($rate)\n");
      printText("#$miniFiller          $dskhdr1Format");
      printText("#${miniDateTime}Name  $dskhdr2Format");
      exit(0)    if $showColFlag;
    }

    for (my $i=0; $i<@dskOrder; $i++)
    {
      # preserve display order but skip any disks not seen this interval
      $dskName=$dskOrder[$i];
      next    if !defined($dskSeen[$i]);
      next    if ($dskFiltKeep eq '' && $dskName=~/$dskFiltIgnore/) || ($dskFiltKeep ne '' && $dskName!~/$dskFiltKeep/);

      # Filter out lines of all zeros when requested
      next    if $dskOpts=~/z/ && ($dskReadKB[$i]+$dskReadMrg[$i]+$dskRead[$i]+
				   $dskWriteKB[$i]+$dskWriteMrg[$i]+$dskWrite[$i]+
				   $dskRqst[$i]+$dskQueLen[$i]+$dskWait[$i]+$dskSvcTime[$i]+$dskUtil[$i]==0);

      # If exception processing in effect, make sure this entry qualities
      next    if $options=~/x/ && $dskRead[$i]/$intSecs<$limIOS && $dskWrite[$i]/$intSecs<$limIOS;

      $line=sprintf($dskdetFormat,
 	        $datetime, $dskName,
		$dskReadKB[$i]/$intSecs,  $dskReadMrg[$i]/$intSecs,  cvt($dskRead[$i]/$intSecs),
	        $dskRead[$i] ? cvt($dskReadKB[$i]/$dskRead[$i],4,0,1) : 0,
		$dskWriteKB[$i]/$intSecs, $dskWriteMrg[$i]/$intSecs, cvt($dskWrite[$i]/$intSecs),
                $dskWrite[$i] ? cvt($dskWriteKB[$i]/$dskWrite[$i],4,0,1) : 0,
		$dskRqst[$i], $dskQueLen[$i], $dskWait[$i], $dskSvcTime[$i], $dskUtil[$i]);
      printText($line);
    }
  }

  if ($subsys=~/f/)
  {
    if (printHeader())
    {
      my $temp=($nfsFilt ne '') ? "Filters: $nfsFilt" : '';
      printText("\n")    if !$homeFlag;
      printText("# NFS SUMMARY ($rate) $temp\n");


      $temp="#$miniFiller";
      $temp.="<---------------------------server--------------------------->"     if $nfsSFlag;
      $temp.="<----------------client---------------->"                           if $nfsCFlag;
      printText("$temp\n");

      $temp="#$miniDateTime";
      $temp.=" Reads Writes Meta Comm  UDP   TCP  TCPConn  BadAuth  BadClnt "     if $nfsSFlag;
      $temp.=" Reads Writes Meta Comm Retrans  Authref"                           if $nfsCFlag;
      printText("$temp\n");
      exit(0)    if $showColFlag;
    }

    $line=$datetime;
    $line.=sprintf(" %6s %6s %4s %4s %4s  %4s     %4s     %4s     %4s",
	 	cvt($nfsSReadsTot/$intSecs,6), cvt($nfsSWritesTot/$intSecs,6), 
                cvt($nfsSMetaTot/$intSecs),    cvt($nfsSCommitTot/$intSecs),
                cvt($nfsUdpTot/$intSecs),      cvt($nfsTcpTot/$intSecs),
                cvt($nfsTcpConnTot/$intSecs),  cvt($rpcBadAuthTot/$intSecs),
                cvt($rpcBadClntTot/$intSecs))
			if $nfsSFlag;

    $line.=sprintf(" %6s %6s %4s %4s    %4s     %4s",
                cvt($nfsCReadsTot/$intSecs,6), cvt($nfsCWritesTot/$intSecs,6),
                cvt($nfsCMetaTot/$intSecs),    cvt($nfsCCommitTot/$intSecs),
		cvt($rpcRetransTot/$intSecs),  cvt($rpcCredRefTot/$intSecs))
			if $nfsCFlag;
    $line.="\n";
    printText($line);
  }  

  if ($subsys=~/F/)
  {
    if (printHeader())
    {
      printText("\n")    if !$homeFlag;
      printText("# NFS SERVER/CLIENT DETAILS ($rate)\n");

      # NOTE - we're not including V2 root/wrcache
      printText("#${miniDateTime}Type Read Writ Comm Look Accs Gttr Sttr Rdir Cre8 Rmov Rnam Link Rlnk Null Syml Mkdr Rmdr Fsta Finf Path Mknd Rdr+\n");
      exit(0)    if $showColFlag;
    }

    # As an optimization, only show data where the filesystem is actually active but if --nfsopts z, only show
    # entries with non-zero data.  Currently only valid value for $nfsOpts is 'z'
    if ($nfs2CFlag && $nfs2CSeen && ($nfsOpts!~/z/ || $nfs2CRead+$nfs2CWrite+$nfs2CMeta))
    {
      $line =sprintf("$datetime Clt2 %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s\n",
		cvt($nfs2CRead/$intSecs),    cvt($nfs2CWrite/$intSecs),   '',
		cvt($nfs2CLookup/$intSecs),  '',                          cvt($nfs2CGetattr/$intSecs), 
		cvt($nfs2CSetattr/$intSecs), cvt($nfs2CReaddir/$intSecs), cvt($nfs2CCreate/$intSecs), 
		cvt($nfs2CRemove/$intSecs),  cvt($nfs2CRename/$intSecs),  cvt($nfs2CLink/$intSecs),        
		cvt($nfs2CReadlink/$intSecs),cvt($nfs2CNull/$intSecs),    cvt($nfs2CSymlink/$intSecs), 
		cvt($nfs2CMkdir/$intSecs),   cvt($nfs2CRmdir/$intSecs),   cvt($nfs2CFsstat/$intSecs));
      printText($line);
    }

    if ($nfs2SFlag && $nfs2SSeen && ($nfsOpts!~/z/ || $nfs2SRead+$nfs2SWrite+$nfs2SMeta))
    {
      $line =sprintf("$datetime Svr2 %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s\n",
		cvt($nfs2SRead/$intSecs),    cvt($nfs2SWrite/$intSecs),   '',
		cvt($nfs2SLookup/$intSecs),  '',                          cvt($nfs2SGetattr/$intSecs), 
		cvt($nfs2SSetattr/$intSecs), cvt($nfs2SReaddir/$intSecs), cvt($nfs2SCreate/$intSecs), 
		cvt($nfs2SRemove/$intSecs),  cvt($nfs2SRename/$intSecs),  cvt($nfs2SLink/$intSecs),        
		cvt($nfs2SReadlink/$intSecs),cvt($nfs2SNull/$intSecs),    cvt($nfs2SSymlink/$intSecs), 
		cvt($nfs2SMkdir/$intSecs),   cvt($nfs2SRmdir/$intSecs),   cvt($nfs2SFsstat/$intSecs));
      printText($line);
    }

    if ($nfs3CFlag && $nfs3CSeen && ($nfsOpts!~/z/ || $nfs3CRead+$nfs3CWrite+$nfs3CMeta))
    {
      $line =sprintf("$datetime Clt3 %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s\n",
		cvt($nfs3CRead/$intSecs),    cvt($nfs3CWrite/$intSecs),   cvt($nfs3CCommit/$intSecs),
		cvt($nfs3CLookup/$intSecs),  cvt($nfs3CAccess/$intSecs),  cvt($nfs3CGetattr/$intSecs), 
		cvt($nfs3CSetattr/$intSecs), cvt($nfs3CReaddir/$intSecs), cvt($nfs3CCreate/$intSecs), 
		cvt($nfs3CRemove/$intSecs),  cvt($nfs3CRename/$intSecs),  cvt($nfs3CLink/$intSecs),        
		cvt($nfs3CReadlink/$intSecs),cvt($nfs3CNull/$intSecs),    cvt($nfs3CSymlink/$intSecs), 
		cvt($nfs3CMkdir/$intSecs),   cvt($nfs3CRmdir/$intSecs),   cvt($nfs3CFsstat/$intSecs), 
		cvt($nfs3CFsinfo/$intSecs),  cvt($nfs3CPathconf/$intSecs),cvt($nfs3CMknod/$intSecs),  
		cvt($nfs3CReaddirplus/$intSecs));
      printText($line);
    }

    if ($nfs3SFlag && $nfs3SSeen && ($nfsOpts!~/z/ || $nfs3SRead+$nfs3SWrite+$nfs3SMeta))
    {
      $line =sprintf("$datetime Svr3 %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s\n",
		cvt($nfs3SRead/$intSecs),    cvt($nfs3SWrite/$intSecs),   cvt($nfs3SCommit/$intSecs),
		cvt($nfs3SLookup/$intSecs),  cvt($nfs3SAccess/$intSecs),  cvt($nfs3SGetattr/$intSecs), 
		cvt($nfs3SSetattr/$intSecs), cvt($nfs3SReaddir/$intSecs), cvt($nfs3SCreate/$intSecs), 
		cvt($nfs3SRemove/$intSecs),  cvt($nfs3SRename/$intSecs),  cvt($nfs3SLink/$intSecs),        
		cvt($nfs3SReadlink/$intSecs),cvt($nfs3SNull/$intSecs),    cvt($nfs3SSymlink/$intSecs), 
		cvt($nfs3SMkdir/$intSecs),   cvt($nfs3SRmdir/$intSecs),   cvt($nfs3SFsstat/$intSecs), 
		cvt($nfs3SFsinfo/$intSecs),  cvt($nfs3SPathconf/$intSecs),cvt($nfs3SMknod/$intSecs),  
		cvt($nfs3SReaddirplus/$intSecs));
      printText($line);
    }

    # Not Used: Mkdir Mknod Readdirplus Fsstat Rmdir
    if ($nfs4CFlag && $nfs4CSeen && ($nfsOpts!~/z/ || $nfs4CRead+$nfs4CWrite+$nfs4CMeta))
    {
      $line =sprintf("$datetime Clt4 %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s\n",
		cvt($nfs4CRead/$intSecs),    cvt($nfs4CWrite/$intSecs),   cvt($nfs4CCommit/$intSecs),
		cvt($nfs4CLookup/$intSecs),  cvt($nfs4CAccess/$intSecs),  cvt($nfs4CGetattr/$intSecs), 
		cvt($nfs4CSetattr/$intSecs), cvt($nfs4CReaddir/$intSecs), cvt($nfs4CCreate/$intSecs), 
		cvt($nfs4CRemove/$intSecs),  cvt($nfs4CRename/$intSecs),  cvt($nfs4CLink/$intSecs),        
		cvt($nfs4CReadlink/$intSecs),cvt($nfs4CNull/$intSecs),    cvt($nfs4CSymlink/$intSecs), 
		'', '', '',                  cvt($nfs4CFsinfo/$intSecs),  cvt($nfs4CPathconf/$intSecs));
     printText($line);
    }

    if ($nfs4SFlag && $nfs4SSeen && ($nfsOpts!~/z/ || $nfs4SRead+$nfs4SWrite+$nfs4SMeta))
    {
      # Not Used: Null Pathconf Mkdir Mknod Readdirplus Fsinfo Fsstat Symlink Rmdir
      $line =sprintf("$datetime Svr4 %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s\n",
		cvt($nfs4SRead/$intSecs),    cvt($nfs4SWrite/$intSecs),   cvt($nfs4SCommit/$intSecs),
		cvt($nfs4SLookup/$intSecs),  cvt($nfs4SAccess/$intSecs),  cvt($nfs4SGetattr/$intSecs), 
		cvt($nfs4SSetattr/$intSecs), cvt($nfs4SReaddir/$intSecs), cvt($nfs4SCreate/$intSecs), 
		cvt($nfs4SRemove/$intSecs),  cvt($nfs4SRename/$intSecs),  cvt($nfs4SLink/$intSecs),        
		cvt($nfs4SReadlink/$intSecs));
      printText($line);
    }
  }

  if ($subsys=~/i/)
  {
    if (printHeader())
    {
      printText("\n")    if !$homeFlag;
      printText("# INODE SUMMARY\n");
      printText("#${miniFiller}     Dentries       File Handles    Inodes\n");
      printText("#${miniDateTime}  Number   Unused   Alloc   % Max   Number\n");
      exit(0)    if $showColFlag;
    }

    $line=sprintf("$datetime  %7s  %7s  %6s   %5.2f   %6s\n",
    	cvt($dentryNum,7), cvt($dentryUnused,7),
	cvt($filesAlloc,6),   $filesMax ? $filesAlloc*100/$filesMax : 0, 
	cvt($inodeUsed,6));
    printText($line);
  }

  # This is the normal output for an MDS and only skip if --lustopts D and only D
  # noting D output (which itself is only for hp-sfs), is handled elsewhere
  if ($subsys=~/l/ && $reportMdsFlag && $lustOpts ne 'D')
  {
    if (printHeader())
    {
        printText("\n")    if !$homeFlag;
 	printText("# LUSTRE MDS SUMMARY ($rate)\n");
        printText("#${miniDateTime} Getattr GttrLck  StatFS    Sync  Gxattr  Sxattr Connect Disconn");
  	printText(" Reint")                                  if $cfsVersion lt '1.6.5';
  	printText(" Create   Link Setattr Rename Unlink")    if $cfsVersion ge '1.6.5';
	printText("\n");
        exit(0)    if $showColFlag;
    }

    # Don't report if exception processing in effect and we're below limit
    # NOTE - exception processing only for versions < 1.6.5
    if ($options!~/x/ || $cfsVersion ge '1.6.5' || $lustreMdsReint/$intSecs>=$limLusReints)
    {
      $line.=sprintf("$datetime  %7d %7d %7d %7d %7d %7d %7d %7d",
            $lustreMdsGetattr/$intSecs,  $lustreMdsGetattrLock/$intSecs,
            $lustreMdsStatfs/$intSecs,   $lustreMdsSync/$intSecs,
            $lustreMdsGetxattr/$intSecs, $lustreMdsSetxattr/$intSecs,
            $lustreMdsConnect/$intSecs,  $lustreMdsDisconnect/$intSecs);

      if ($cfsVersion lt '1.6.5')
      {
        $line.=sprintf(" %5d", $lustreMdsReint/$intSecs);
      }
      else
      {
        $line.=sprintf(" %6d %6d %7d %6d %6d",
	    $lustreMdsReintCreate/$intSecs,  $lustreMdsReintLink/$intSecs, 
	    $lustreMdsReintSetattr/$intSecs, $lustreMdsReintRename/$intSecs,
	    $lustreMdsReintUnlink/$intSecs);
      }
    }
    $line.="\n";
    printText($line);
  }

  # This is the normal output for an OST and only skip if --lustopts D and only D
  # noting D output (which itself is only for hp-sfs), is handled elsewhere
  if ($subsys=~/l/ && $reportOstFlag && $lustOpts ne 'D')
  {
    if (printHeader())
    {
        printText("\n")    if !$homeFlag;
 	printText("# LUSTRE OST SUMMARY ($rate)\n");
        if ($lustOpts!~/B/)
        {
          printText("#${miniDateTime}  KBRead   Reads  SizeKB  KBWrite  Writes  SizeKB\n");
        }
        else
        {
          printText("#${miniFiller}<----------------------reads-------------------------|");
          printText("-----------------------writes------------------------->\n");
          $temp='';
          foreach my $i (@brwBuckets)
          { $temp.=sprintf(" %3dP", $i); }
          printText("#${miniDateTime}RdK  Rds$temp WrtK Wrts$temp\n");
	}
        exit(0)    if $showColFlag;
    }

    $line=$datetime;
    if ($lustOpts!~/B/)
    {
      $line.=sprintf("  %7d  %6d  %6s  %7d  %6d  %6s",
          $lustreReadKBytesTot/$intSecs,  $lustreReadOpsTot/$intSecs,
	  $lustreReadOpsTot ? cvt($lustreReadKBytesTot/$lustreReadOpsTot,6,0,1) : 0,
          $lustreWriteKBytesTot/$intSecs, $lustreWriteOpsTot/$intSecs,
	  $lustreWriteOpsTot ? cvt($lustreWriteKBytesTot/$lustreWriteOpsTot,6,0,1) : 0);
    }
    else
    {
      $line.=sprintf("%4s %4s",
	  cvt($lustreReadKBytesTot/$intSecs,4,0,1), cvt($lustreReadOpsTot/$intSecs));
      for ($i=0; $i<$numBrwBuckets; $i++)
      {
        $line.=sprintf(" %4s", cvt($lustreBufReadTot[$i]/$intSecs));
      }

      $line.=sprintf(" %4s %4s",
  	  cvt($lustreWriteKBytesTot/$intSecs,4,0,1), cvt($lustreWriteOpsTot/$intSecs));
      for ($i=0; $i<$numBrwBuckets; $i++)
      {
	$line.=sprintf(" %4s", cvt($lustreBufWriteTot[$i]/$intSecs));
      }
    }
    $line.="\n";
    printText($line);
  }

  # NOTE - this only applies to hp-sfs
  if ($subsys=~/l/ && ($reportMdsFlag || $reportOstFlag) && $lustOpts=~/D/)
  {
    if (printHeader())
    {
      printText("\n")    if !$homeFlag;
      printText("# LUSTRE DISK BLOCK LEVEL SUMMARY ($rate)\n#$miniFiller");
      $temp='';

      # not even room to preceed sizes with r/w's.
      foreach my $i (@diskBuckets)
      { 
        #last    if $i>$LustreMaxBlkSize;
        if ($i<1000) { $temp.=sprintf(" %3sK", $i) } else { $temp.=sprintf(" %3dM", $i/1024); }
      }
      printText("RdK  Rds$temp WrtK Wrts$temp\n");
      exit(0)    if $showColFlag;
    }

    # Now do the data
    $line=$datetime;
    $line.=sprintf("%4s %4s",
          cvt($lusDiskReadBTot[$LusMaxIndex]*0.5/$intSecs),
	  cvt($lusDiskReadsTot[$LusMaxIndex]/$intSecs));
    for ($i=0; $i<$LusMaxIndex; $i++)
    {
      $line.=sprintf(" %4s", cvt($lusDiskReadsTot[$i]/$intSecs));
    }
    $line.=sprintf(" %4s %4s",
          cvt($lusDiskWriteBTot[$LusMaxIndex]*0.5/$intSecs),
	  cvt($lusDiskWritesTot[$LusMaxIndex]/$intSecs));
    for ($i=0; $i<$LusMaxIndex; $i++)
    {
      $line.=sprintf(" %4s", cvt($lusDiskWritesTot[$i]/$intSecs));
    }
    printText("$line\n");
  }

  if ($subsys=~/L/ && $reportOstFlag && ($lustOpts=~/B/ || $lustOpts!~/D/))
  {
    if (printHeader())
    {
      # build ost header, and when no date/time make it even 1 char less.
      $temp="Ost". ' 'x$OstWidth;
      $temp=substr($temp, 0, $OstWidth);
      $temp=substr($temp, 0, $OstWidth-2).' '    if $miniFiller eq '';

      # When doing dates/time shift first field over 1 to the left;
      $fill1='';
      if ($miniFiller ne '')
      {
        $fill1=substr($miniDateTime, 0, length($miniFiller)-1);
      }

      printText("\n")    if !$homeFlag;
      printText("# LUSTRE FILESYSTEM SINGLE OST STATISTICS ($rate)\n");
      if ($lustOpts!~/B/)
      {
        printText("#$fill1$temp   KBRead   Reads  SizeKB    KBWrite  Writes  SizeKB\n");
      }
      else
      {
        $temp2='';
        foreach my $i (@brwBuckets)
        { $temp2.=sprintf(" %3dP", $i); }
        printText("#$fill1$temp   RdK  Rds$temp2 WrtK Wrts$temp2\n");
      }
      exit(0)    if $showColFlag;
    }

    for ($i=0; $i<$NumOst; $i++)
    {
      # If exception processing in effect, make sure this entry qualities
      next    if $options=~/x/ && 
	      $lustreReadKBytes[$i]/$intSecs<$limLusKBS &&
	      $lustreWriteKBytes[$i]/$intSecs<$limLusKBS;

      $line='';
      if ($lustOpts!~/B/)
      {
        $line.=sprintf("$datetime%-${OstWidth}s  %7d  %6d  %6d    %7d  %6d  %6d\n",
	       $lustreOsts[$i],
	       $lustreReadKBytes[$i]/$intSecs,  $lustreReadOps[$i]/$intSecs,
               $lustreReadOps[$i] ? $lustreReadKBytes[$i]/$lustreReadOps[$i] : 0,
	       $lustreWriteKBytes[$i]/$intSecs, $lustreWriteOps[$i]/$intSecs,
               $lustreWriteOps[$i] ? $lustreWriteKBytes[$i]/$lustreWriteOps[$i] : 0);
      }
      else
      {
        $line.=sprintf("$datetime%-${OstWidth}s  %4s %4s",
	       $lustreOsts[$i], 
               cvt($lustreReadKBytes[$i]/$intSecs,4,0,1),
	       cvt($lustreReadOps[$i]/$intSecs));
        for ($j=0; $j<$numBrwBuckets; $j++)
        {
	  $line.=sprintf(" %4s", cvt($lustreBufRead[$i][$j]/$intSecs));
        }

        $line.=sprintf(" %4s %4s",
               cvt($lustreWriteKBytes[$i]/$intSecs,4,0,1),
  	       cvt($lustreWriteOps[$i]/$intSecs));
        for ($j=0; $j<$numBrwBuckets; $j++)
        {
	  $line.=sprintf(" %4s", cvt($lustreBufWrite[$i][$j]/$intSecs));
        }
	$line.="\n";
      }
      printText($line);
    }
  }

  if ($subsys=~/L/ && $lustOpts=~/D/)
  {
    if (printHeader())
    {
      printText("\n")    if !$homeFlag;
      printText("# LUSTRE DISK BLOCK LEVEL DETAIL ($rate, units are 512 bytes)\n#$miniFiller");
      $temp='';
      foreach my $i (@diskBuckets)
      { 
        #last    if $i>$LustreMaxBlkSize;
        if ($i<1000) { $temp.=sprintf(" %3sK", $i) } else { $temp.=sprintf(" %3dM", $i/1024); }
      }
      printText("DISK RdK  Rds$temp WrtK Wrts$temp\n");
      exit(0)    if $showColFlag;
    }

    # Now do the data
    for ($i=0; $i<$NumLusDisks; $i++)
    {
      $line=$datetime;
      $line.=sprintf("%4s %4s %4s",
	     $LusDiskNames[$i], 
             cvt($lusDiskReadB[$i][$LusMaxIndex]*0.5/$intSecs),
	     cvt($lusDiskReads[$i][$LusMaxIndex]/$intSecs));
      for ($j=0; $j<$LusMaxIndex; $j++)
      {
	$temp=(defined($lusDiskReads[$i][$j])) ? cvt($lusDiskReads[$i][$j]/$intSecs) : 0;
        $line.=sprintf(" %4s", $temp);
      }
      $line.=sprintf(" %4s %4s",
             cvt($lusDiskWriteB[$i][$LusMaxIndex]*0.5/$intSecs),
	     cvt($lusDiskWrites[$i][$LusMaxIndex]/$intSecs));
      for ($j=0; $j<$LusMaxIndex; $j++)
      {
	$temp=(defined($lusDiskWrites[$i][$j])) ? cvt($lusDiskWrites[$i][$j]/$intSecs) : 0;
        $line.=sprintf(" %4s", $temp);
      }
      printText("$line\n");
    }
  }

  # NOTE - there are a number of different types of formats here and we're always going
  # to include reads/writes with all of them!
  if ($subsys=~/l/ && $reportCltFlag)
  {
    # If time for common header, do it...
    if (printHeader())
    {
      printText("\n")    if !$homeFlag;
      printText("# LUSTRE CLIENT SUMMARY ($rate)");
      printText(":")                       if $lustOpts=~/[BMR]/;
      printText(" RPC-BUFFERS (pages)")    if $lustOpts=~/B/;
      printText(" METADATA")               if $lustOpts=~/M/;
      printText(" READAHEAD")              if $lustOpts=~/R/;
      printText("\n");
    }

    # If exception processing must be above minimum
    if ($options!~/x/ || 
	    $lustreCltReadKBTot/$intSecs>=$limLusKBS ||
            $lustreCltWriteKBTot/$intSecs>=$limLusKBS)
    {
      if ($lustOpts!~/[BMR]/)
      {
        printText("#$miniDateTime  KBRead  Reads SizeKB   KBWrite Writes SizeKB\n")
		   if printHeader();
        exit(0)    if $showColFlag;

        $line=sprintf("$datetime  %7d %6d %6d   %7d %6d %6d\n",
	    $lustreCltReadKBTot/$intSecs,  $lustreCltReadTot/$intSecs,
	    $lustreCltReadTot ? int($lustreCltReadKBTot/$lustreCltReadTot) : 0,
	    $lustreCltWriteKBTot/$intSecs, $lustreCltWriteTot/$intSecs,
	    $lustreCltWriteTot ? int($lustreCltWriteKBTot/$lustreCltWriteTot) : 0);
        printText($line);
      }

      if ($lustOpts=~/B/)
      {
        if (printHeader())
        {
          $temp='';
  	  foreach my $i (@brwBuckets)
          { $temp.=sprintf(" %3dP", $i); }
	  printText("#${miniDateTime}RdK  Rds$temp WrtK Wrts$temp\n");
          exit(0)    if $showColFlag;
        }

        $line="$datetime";
        $line.=sprintf("%4s %4s", 
	    cvt($lustreCltReadKBTot/$intSecs,4,0,1), cvt($lustreCltReadTot/$intSecs));
        for ($i=0; $i<$numBrwBuckets; $i++)
        {
	  $line.=sprintf(" %4s", cvt($lustreCltRpcReadTot[$i]/$intSecs));
        }

        $line.=sprintf(" %4s %4s",
            cvt($lustreCltWriteKBTot/$intSecs,4,0,1), cvt($lustreCltWriteTot/$intSecs));
        for ($i=0; $i<$numBrwBuckets; $i++)
        {
	  $line.=sprintf(" %4s", cvt($lustreCltRpcWriteTot[$i]/$intSecs));
        }
        printText("$line\n");
      }

      if ($lustOpts=~/M/)
      {
        printText("#$miniDateTime  KBRead  Reads  KBWrite Writes  Open Close GAttr SAttr  Seek Fsynk DrtHit DrtMis\n")
		   if printHeader();
        exit(0)    if $showColFlag;

        $line=sprintf("$datetime  %7d %6d  %7d %6d %5d %5d %5d %5d %5d %5d %6d %6d\n",
	    $lustreCltReadKBTot/$intSecs,    $lustreCltReadTot/$intSecs,   
	    $lustreCltWriteKBTot/$intSecs,   $lustreCltWriteTot/$intSecs,   
	    $lustreCltOpenTot/$intSecs,      $lustreCltCloseTot/$intSecs, 
	    $lustreCltGetattrTot/$intSecs,   $lustreCltSetattrTot/$intSecs, 
	    $lustreCltSeekTot/$intSecs,      $lustreCltFsyncTot/$intSecs,  
            $lustreCltDirtyHitsTot/$intSecs, $lustreCltDirtyMissTot/$intSecs);
        printText($line);
      }

      if ($lustOpts=~/R/)
      {
        printText("#$miniDateTime  KBRead  Reads  KBWrite Writes  Pend  Hits Misses NotCon MisWin FalGrb LckFal  Discrd ZFile ZerWin RA2Eof HitMax  Wrong\n")
		   if printHeader();
        exit(0)    if $showColFlag;

        $line=sprintf("$datetime  %7d %6d  %7d %6d %5d %5d %6d %6d %6d %6d %6d %6d %6d %6d %6d %6d %6d\n",
	    $lustreCltReadKBTot/$intSecs,     $lustreCltReadTot/$intSecs,   
	    $lustreCltWriteKBTot/$intSecs,    $lustreCltWriteTot/$intSecs,   
            $lustreCltRAPendingTot/$intSecs,  $lustreCltRAHitsTot/$intSecs,
            $lustreCltRAMissesTot/$intSecs,   $lustreCltRANotConTot/$intSecs,
            $lustreCltRAMisWinTot/$intSecs,   $lustreCltRAFalGrabTot/$intSecs,
            $lustreCltRALckFailTot/$intSecs,  $lustreCltRAReadDiscTot/$intSecs, 
            $lustreCltRAZeroLenTot/$intSecs,  $lustreCltRAZeroWinTot/$intSecs,  
            $lustreCltRA2EofTot/$intSecs,     $lustreCltRAHitMaxTot/$intSecs,
            $lustreCltRAWrongTot/$intSecs);
        printText($line);
      }
    }
  }

  # NOTE -- there are 2 levels of details, both with and without --lustopts O
  if ($subsys=~/L/ && $reportCltFlag)
  {
    if (printHeader())
    {
      # we need to build filesystem header, and when no date/time make it even 1
      # char less.
      $temp="Filsys". ' 'x$FSWidth;
      $temp=substr($temp, 0, $FSWidth);
      $temp=substr($temp, 0, $FSWidth-2).' '    if $miniFiller eq '';

      # When doing dates/time, we also need to shift first field over 1 to the left;
      $fill1='';
      if ($miniFiller ne '')
      {
        $fill1=substr($miniDateTime, 0, length($miniFiller)-1);
      }

      printText("\n")    if !$homeFlag;
      printText("# LUSTRE CLIENT DETAIL ($rate)");
      printText(":")                       if $lustOpts=~/[BMR]/;
      printText(" RPC-BUFFERS (pages)")    if $lustOpts=~/B/;
      printText(" METADATA")               if $lustOpts=~/M/;
      printText(" READAHEAD")              if $lustOpts=~/R/;
      printText("\n");
    }

    if ($lustOpts=~/O/)
    {
      # Never for M or R
      if ($lustOpts!~/B/)
      {
        $fill2=' 'x($OstWidth-3);
        printText("#$fill1$temp Ost$fill2  KBRead  Reads SizeKB  KBWrite Writes SizeKB\n")
	           if printHeader();
        exit(0)    if $showColFlag;
 
        for ($i=0; $i<$NumLustreCltOsts; $i++)
        {
          $line=sprintf("$datetime%-${FSWidth}s %-${OstWidth}s %7d %6d %6d  %7d %6d %6d\n",
		    $lustreCltOstFS[$i], $lustreCltOsts[$i],
	    	    defined($lustreCltLunReadKB[$i]) ? $lustreCltLunReadKB[$i]/$intSecs : 0,
		    $lustreCltLunRead[$i]/$intSecs,
                    (defined($lustreCltLunReadKB[$i]) && $lustreCltLunRead[$i]) ? $lustreCltLunReadKB[$i]/$lustreCltLunRead[$i] : 0,
	   	    defined($lustreCltLunWriteKB[$i]) ? $lustreCltLunWriteKB[$i]/$intSecs : 0,
	    	    $lustreCltLunWrite[$i]/$intSecs,
                    (defined($lustreCltLunWriteKB[$i]) && $lustreCltLunWrite[$i]) ? $lustreCltLunWriteKB[$i]/$lustreCltLunWrite[$i] : 0);
          printText($line);
        }
      }

      if ($lustOpts=~/B/)
      {
        $fill2=' 'x($OstWidth-3);
        if (printHeader())
        {
          $temp2=' 'x(length("$fill1$temp Ost$fill2 "));
          $temp3='';
  	  foreach my $i (@brwBuckets)
          { $temp3.=sprintf(" %3dP", $i); }
	  printText("#$fill1$temp Ost$fill2 RdK  Rds$temp3 WrtK Wrts$temp3\n");
        }
        for ($clt=0; $clt<$NumLustreCltOsts; $clt++)
        {
          $line=sprintf("$datetime%-${FSWidth}s %-${OstWidth}s", $lustreCltOstFS[$clt], $lustreCltOsts[$clt]);
          $line.=sprintf("%4s %4s", 
                 cvt($lustreCltLunReadKB[$clt]/$intSecs,4,0,1), cvt($lustreCltLunRead[$clt]/$intSecs));

          for ($i=0; $i<$numBrwBuckets; $i++)
          {
	    $line.=sprintf(" %4s", cvt($lustreCltRpcRead[$clt][$i]/$intSecs));
          }

          $line.=sprintf(" %4s %4s",
    	         cvt($lustreCltLunWriteKB[$clt]/$intSecs,4,0,1), cvt($lustreCltLunWrite[$clt]/$intSecs));
          for ($i=0; $i<$numBrwBuckets; $i++)
          {
	    $line.=sprintf(" %4s", cvt($lustreCltRpcWrite[$clt][$i]/$intSecs));
          }
          printText("$line\n");
        }
      }
    }
    else
    {
      $commonLine= "#$fill1$temp  KBRead  Reads SizeKB  KBWrite Writes SizeKB";
      if ($lustOpts!~/[MR]/)
      {
        printText("$commonLine\n")    if printHeader();
        exit(0)    if $showColFlag;

        for ($i=0; $i<$NumLustreFS; $i++)
        {
          $line=sprintf("$datetime%-${FSWidth}s %7d %6d %6d  %7d %6d %6d\n",
	    $lustreCltFS[$i],
	    $lustreCltReadKB[$i]/$intSecs,  $lustreCltRead[$i]/$intSecs,
	    $lustreCltRead[$i] ? $lustreCltReadKB[$i]/$lustreCltRead[$i] : 0,
	    $lustreCltWriteKB[$i]/$intSecs, $lustreCltWrite[$i]/$intSecs,
            $lustreCltWrite[$i] ? $lustreCltWriteKB[$i]/$lustreCltWrite[$i] : 0);
          printText($line);
        }
      }

      if ($lustOpts=~/M/)
      {
        printText("$commonLine  Open Close GAttr SAttr  Seek Fsync DrtHit DrtMis\n")
		   if printHeader();
        exit(0)    if $showColFlag;

        {
          for ($i=0; $i<$NumLustreFS; $i++)
          {
            $line=sprintf("$datetime%-${FSWidth}s %7d %6d %6d  %7d %6d %6d %5d %5d %5d %5d %5d %5d %6d %6d\n",
	    $lustreCltFS[$i],
	    $lustreCltReadKB[$i]/$intSecs,    $lustreCltRead[$i]/$intSecs,
	    $lustreCltRead[$i] ? $lustreCltReadKB[$i]/$lustreCltRead[$i] : 0,
	    $lustreCltWriteKB[$i]/$intSecs,   $lustreCltWrite[$i]/$intSecs,
            $lustreCltWrite[$i] ? $lustreCltWriteKB[$i]/$lustreCltWrite[$i] : 0,
	    $lustreCltOpen[$i]/$intSecs,      $lustreCltClose[$i]/$intSecs, 
	    $lustreCltGetattr[$i]/$intSecs,   $lustreCltSetattr[$i]/$intSecs, 
	    $lustreCltSeek[$i]/$intSecs,      $lustreCltFsync[$i]/$intSecs,  
            $lustreCltDirtyHits[$i]/$intSecs, $lustreCltDirtyMiss[$i]/$intSecs);
            printText($line);
          }
        }
      }

      if ($lustOpts=~/R/)
      {
        printText("$commonLine  Pend  Hits Misses NotCon MisWin FalGrb LckFal  Discrd ZFile ZerWin RA2Eof HitMax  Wrong\n")
		   if printHeader();
        exit(0)    if $showColFlag;

        {
          for ($i=0; $i<$NumLustreFS; $i++)
          {
            $line=sprintf("$datetime%-${FSWidth}s %7d %6d %6d  %7d %6d %6d %5d %5d %6d %6d %6d %6d %6d %6d %6d %6d %6d %6d %6d\n",
	    $lustreCltFS[$i],
	    $lustreCltReadKBTot/$intSecs,    $lustreCltReadTot/$intSecs, 
	    $lustreCltRead[$i] ? $lustreCltReadKB[$i]/$lustreCltRead[$i] : 0,
            $lustreCltWriteKBTot/$intSecs,   $lustreCltWriteTot/$intSecs, 
            $lustreCltWrite[$i] ? $lustreCltWriteKB[$i]/$lustreCltWrite[$i] : 0,
            $lustreCltRAPendingTot/$intSecs, $lustreCltRAHitsTot/$intSecs,
            $lustreCltRAMissesTot/$intSecs,  $lustreCltRANotConTot/$intSecs,  $lustreCltRAMisWinTot/$intSecs, 
            $lustreCltRAFalGrabTot/$intSecs, $lustreCltRALckFailTot/$intSecs, $lustreCltRAReadDiscTot/$intSecs,
            $lustreCltRAZeroLenTot/$intSecs, $lustreCltRAZeroWinTot/$intSecs, $lustreCltRA2EofTot/$intSecs,
            $lustreCltRAHitMaxTot/$intSecs,  $lustreCltRAWrongTot/$intSecs);
            printText($line);
          }
        }
      }
    }
  }

  if ($subsys=~/m/)
  {
    if (printHeader())
    {
      # Note that sar does page sizes in numbers of pages, not bytes
      printText("\n")    if !$homeFlag;
      my $type=($memOpts!~/R/) ? '' : ' changes/int';
      printText("# MEMORY SUMMARY$type\n");
      if ($memOpts!~/R/)
      {
        $line="#$miniFiller";
        $line.="<-------------------------------Physical Memory-------------------------------------->"    if $memOpts eq '' || $memOpts=~/P/;
        $line.="<-----------Swap------------><-------Paging------>"                                        if $memOpts eq '' || $memOpts=~/V/;
        $line.="<---Other---|-------Page Alloc------|------Page Refill----->"                              if $memOpts=~/p/;
        $line.="<------Page Steal-------|-------Scan KSwap------|------Scan Direct----->"                  if $memOpts=~/s/;
        printText("$line\n");

        $line="#$miniFiller";
        $line.="   Total    Used    Free    Buff  Cached    Slab  Mapped    Anon  Commit  Locked Inact"    if $memOpts eq '' || $memOpts=~/P/;
        $line.=" Total  Used  Free   In  Out Fault MajFt   In  Out"                                        if $memOpts eq '' || $memOpts=~/V/;
        $line.="  Free Activ   Dma Dma32  Norm  Move   Dma Dma32  Norm  Move"                              if $memOpts=~/p/;
        $line.="   Dma Dma32  Norm  Move   Dma Dma32  Norm  Move   Dma Dma32  Norm  Move"                  if $memOpts=~/s/;
        printText("$line\n");
      }
      else
      {
        $line=sprintf("#$miniFiller<-----------------------------------Physical Memory-------------------------------------------><------------Swap-------------><-------Paging------>\n");
        printText($line);
        printText("#$miniDateTime   Total     Used     Free     Buff   Cached     Slab   Mapped     Anon  Commit  Locked   Inact Total   Used   Free   In  Out Fault MajFt   In  Out\n");
      }
    exit(0)    if $showColFlag;
    }

    if ($memOpts!~/R/)
    {
      $line="$datetime ";
      $line.=sprintf(" %7s %7s %7s %7s %7s %7s %7s %7s %7s %7s %5s",
                cvt($memTot,7,1,1),          cvt($memUsed,7,1,1),         cvt($memFree,7,1,1),
                cvt($memBuf,7,1,1),          cvt($memCached,7,1,1),
                cvt($memSlab,7,1,1),         cvt($memMap,7,1,1),          cvt($memAnon,7,1,1),
                cvt($memCommit,7,1,1),       cvt($memLocked,7,1,1),       cvt($memInact,5,1,1))		  if $memOpts eq '' || $memOpts=~/P/;
      $line.=sprintf(" %5s %5s %5s %4s %4s %5s %5s %4s %4s",
                cvt($swapTotal,5,1,1),       cvt($swapUsed,5,1,1),        cvt($swapFree,5,1,1),
                cvt($swapin/$intSecs,5,1,1), cvt($swapout/$intSecs,5,1,1),
                cvt($pagefault/$intSecs,5),  cvt($pagemajfault/$intSecs,5),
                cvt($pagein/$intSecs,4),     cvt($pageout/$intSecs,4))		 		  	  if $memOpts eq '' || $memOpts=~/V/;
      $line.=sprintf(" %5s %5s %5s %5s %5s %5s %5s %5s %5s %5s",
                cvt($pageFree,5),       cvt($pageActivate,5),
		cvt($pageAllocDma,5),   cvt($pageAllocDma32,5),   cvt($pageAllocNormal,5),   cvt($pageAllocMove,5),
		cvt($pageRefillDma,5),  cvt($pageRefillDma32,5),  cvt($pageRefillNormal,5),  cvt($pageRefillMove,5))   if $memOpts=~/p/;
      $line.=sprintf(" %5s %5s %5s %5s %5s %5s %5s %5s %5s %5s %5s %5s",
                cvt($pageStealDma,5),   cvt($pageStealDma32,5),   cvt($pageStealNormal,5),   cvt($pageStealMove,5),
                cvt($pageKSwapDma,5),   cvt($pageKSwapDma32,5),   cvt($pageKSwapNormal,5),   cvt($pageKSwapMove,5),
                cvt($pageDirectDma,5),  cvt($pageDirectDma32,5),  cvt($pageDirectNormal,5),  cvt($pageDirectMove,5))   if $memOpts=~/s/;
      $line.="\n";
    }
    else
    {
      $line=sprintf("$datetime  %7s %8s %8s %8s %8s  %7s  %7s  %7s %7s %7s  %6s %5s %6s %6s %4s %4s %5s %5s %4s %4s\n",
            	cvt($memTot/$intSecs,7,1,1),     cvt($memUsedC/$intSecs,7,1,1),   cvt($memFreeC/$intSecs,7,1,1),
            	cvt($memBufC/$intSecs,7,1,1),    cvt($memCachedC/$intSecs,7,1,1),
		cvt($memSlabC/$intSecs,7,1,1),   cvt($memMapC/$intSecs,7,1,1),    cvt($memAnonC/$intSecs,7,1,1),
		cvt($memCommitC/$intSecs,7,1,1), cvt($memLockedC/$intSecs,7,1,1), cvt($memInactC/$intSecs,5,1,1),
            	cvt($swapTotal,5,1,1),           cvt($swapUsedC/$intSecs,5,1,1),  cvt($swapFreeC/$intSecs,5,1,1),
            	cvt($swapin/$intSecs,5,1,1),     cvt($swapout/$intSecs,5,1,1),
            	cvt($pagefault/$intSecs,5),      cvt($pagemajfault/$intSecs,5),
            	cvt($pagein/$intSecs,4),         cvt($pageout/$intSecs,4));

    }
    printText($line);
  }

  if ($subsys=~/M/)
  {
    if (printHeader())
    {
      printText("\n")    if !$homeFlag;
      my $type=($memOpts!~/R/) ? '' : " change$type";
      printText("# MEMORY STATISTICS $type\n");
      {
        # we've got the room so let's use an extra column for each and have the same
        # headers for 'R' and because I'm lazy.
        printText("#$miniFiller Node    Total     Used     Free     Slab   Mapped     Anon   Locked    Inact");
        printText(" Hit%")    if $memOpts!~/R/;
        printText("\n");
      }
      exit(0)    if $showColFlag;
    }

    $line='';
    for (my $i=0; $i<$CpuNodes; $i++)
    {
      if ($memOpts!~/R/)
      {
        # total hits can be 0 if no data collected
        my $misses=$numaStat[$i]->{for}+$numaStat[$i]->{miss};
        my $hitrate=($misses) ? $numaStat[$i]->{hits}/($numaStat[$i]->{hits}+$misses)*100/$intSecs : 0;
        $line.=sprintf("$datetime  %4d %8s %8s %8s %8s %8s %8s %8s %8s %4d\n", $i,
                cvt($numaMem[$i]->{used}+$numaMem[$i]->{free},7,1,1),
                cvt($numaMem[$i]->{used},7,1,1),  cvt($numaMem[$i]->{free},7,1,1),
                cvt($numaMem[$i]->{slab},7,1,1),  cvt($numaMem[$i]->{map},7,1,1),
                cvt($numaMem[$i]->{anon},7,1,1),  cvt($numaMem[$i]->{lock},7,1,1),
		cvt($numaMem[$i]->{inact},7,1,1), $hitrate);
      }
      else
      {
        $line.=sprintf("$datetime  %4d %8s %8s %8s %8s %8s %8s %8s %8s\n", $i,
                cvt($numaMem[$i]->{usedC}+$numaMem[$i]->{freeC},7,1,1),
                cvt($numaMem[$i]->{usedC},7,1,1), cvt($numaMem[$i]->{freeC},7,1,1),
                cvt($numaMem[$i]->{slabC},7,1,1), cvt($numaMem[$i]->{mapC},7,1,1),
                cvt($numaMem[$i]->{anonC},7,1,1), cvt($numaMem[$i]->{lockC},7,1,1),
		cvt($numaMem[$i]->{inactC},7,1,1));
      }
    }
    printText($line);
  }

  if ($subsys=~/b/)
  {
    if (printHeader())
    {
      my $k=$PageSize/1024;
      my $headers='';
      for (my $i=0; $i<11; $i++)
      {
        my $header=sprintf("%dPg%s", 2**$i, $i==0 ? '': 's');
	$headers.=sprintf("%8s", $header);
      }
      printText("\n")    if !$homeFlag;
      printText("# MEMORY FRAGMENTATION SUMMARY (${k}K pages)\n");
      printText("#${miniDateTime}$headers\n");
      exit(0)    if $showColFlag;
    }

    my $line="$datetime ";
    for (my $i=0; $i<11; $i++)
    {
      $line.=sprintf("%8d", $buddyInfoTot[$i]);
    }
    printText("$line\n");
  }

  if ($subsys=~/B/)
  {
    if (printHeader())
    {
      my $k=$PageSize/1024;
      my $headers='';
      for (my $i=0; $i<11; $i++)
      {
        my $header=sprintf("%dPg%s", 2**$i, $i==0 ? '': 's');
	$headers.=sprintf("%8s", $header);
      }
      printText("\n")    if !$homeFlag;
      printText("# MEMORY FRAGMENTATION (${k}K pages)\n");
      printText("#${miniDateTime}Node    Zone $headers\n");
      exit(0)    if $showColFlag;
    }

    for (my $i=0; $i<$NumBud; $i++)
    {
      my $line="$datetime ";
      $line.=sprintf("%4d  %6s ", $buddyNode[$i], $buddyZone[$i]);
      for (my $j=0; $j<11; $j++)
      {
        $line.=sprintf("%8d", $buddyInfo[$i][$j]);
      }
      printText("$line\n");
    }
  }

  if ($subsys=~/n/)
  {
    my $netErrors=$netRxErrsTot+$netTxErrsTot;
    if ($netOpts!~/E/ || $netErrors || $showColFlag)
    {
      if (printHeader())
      {
        my $errors=($netOpts=~/e/) ? 'ERRORS ' : '';
      	printText("\n")    if !$homeFlag;
        printText("# NETWORK ${errors}SUMMARY ($rate)\n");
        printText("#${miniDateTime} KBIn  PktIn SizeIn  MultI   CmpI  ErrsI  KBOut PktOut  SizeO   CmpO  ErrsO\n")
	    if $netOpts!~/e/;
        printText("#${miniDateTime}  ErrIn  DropIn  FifoIn FrameIn    ErrOut DropOut FifoOut CollOut CarrOut\n")
	           if $netOpts=~/e/;
        exit(0)    if $showColFlag;
      }

      # if --netopts E, only print lines when there are errors
      # remember 'errs' is the totals of all the rx/tx counters, 'err' is a single counter
      if ($netOpts!~/e/)
      {
        $line=sprintf("$datetime%6d %6d %6d %6d %6d %6d %6d %6d %6d %6d %6d\n",
            $netRxKBTot/$intSecs,  $netRxPktTot/$intSecs, $netRxPktTot ? $netRxKBTot*1024/$netRxPktTot : 0,
            $netRxMltTot/$intSecs, $netRxCmpTot/$intSecs, $netRxErrsTot/$intSecs,
            $netTxKBTot/$intSecs,  $netTxPktTot/$intSecs, $netTxPktTot ? $netTxKBTot*1024/$netTxPktTot : 0,
            $netTxCmpTot/$intSecs, $netTxErrsTot/$intSecs);
      }
      else
      {
        $line=sprintf("$datetime %7d %7d %7d %7d   %7d %7d %7d %7d %7d\n",
	    $netRxErrTot/$intSecs, $netRxDrpTot/$intSecs, $netRxFifoTot/$intSecs, $netRxFraTot/$intSecs,
	    $netTxErrTot/$intSecs, $netTxErrTot/$intSecs, $netTxDrpTot/$intSecs,  $netTxFifoTot/$intSecs,
            $netTxCollTot/$intSecs, $netTxCarTot/$intSecs);
      }
      printText($line);
    }

    # When we skip printing an interval when a single subsystem, our header counter
    # is off because it's been incremented, so back it up
    elsif ($subsys eq 'n')
    {
      $interval1Counter--;
    }
  }

  if ($subsys=~/N/)
  {
    # NOTE - header processing for detail data has always been ugly so let's not even
    # deal with error exception processing.
    if (printHeader())
    {
      my $errors=($netOpts=~/e/) ? 'ERRORS ' : '';
      my $tempName=' 'x($NetWidth-5).'Name';
      printText("\n")    if !$homeFlag;
      printText("# NETWORK ${errors}STATISTICS ($rate)\n");
      printText("#${miniDateTime}Num   $tempName   KBIn  PktIn SizeIn  MultI   CmpI  ErrsI  KBOut PktOut  SizeO   CmpO  ErrsO\n")
	    if $netOpts!~/e/;
      printText("#${miniDateTime}Num   $tempName   ErrIn  DropIn  FifoIn FrameIn    ErrOut DropOut FifoOut CollOut CarrOut\n")
	         if $netOpts=~/e/;
      exit(0)    if $showColFlag;
    }

    for ($i=0; $i<@netOrder; $i++)
    {
      $netName=$netOrder[$i];
      next    if !defined($netSeen[$i]);
      next    if ($netFiltKeep eq '' && $netName=~/$netFiltIgnore/) || ($netFiltKeep ne '' && $netName!~/$netFiltKeep/);

      my $netErrors=$netRxErrs[$i]+$netTxErrs[$i];
      if ($netOpts!~/e/)
      {
        $line=sprintf("$datetime %3d  %${NetWidth}s %6d %6d %6d %6d %6d %6d %6d %6d %6d %6d %6d\n",
	      $i, $netName, 
	      $netRxKB[$i]/$intSecs,  $netRxPkt[$i]/$intSecs, $netRxPkt[$i] ? $netRxKB[$i]*1024/$netRxPkt[$i] : 0,
              $netRxMlt[$i]/$intSecs, $netRxCmp[$i]/$intSecs, $netRxErrs[$i]/$intSecs,
              $netTxKB[$i]/$intSecs,  $netTxPkt[$i]/$intSecs, $netTxPkt[$i] ? $netTxKB[$i]*1024/$netTxPkt[$i] : 0,
              $netTxCmp[$i]/$intSecs, $netTxErrs[$i]/$intSecs);
      }
      else
      {
        $line=sprintf("$datetime %3d  %${NetWidth}s %7d %7d %7d %7d   %7d %7d %7d %7d %7d\n",
	      $i, $netName[$i], 
	      $netRxErr[$i]/$intSecs,  $netRxDrp[$i]/$intSecs, $netRxFifo[$i]/$intSecs, $netRxFra[$i]/$intSecs,
	      $netTxErr[$i]/$intSecs,  $netTxErr[$i]/$intSecs, $netTxDrp[$i]/$intSecs,  $netTxFifo[$i]/$intSecs,
              $netTxColl[$i]/$intSecs, $netTxCar[$i]/$intSecs);
      }
      printText($line)    if $netOpts!~/E/ || $netErrors;
    }
  }

  if ($subsys=~/s/)
  {
    if (printHeader())
    {
      printText("\n")    if !$homeFlag;
      printText("# SOCKET STATISTICS\n");
      printText("#${miniFiller}      <-------------Tcp------------->   Udp   Raw   <---Frag-->\n");
      printText("#${miniDateTime}Used  Inuse Orphan    Tw  Alloc   Mem  Inuse Inuse  Inuse   Mem\n");
      exit(0)    if $showColFlag;
    }

    $line=sprintf("$datetime%5d  %5d  %5d %5d  %5d %5d  %5d %5d  %5d %5d\n",
           $sockUsed, $sockTcp, $sockOrphan, $sockTw, $sockAlloc, $sockMem,
	   $sockUdp, $sockRaw, $sockFrag, $sockFragM);
    printText($line);
  }

  if ($subsys=~/t/)
  {
    if (printHeader())
    {
      printText("\n")    if !$homeFlag;
      printText("# TCP STACK SUMMARY ($rate)\n");
      $line= "#${miniFiller}";
      $line.="<----------------------------------IpPkts----------------------------------->"                 if $tcpFilt=~/i/;
      $line.="<---------------------------------Tcp--------------------------------->"                       if $tcpFilt=~/t/;
      $line.="<------------Udp----------->"                                                                  if $tcpFilt=~/u/;
      $line.="<----------------------------Icmp--------------------------->"                                 if $tcpFilt=~/c/;
      $line.="<-------------------------IpExt------------------------>"                                      if $tcpFilt=~/I/;
      $line.="<------------------------------------------TcpExt----------------------------------------->"   if $tcpFilt=~/T/;
      $line.="\n";

      $line.="#$miniFiller";
      $line.=" Receiv Delivr Forwrd DiscdI InvAdd   Sent DiscrO ReasRq ReasOK FragOK FragCr"		     if $tcpFilt=~/i/;
      $line.=" ActOpn PasOpn Failed ResetR  Estab   SegIn SegOut SegRtn SegBad SegRes"			     if $tcpFilt=~/t/;
      $line.="  InDgm OutDgm NoPort Errors"								     if $tcpFilt=~/u/;
      $line.=" Recvd FailI UnreI EchoI ReplI  Trans FailO UnreO EchoO ReplO"				     if $tcpFilt=~/c/;
      $line.=" MPktsI BPktsI OctetI MOctsI BOctsI MPktsI OctetI MOctsI"                                      if $tcpFilt=~/I/;
      $line.=" FasTim Reject DelAck QikAck PktQue PreQuB HdPdct AkNoPy PreAck DsAcks RUData REClos  SackS"   if $tcpFilt=~/T/;
      $line.="\n";
      printText($line);
    
      exit(0)    if $showColFlag;
    }

    $line="$datetime ";

    $line.=sprintf(" %6d %6d %6d %6d %6d %6d %6d %6d %6d %6d %6d",
			$tcpData{Ip}->{InReceives}/$intSecs,	$tcpData{Ip}->{InDelivers}/$intSecs, 
			$tcpData{Ip}->{ForwDatagrams}, 		$tcpData{Ip}->{InDiscards}, 
			$tcpData{Ip}->{InAddrErrors},  		$tcpData{Ip}->{OutRequests}/$intSecs,
			$tcpData{Ip}->{OutDiscards},   		$tcpData{Ip}->{ReasmReqds},
			$tcpData{Ip}->{ReasmOKs},      		$tcpData{Ip}->{FragOKs},
			$tcpData{Ip}->{FragCreates})
				if $tcpFilt=~/i/; 

    $line.=sprintf(" %6d %6d %6d %6d %6d  %6d %6d %6d %6d %6d",
			$tcpData{Tcp}->{ActiveOpens}/$intSecs,	$tcpData{Tcp}->{PassiveOpens}/$intSecs,
			$tcpData{Tcp}->{AttemptFails},		$tcpData{Tcp}->{EstabResets},
			$tcpData{Tcp}->{CurrEstab},		$tcpData{Tcp}->{InSegs}/$intSecs, 
			$tcpData{Tcp}->{OutSegs}/$intSecs,	$tcpData{Tcp}->{RetransSegs},
			$tcpData{Tcp}->{InErrs},       		$tcpData{Tcp}->{OutRsts})
				if $tcpFilt=~/t/;

    $line.=sprintf(" %6d %6d %6d %6d",
			$tcpData{Udp}->{InDatagrams}/$intSecs,	$tcpData{Udp}->{OutDatagrams}/$intSecs,
			$tcpData{Udp}->{NoPorts},      		$tcpData{Udp}->{InErrors})
				if $tcpFilt=~/u/;

    $line.=sprintf(" %5d %5d %5d %5d %5d  %5d %5d %5d %5d %5d",
			$tcpData{Icmp}->{InMsgs},		$tcpData{Icmp}->{InErrors},
			$tcpData{Icmp}->{InDestUnreachs},	$tcpData{Icmp}->{InEchos},
			$tcpData{Icmp}->{InEchoReps},		$tcpData{Icmp}->{OutMsgs},
			$tcpData{Icmp}->{OutErrors},		$tcpData{Icmp}->{OutDestUnreachs},
			$tcpData{Icmp}->{OutEchos},		$tcpData{Icmp}->{OutEchoReps})
				if $tcpFilt=~/c/;

    $line.=sprintf(" %6d %6d %6d %6d %6d %6d %6d %6d",
			$tcpData{IpExt}->{InMcastPkts}, 	$tcpData{IpExt}->{InBcastPkts},
			$tcpData{IpExt}->{InOctets}, 		$tcpData{IpExt}->{InMcastOctets},
			$tcpData{IpExt}->{InBcastOctets}, 	$tcpData{IpExt}->{OutMcastPkts},
			$tcpData{IpExt}->{OutOctets}, 		$tcpData{IpExt}->{OutMcastOctets})
				if $tcpFilt=~/I/;

    $line.=sprintf(" %6d %6d %6d %6d %6d %6d %6d %6d %6d %6d %6d %6d %6d",
			$tcpData{TcpExt}->{TW},		     	$tcpData{TcpExt}->{PAWSEstab},
			$tcpData{TcpExt}->{DelayedACKs},	$tcpData{TcpExt}->{DelayedACKLost},
			$tcpData{TcpExt}->{TCPPrequeued},	$tcpData{TcpExt}->{TCPDirectCopyFromPrequeue},
			$tcpData{TcpExt}->{TCPHPHits},	 	$tcpData{TcpExt}->{TCPPureAcks},
			$tcpData{TcpExt}->{TCPHPAcks}, 	 	$tcpData{TcpExt}->{TCPDSACKOldSent},
			$tcpData{TcpExt}->{TCPAbortOnData}, 	$tcpData{TcpExt}->{TCPAbortOnClose},
			$tcpData{TcpExt}->{TCPSackShiftFallback})
				if $tcpFilt=~/T/;

    $line.="\n";
    printText($line);
  }

  if ($subsys=~/E/ && $interval3Print)
  {
    if (printHeader())
    {
      printText("\n")    if !$homeFlag;
      printText("# ENVIRONMENTAL STATISTICS\n");
      $envNewHeader=1;
    }

    my $keyCounter=0;
    foreach $key (sort keys %$ipmiData)
    {
      next    if $key=~/fan/   && $envOpts!~/f/;
      next    if $key=~/power/ && $envOpts!~/p/;
      next    if $key=~/temp/  && $envOpts!~/t/;

      $keyCounter++;
      if ($keyCounter==1 || $envOpts=~/M/)
      {
        $envHeader="#$miniDateTime";
        $line="$datetime ";
      }

      for (my $i=0; $i<scalar(@{$ipmiData->{$key}}); $i++)
      {
        # we only do these when a main header printed
        if ($envNewHeader)
        {
          my $name=$ipmiData->{$key}->[$i]->{name};
          my $inst=$ipmiData->{$key}->[$i]->{inst};

          $name=sprintf("$name%s", $inst ne '-1' ? $inst : '');
          $envHeader.=sprintf(" %7s", $name);
        }

        # Not sure if I should be reporting 0 but that's why this is experimental!
        my $value= $ipmiData->{$key}->[$i]->{value};
        my $status=$ipmiData->{$key}->[$i]->{status};
        $line.=sprintf(" %7s", ($value ne '') ? $value : 0);
      }

      # a multi-line print is done for each unique type (currently just fan & temp)
      if ($envOpts=~/M/)
      {
        printText("$envHeader\n")    if $envNewHeader;
        printText("$line\n");
      }
    }

    # Non-multi-line prints only done once
    if ($envOpts!~/M/)
    {
      printText("$envHeader\n")    if $envNewHeader;
      exit(0)                      if $showColFlag;
      printText("$line\n");
    }
  }

  if ($subsys=~/x/)
  {
    if ($NumXRails)
    {
      if (printHeader())
      {
        printText("\n")    if !$homeFlag;
        printText("# ELAN4 SUMMARY ($rate)\n");
        printText("#${miniDateTime}OpsIn OpsOut   KBIn  KBOut Errors\n");
        exit(0)    if $showColFlag;
      }

      $elanErrors=$elanSendFailTot+$elanNeterrAtomicTot+$elanNeterrDmaTot;
      $line=sprintf("$datetime%6d %6d %6d %6d %6d\n",
	$elanRxTot/$intSecs,   $elanTxTot/$intSecs,
	$elanRxKBTot/$intSecs, $elanTxKBTot/$intSecs,
	$elanErrors/$intSecs);
      printText($line);
    }

    if ($NumHCAs)
    {
      if (printHeader())
      {
        printText("\n")    if !$homeFlag;
        printText("# INFINIBAND SUMMARY ($rate)\n");
        printText("#${miniDateTime}  KBIn   PktIn  SizeIn   KBOut  PktOut SizeOut  Errors\n");
        exit(0)    if $showColFlag;
      }

      $line=sprintf("$datetime%7d %7d %7d %7d %7d %7s %7s\n",
          $ibRxKBTot/$intSecs, $ibRxTot/$intSecs, $ibRxTot ? cvt($ibRxKBTot*1024/$ibRxTot,7,0,1) : 0,
          $ibTxKBTot/$intSecs, $ibTxTot/$intSecs, $ibTxTot ? cvt($ibTxKBTot*1024/$ibTxTot,7,0,1) : 0,
          $ibErrorsTotTot);
      printText($line);
    }
  }

  if ($subsys=~/X/)
  {
    if ($NumXRails)
    {
      if (printHeader())
      {
        printText("\n")    if !$homeFlag;
        printText("# ELAN4 STATISTICS ($rate)\n");
        printText("#${miniDateTime}Rail  OpsIn OpsOut  KB-In KB-Out OpsGet OpsPut KB-Get KB-Put   Comp CompKB SndErr AtmErr DmsErr\n");
        exit(0)    if $showColFlag;
      }

      for ($i=0; $i<$NumXRails; $i++)
      {
        $line=sprintf("$datetime %4d %6d %6d %6d %6d %6d %6d %6d %6d %6d %6d %6d %6d %6d\n",
	  $i, 
	  $elanRx[$i]/$intSecs,       $elanTx[$i]/$intSecs,
	  $elanRxKB[$i]/$intSecs,     $elanTxKB[$i]/$intSecs, 
	  $elanGet[$i]/$intSecs,      $elanPut[$i]/$intSecs,
	  $elanGetKB[$i]/$intSecs,    $elanPutKB[$i]/$intSecs, 
	  $elanComp[$i]/$intSecs,     $elanCompKB[$i]/$intSecs, 
	  $elanSendFail[$i]/$intSecs, $elanNeterrAtomic[$i]/$intSecs, 
	  $elanNeterrDma[$i]/$intSecs);
        printText($line);
      }
    }

    if ($NumHCAs)
    {
      if (printHeader())
      {
        printText("\n")    if !$homeFlag;
        printText("# INFINIBAND STATISTICS ($rate)\n");
        printText("#${miniDateTime}HCA    KBIn   PktIn  SizeIn   KBOut  PktOut SizeOut  Errors\n");
        exit(0)    if $showColFlag;
     }

      for ($i=0; $i<$NumHCAs; $i++)
      {
        $line=sprintf("$datetime  %2d %7d %7d %7d %7d %7d %7d %7d\n",
	  $i,
	  $ibRxKB[$i]/$intSecs, $ibRx[$i]/$intSecs, $ibRx[$i] ? $ibRxKB[$i]/$ibRx[$i] : 0,
	  $ibTxKB[$i]/$intSecs, $ibTx[$i]/$intSecs, $ibTx[$i] ? $ibTxKB[$i]/$ibTx[$i] : 0,
	  $ibErrorsTot[$i]);
        printText($line);
      }
    }
  }

  if ($subsys=~/y/ && $interval2Print)
  {
    if ($slabinfoFlag)
    {
      if (printHeader())
      {
        printText("\n")    if !$homeFlag;
        printText("# SLAB SUMMARY\n");
        printText("#${miniFiller}<------------Objects------------><--------Slab Allocation-------><--Caches--->\n");
        printText("#${miniDateTime}  InUse   Bytes    Alloc   Bytes   InUse   Bytes   Total   Bytes  InUse  Total\n");
        exit(0)    if $showColFlag;
      }

      $line=sprintf("$datetime %7s %7s  %7s %7s  %6s %7s  %6s %7s %6s %6s\n",
          cvt($slabObjActTotal,7),  cvt($slabObjActTotalB,7,0,1), 
	  cvt($slabObjAllTotal,7),  cvt($slabObjAllTotalB,7,0,1),
	  cvt($slabSlabActTotal,6), cvt($slabSlabActTotalB,7,0,1),
	  cvt($slabSlabAllTotal,6), cvt($slabSlabAllTotalB,7,0,1),
   	  cvt($slabNumAct,6),       cvt($slabNumTot,6));
      printText($line);
    }
    else
    {
      if (printHeader())
      {
        printText("\n")    if !$homeFlag;
        printText("# SLAB SUMMARY\n");
        printText("#${miniFiller}<---Objects---><-Slabs-><-----memory----->\n");
        printText("#${miniDateTime} In Use   Avail  Number      Used    Total\n");
        exit(0)    if $showColFlag;
      }
      $line=sprintf("$datetime %7s %7s %7s   %7s  %7s\n",
          cvt($slabNumObjTot,7),  cvt($slabObjAvailTot,7), cvt($slabNumTot,7),  
	  cvt($slabUsedTot,7,0,1), cvt($slabTotalTot,7,0,1));
      printText($line);
    }
  }

  # tricky - by definitio --showcolheaders only shows single lines headers, SO if multiple
  # imports and verbose, you only get the first!
  for (my $i=0; $i<$impNumMods; $i++)
  {
    &{$impPrintVerbose[$i]}(printHeader(), $homeFlag, \$line);
    printText($line)    if $line ne '';    # rare, but it can happen when no instances of a component (screws up colmux!)
    exit(0)    if $showColFlag;
  }

  # Since slabs/processes both report rates, we need to skip first printable interval
  # unless we're doing consecutive files
  printTermSlab()    if $subsys=~/Y/ && $interval2Print && (!$firstTime2 || $consecutiveFlag);
  printTermProc()    if $subsys=~/Z/ && $interval2Print && (!$firstTime2 || $consecutiveFlag);

  # if running with --home in --top mode we might have junk in the rest of the display when 
  # items come and go, which they can when doing things like disk filtering or displaying
  # processes so clear from the current location to the end of the display and reset $clscr
  # so we never clear the screen more than once but rather just overwrite what's there
  printText($clr)    if $homeFlag || ($numTop && $playback eq '');
  $clscr=$home;
}

sub printTermSlab
{
  # Much of the top-slab methodology stolen from printTermProc()
  my %slabSort;
  my $slabCount=0;
  my $eol=sprintf("%c[K", 27);
  printf "%c[%d;H", 27, $scrollEnd ? $scrollEnd+1 : 0    if $numTop && $playback eq '';

  # if someone wants to look at slabs with --home and NOT --top, let them!
  print "$clscr"   if !$numTop && $homeFlag;

  if (printHeader() || $numTop)
  {
    if ($numTop)
    {
      $temp2=(split(/\s+/,localtime($seconds)))[3];
      $temp2.=sprintf(".%03d", $usecs)    if $options=~/m/;
    }

    printText("\n")    if !$homeFlag;
    my $temp=(!$topSlabFlag) ? 'SLAB DETAIL' : "TOP SLABS $temp2";
    printText("# $temp\n");
    if ($topSlabFlag)
    {
      print "#NumObj  ActObj  ObjSize  NumSlab  Obj/Slab  TotSize  TotChg  TotPct  Name\n";
    }
    elsif ($slabinfoFlag)
    {
      printText("#${miniFiller}                           <-----------Objects----------><---------Slab Allocation------><---Change-->\n");
      printText("#${miniDateTime}Name                       InUse   Bytes   Alloc   Bytes   InUse   Bytes   Total   Bytes   Diff    Pct\n");
    }
    else
    {
      printText("#${miniFiller}                             <----------- objects --------><--- slabs ---><---------allocated memory-------->\n");
      printText("#${miniDateTime}Slab Name                    Size  /slab   In Use    Avail  SizeK  Number     UsedK    TotalK   Change    Pct\n");
    }
    exit(0)    if $showColFlag;
  }

  if ($slabinfoFlag)
  {
    for ($i=0; $i<$slabIndexNext; $i++)
    {
      if (!$topSlabFlag || $topType eq 'name') {
        $key=$slabName[$i];
      } elsif ($topType eq 'numobj') {
        $key=sprintf('%9d', 999999999-$slabObjAllTot[$i]);
      } elsif ($topType eq 'actobj') {
        $key=sprintf('%9d', 999999999-$slabObjActTot[$i]);
      } elsif ($topType eq 'objsize') {
        $key=sprintf('%9d', 999999999-$slabObjSize[$i]);
      } elsif ($topType eq 'numslab') {
        $key=sprintf('%9d', 999999999-$slabSlabActTot[$i]);
      } elsif ($topType eq 'objslab') {
        $key=sprintf('%9d', 999999999-$slabObjPerSlab[$i]);
      } elsif ($topType eq 'totsize') {
        $key=sprintf('%9d', 999999999-$slabSlabAllTotB[$i]);
      } elsif ($topType eq 'totchg') {
        $key=sprintf('%9d', 999999999-abs($slabTotMemChg[$i]));
      } elsif ($topType eq 'totpct') {
        $key=sprintf('%9d', 999999999-abs($slabTotMemPct[$i]));
	      }
      $slabSort{"$key-$i"}=$i;    # need to include '-$i' to allow duplicates
    }

    foreach $key (sort keys %slabSort)
    {
      $i=$slabSort{$key};

      # the first test is for filtering out zero-size slabs and the
      # second for slabs that didn't change this during this interval
      next    if (($slabSlabAllTot[$i]==0 && ($topSlabFlag || $slabOpts=~/s/)) || 
 	          ($slabOpts=~/S/ && $slabSlabAct[$i]==0 && $slabSlabAll[$i]==0));

      if ($topSlabFlag)
      {
        last    if ++$slabCount>$numTop;
	$line=sprintf("%7s %7s  %7s  %7s   %7s  %7s %7s  %6.1f  %s",
		cvt($slabObjAllTot[$i],6),  cvt($slabObjActTot[$i],6), 
		cvt($slabObjSize[$i],6),    cvt($slabSlabActTot[$i],6),
		cvt($slabObjPerSlab[$i],6), cvt($slabSlabAllTotB[$i],4,0,1), 
		cvt($slabTotMemChg[$i],4,0,1),$slabTotMemPct[$i], $slabName[$i]);

        $line.=$eol    if $playback eq '' && $numTop;
        $line.="\n"    if $playback ne '' || !$numTop || $slabCount<$numTop;
        printText($line);
        next;
      }

      $line=sprintf("$datetime%-25s %7s %7s  %6s %7s  %6s %7s  %6s %7s %6s %6.1f\n",
          substr($slabName[$i],0,25),
	  cvt($slabObjActTot[$i],6),    cvt($slabObjActTotB[$i],7,0,1), 
  	  cvt($slabObjAllTot[$i],6),    cvt($slabObjAllTotB[$i],7,0,1),
	  cvt($slabSlabActTot[$i],6),   cvt($slabSlabActTotB[$i],7,0,1),
	  cvt($slabSlabAllTot[$i],6),   cvt($slabSlabAllTotB[$i],7,0,1),
	  cvt($slabTotMemChg[$i],7,0,1),$slabTotMemPct[$i]);

      printText($line);
    }
  }
  else
  {
    foreach my $first (sort keys %slabfirst)
    {
      my $slab=$slabfirst{$first};
      if (!$topSlabFlag || $topType eq 'name') {
        $key=lc($first);   # otherwise all upper-case names will come first
      } elsif ($topType eq 'numobj') {
        $key=sprintf('%9d', 999999999-$slabdata{$slab}->{slabsize}*$slabdata{$slab}->{avail});
      } elsif ($topType eq 'actobj') {
        $key=sprintf('%9d', 999999999-$slabdata{$slab}->{slabsize}*$slabdata{$slab}->{objects});
      } elsif ($topType eq 'objsize') {
        $key=sprintf('%9d', 999999999-$slabdata{$slab}->{slabsize});
      } elsif ($topType eq 'numslab') {
        $key=sprintf('%9d', 999999999-$slabdata{$slab}->{slabs});
      } elsif ($topType eq 'objslab') {
        $key=sprintf('%9d', 999999999-$slabdata{$slab}->{objper});
      } elsif ($topType eq 'totsize') {
        $key=sprintf('%9d', 999999999-$slabdata{$slab}->{total});
      } elsif ($topType eq 'totchg') {
        $key=sprintf('%9d', 999999999-abs($slabdata{$slab}->{memchg}));
      } elsif ($topType eq 'totpct') {
        $key=sprintf('%9d', 999999999-abs($slabdata{$slab}->{mempct}));
      }	
      $slabSort{"$key-$first"}=$first;    # need to include '-$first' to allow duplicates
    }

    foreach my $key (sort keys %slabSort)
    {
      my $first=$slabSort{$key};
      my $slab=$slabfirst{$first};

      # as for regular slabs, the first test is for filtering out zero-size
      # slabs and the second for slabs that didn't change this during this interval
      my $numObjects=$slabdata{$slab}->{objects};
      my $numSlabs=  $slabdata{$slab}->{slabs};
      next    if (($slabdata{$slab}->{objects}==0 && ($topSlabFlag || $slabOpts=~/s/)) || 
 	          ($slabOpts=~/S/ && $slabdata{$slab}->{lastobj}==$numObjects &&
	   	                     $slabdata{$slab}->{lastslabs}==$numSlabs));

      if ($topSlabFlag)
      {
        last    if ++$slabCount>$numTop;
        $line=sprintf("%7s %7s  %7s  %7s   %7s  %7s %7s  %6.1f  %s",
		cvt($slabdata{$slab}->{slabsize}*$slabdata{$slab}->{avail},6),
		cvt($slabdata{$slab}->{slabsize}*$numObjects,6),
		cvt($slabdata{$slab}->{slabsize},6),
		cvt($numSlabs,6),
		cvt($slabdata{$slab}->{objper},6),
		cvt($slabdata{$slab}->{total},4,0,1),
                cvt($slabdata{$slab}->{memchg},4,0,1),
                $slabdata{$slab}->{mempct}, $first);

        $line.=$eol    if $playback eq '' && $numTop;
        $line.="\n"    if $playback ne '' || !$numTop || $slabCount<$numTop;
        printText($line);
        next;
      }

      printf "$datetime%-25s  %7d  %5d  %7d  %7d  %5d %7d  %8d  %8d  %7s %6.1f\n",
            substr($first,0,25),
	    $slabdata{$slab}->{slabsize},
	    $slabdata{$slab}->{objper},
	    $numObjects,
	    $slabdata{$slab}->{avail},
            ($PageSize<<$slabdata{$slab}->{order})/1024,
	    $numSlabs, 
	    $slabdata{$slab}->{used}/1024, 
	    $slabdata{$slab}->{total}/1024,
            cvt($slabdata{$slab}->{memchg},7,0,1),
            $slabdata{$slab}->{mempct};

      # So we can tell when something changes
      $slabdata{$slab}->{lastobj}=  $numObjects;
      $slabdata{$slab}->{lastslabs}=$numSlabs;
    }
  }
}

sub printTermProc
{
    # if a process is discovered AFTER we start, this routine gets called called the first
    # time a process is seen and '$interval2Secs' will be 0!  In that one special case
    # we need to wait for the next interval before printing.
    return    if !$interval2Secs;

    # if we get here interactively, our cursor has already been set at home, but if
    # --top and -s also specified ($scrollEnd!=0) we need to move past the scroll area
    printf "%c[%d;H", 27, $scrollEnd ? $scrollEnd+1 : 0    if $numTop && $playback eq '';

    # Never report timestamps in --top format.
    my $tempFiller=(!$numTop) ? $miniDateTime : '';
    my $tempTStamp=(!$numTop) ? $datetime : '';

    # Since printHeader() is used by everyone, we need to force header printing for
    # processes when in top mode since we ALWAYS want them
    if (printHeader() || $numTop)
    {
      printText("\n")    if !$homeFlag;
      $temp1=($procOpts=~/f/) ? "(counters are cumulative)" : "(counters are $rate)";

      $temp2='';
      if ($numTop)
      {
        $temp2= " ".(split(/\s+/,localtime($seconds)))[3];
        $temp2.=sprintf(".%03d", $usecs)    if $options=~/m/;
        printText("# TOP PROCESSES sorted by $topType $temp1$temp2\n");
      }
      else
      {
        printText("# PROCESS SUMMARY $temp1$temp2$cpuDisabledMsg\n");
      }

      $tempHdr='';
      if ($procOpts!~/[im]/)
      {
        if ($procOpts!~/R/)
        {
          $prHeader='PR';
	  $prFormat='%2s';
        }
	else
        {
          $prHeader='PRIO';
          $prFormat='%4d';
        }

        $tempHdr.="#${tempFiller} PID  User     $prHeader  PPID THRD S   VSZ   RSS CP  SysT  UsrT Pct  AccuTime ";
	$tempHdr.=sprintf("%s ", $procOpts=~/s/ ? 'StrtTime' : 'StartTime     ')    if $procOpts=~/s/i;
        $tempHdr.=" RKB  WKB "    if $processIOFlag;
	$tempHdr.="VCtx NCtx "    if $procOpts=~/x/;
        $tempHdr.="MajF MinF Command\n";
      }
      elsif ($procOpts=~/i/)
      {
        $tempHdr.="#${tempFiller} PID  User      PPID S  SysT  UsrT Pct  AccuTime   RKB   WKB  RKBC  WKBC  RSys  WSys  Cncl Command\n";
      }
      elsif ($procOpts=~/m/)
      {
        $tempHdr.="#${tempFiller} PID  User     S VmSize  VmLck  VmRSS VmData  VmStk  VmExe  VmLib  VmSwp MajF MinF Command\n";
      }
      printText($tempHdr);
      exit(0)    if $showColFlag;
    }

    # When doing --top, we sort by time, io or faults
    my %procSort;
    my $eol='';
    if ($numTop)
    {
      # clear from current position to the end of line since there could be junk there
      $eol=sprintf("%c[K", 27)    if $playback eq '';
      foreach my $pid (keys %procIndexes)
      {
        # While I could do this at print time, it's more efficient to not even consider the
        # during the sort.
        next    if $procState ne '' && $procState[$procIndexes{$pid}]!~/[$procState]/;

	my $accum=0;
        my $ipid=$procIndexes{$pid};
	if ($topType eq 'vsz') {
          $accum=defined($procVmSize[$ipid]) ? $procVmSize[$ipid] : 0;
	} elsif ($topType eq 'rss') {
	  $accum=defined($procVmRSS[$ipid]) ? $procVmRSS[$ipid] : 0;

	} elsif ($topType eq 'pid') {
  	  $accum=32767-$pid;                 # to sort ascending
	} elsif ($topType eq 'cpu') {
  	  $accum=$NumCpus-$procCPU[$ipid];   # to sort ascending
	} elsif ($topType eq 'syst') {
          $accum=$procUTime[$ipid];
	} elsif ($topType eq 'usrt') {
          $accum=$procUTime[$ipid];
	} elsif ($topType eq 'time') {
  	  $accum=$procSTime[$ipid]+$procUTime[$ipid];
	} elsif ($topType eq 'accum') {
  	  $accum=$procSTimeTot[$ipid]+$procUTimeTot[$ipid];

	} elsif ($topType eq 'thread') {
  	  $accum=$procTCount[$ipid];

	} elsif ($topType eq 'rkb') {
  	  $accum=$procRKB[$ipid];
	} elsif ($topType eq 'wkb') {
  	  $accum=$procWKB[$ipid];
	} elsif ($topType eq 'iokb') {
  	  $accum=$procRKB[$ipid]+$procWKB[$ipid];

        } elsif ($topType eq 'rbkc') {
  	  $accum=$procRKBC[$ipid];
        } elsif ($topType eq 'wkbc') {
  	  $accum=$procWKBC[$ipid];
        } elsif ($topType eq 'iokbc') {
  	  $accum=$procRKBC[$ipid]+$procWKBC[$ipid];

        } elsif ($topType eq 'ioall') {
  	  $accum=$procRKB[$ipid]+ $procWKB[$ipid]+
                 $procRKBC[$ipid]+$procWKBC[$ipid];

        } elsif ($topType eq 'rsys') {
  	  $accum=$procRSys[$ipid];
        } elsif ($topType eq 'wsys') {
  	  $accum=$procWSys[$ipid];
        } elsif ($topType eq 'iosys') {
  	  $accum=$procRSys[$ipid]+$procWSys[$ipid];
        } elsif ($topType eq 'iocncl') {
  	  $accum=$procCKB[$ipid];

   
        } elsif ($topType eq 'vctx') {
  	  $accum=$procVCtx[$ipid];
        } elsif ($topType eq 'nctx') {
  	  $accum=$procNCtx[$ipid];

        } elsif ($topType eq 'minf') {
  	  $accum=$procMinFlt[$ipid];
        } elsif ($topType eq 'flt') {
  	  $accum=$procMajFlt[$ipid]+$procMinFlt[$ipid];
        }
        my $key=sprintf("%09d:%06d", 999999999-$accum, $pid);
        $procSort{$key}=$pid    if $procOpts!~/z/ || $accum!=0;
      }
    }
    # otherwise we print in order of ascending pid
    else
    {
      foreach $pid (keys %procIndexes)
      {
        next    if $procState ne '' && $procState[$procIndexes{$pid}]!~/[$procState]/;

        $procSort{sprintf("%06d", $pid)}=$pid;
      }
    }

    my $procCount=0;
    foreach $key (sort keys %procSort)
    {
      # if we had partial data for this pid don't try to print!
      $i=$procIndexes{$procSort{$key}};
      #print ">>>SKIP PRINTING DATA for pid $key  i: $i"
      #	      if (!defined($procSTimeTot[$i]));
      next   	      if (!defined($procSTimeTot[$i]));

      last    if $numTop && ++$procCount>$numTop;

      # Handle -oF
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

      # If wide mode we include the command arguments AND chop trailing spaces
      ($cmd0, $cmd1)=(defined($procCmd[$i])) ? split(/\s+/,$procCmd[$i],2) : ($procName[$i],'');
      $cmd0=basename($cmd0)    if $procOpts=~/r/ && $cmd0=~/^\//;
      $cmd1=''                 if $procOpts!~/w/ || !defined($cmd1);

      # Since a program CAN modify its definition in /proc/pid/cmdline, it can
      # end up without a trailing null and ultimately the split below results
      # in an undefined $cmd1, which is why we need to test/init it if need be
      if ($procOpts=~/w/)
      {
        $cmd1=~s/\s+$//;
        $cmd1=substr($cmd1, 0, $procCmdWidth);
      }

      # This is the standard format
      if ($procOpts!~/[im]/)
      {
        # Note we only started fetching Tgid in V3.0.0
        $line=sprintf("$tempTStamp%5d%s %-8s $prFormat %5d %4d %1s %5s %5s %2d %s %s %s %s ",
		$procPid[$i],  $procThread[$i] ? '+' : ' ',
		substr($procUser[$i],0,8), $procPri[$i],
                defined($procTgid[$i]) && $procTgid[$i]!=$procPid[$i] ? $procTgid[$i] : $procPpid[$i],
		$procTCount[$i], $procState[$i],
		defined($procVmSize[$i]) ? cvt($procVmSize[$i],4,1,1) : 0, 
		defined($procVmRSS[$i])  ? cvt($procVmRSS[$i],4,1,1)  : 0,
		$procCPU[$i],
		cvtT1($procSTime[$i]), cvtT1($procUTime[$i]), 
		cvtP($procSTime[$i]+$procUTime[$i]),
		cvtT2($procSTimeTot[$i]+$procUTimeTot[$i]));
        $line.=sprintf("%s ", cvtT5($procSTTime[$i]))    if $procOpts=~/s/i;
        $line.=sprintf("%4s %4s ", 
		cvt($procRKB[$i]/$interval2Secs,4,0,1),
		cvt($procWKB[$i]/$interval2Secs,4,0,1))     if $processIOFlag;
        $line.=sprintf("%4s %4s ", 
		cvt($procVCtx[$i]/$interval2Secs,4,0,1),
		cvt($procNCtx[$i]/$interval2Secs,4,0,1))    if $procOpts=~/x/;
        $line.=sprintf("%4s %4s %s %s", 
		cvt($majFlt), cvt($minFlt), $cmd0, $cmd1);
      }
      elsif ($procOpts=~/i/)
      {
        $line=sprintf("%s%5d%s %-8s %5d %1s %s %s %3d %s ",
                $tempTStamp, $procPid[$i], $procThread[$i] ? '+' : ' ',
                substr($procUser[$i],0,8),
                defined($procTgid[$i]) && $procTgid[$i]!=$procPid[$i] ? $procTgid[$i] : $procPpid[$i],
                $procState[$i],
                cvtT1($procSTime[$i]), cvtT1($procUTime[$i]),
		cvtP($procSTime[$i]+$procUTime[$i]),
                cvtT2($procSTimeTot[$i]+$procUTimeTot[$i]));
        $line.=sprintf("%5s %5s %5s %5s %5s %5s %5s %s %s",
                cvt($procRKB[$i]/$interval2Secs,5,0,1),
                cvt($procWKB[$i]/$interval2Secs,5,0,1),
                cvt($procRKBC[$i]/$interval2Secs,5,0,1),
                cvt($procWKBC[$i]/$interval2Secs,5,0,1),
                cvt($procRSys[$i]/$interval2Secs,5,0,1),
                cvt($procWSys[$i]/$interval2Secs,5,0,1),
                cvt($procCKB[$i]/$interval2Secs,5,0,1),
		$cmd0, $cmd1);
      }
      elsif ($procOpts=~/m/)
      {
        $line=sprintf("%s%5d%s %-8s %1s %6s %6s %6s %6s %6s %6s %6s %6s %4s %4s %s %s",
                $tempTStamp, $procPid[$i], $procThread[$i] ? '+' : ' ',
                substr($procUser[$i],0,8), $procState[$i],
                defined($procVmSize[$i]) ? cvt($procVmSize[$i],6,1,1) : 0,
                defined($procVmLck[$i])  ? cvt($procVmLck[$i],6,1,1)  : 0,
                defined($procVmRSS[$i])  ? cvt($procVmRSS[$i],6,1,1)  : 0,
                defined($procVmData[$i]) ? cvt($procVmData[$i],6,1,1) : 0,
                defined($procVmStk[$i])  ? cvt($procVmStk[$i],6,1,1)  : 0,
                defined($procVmExe[$i])  ? cvt($procVmExe[$i],6,1,1)  : 0,
                defined($procVmLib[$i])  ? cvt($procVmLib[$i],6,1,1)  : 0,
                defined($procVmSwap[$i]) ? cvt($procVmSwap[$i],6,1,1)  : 0,
		cvt($majFlt), cvt($minFlt), $cmd0, $cmd1);
      }
      $line.=$eol    if $playback eq '' && $numTop;
      $line.="\n"    if $playback ne '' || !$numTop || $procCount<$numTop;
      printText($line);
    }

    # clear to the end of the display in case doing --procopts z, since the process list
    # length changes dynamically
    print $clr    if $numTop && $playback eq '';
}

# this routine detects and 'fixes' counters that have wrapped
# *** warning ***  It appears that partition 'use' counters wrap at wordsize/100 
# on an ia32 (these are pretty pesky to actually catch).  There may be more and 
# they may behave differently on different architectures (though I tend to doubt 
# it) so the best we can do is deal with them when we see them.  It also looks like
#  elan counters are divided by 1MB before reporting so we have to deal with them too
sub fix
{
  my $counter=shift;

  # if we're a smaller architecture than the number itself, we should still be
  # ok because perl isn't restricted by word size.
  if ($counter<0)
  {
    my $divisor=shift;
    my $maxSize=shift;

    # if param3 exists (rare), we use this as the max counter size;  otherwidse 32 bit
    my $wordsize=defined($maxSize) ? $maxSize : $word32;

    # only adjust divisor when we're told to do so in param2.
    my $add=defined($divisor) ? $wordsize/$divisor : $wordsize;
    $counter+=$add;
  }
  return($counter);
}

# unitCounter  0 -> none, 1 -> K, etc (divide by $divisor this # times)
# divisor 0 -> /1000  1 -> /1024
sub cvt
{
  my $field=shift;
  my $width=shift;
  my $unitCounter=shift;
  my $divisorType=shift;

  $width=4                 if !defined($width);
  $unitCounter=0           if !defined($unitCounter);
  $divisorType=0           if !defined($divisorType);
  $negative=0              if !defined($negative);
  $field=int($field+.5)    if $field>0;    # round up in case <1


  # This is tricky, because if the value fits within the width, we
  # must also be sure the unit counter is 0 otherwise both may not
  # fit.  Naturally in 'wide' mode we aways report the complete value
  # and we never print units with values of 0.
  return($field)    if ($field==0) || ($unitCounter<1 && length($field)<=$width) || $wideFlag;

  # At least with slabs you can get negative numbers since we're tracking changes
  my $sign=($field<0) ? -1 : 1;
  $field=abs($field);

  my $last=0;
  my $divisor=($divisorType==0) ? 1000 : $OneKB;
  while (length($field)>=$width)
  {
    $last=$field;
    $field=int($field/$divisor);
    $unitCounter++;
  }
  $field*=$sign;

  my $units=substr(" KMGTP", $unitCounter, 1);
  my $result=(abs($field)>0) ? "$field$units" : "1$units";

  # Messy, but I hope reasonable efficient.  We're only applying this to
  # fields >= 'G' and options g/G!  Furthermore, for -oG we only reformat 
  # when single digit because no room for 2.
  if ($units=~/[GTP]/ && $options=~/g/i && (length($field))!=3)
  {
    # This one's a mouthful...  we need to figure out what the remainer of the 
    # previous division was, by subtracting the field*divisor.  Then we need
    # to round up and pad with leading 0s.  Note cases where we've rounded
    # something like 9.999 which really needs to become 10.000
    my $round=($options=~/g/) ? 5 : 50;
    my $fraction=sprintf("%03d", $last-$field*$divisor+$round);
    if ($fraction>=$divisor)
    {	
      $field++;
      $fraction='000';
    }

    # For 'G' we almost always print the first form but if we just rounded from 9.9 to
    # to 10, we no longer have room for the fraction
    if ($options=~/G/)
    {
      $result=(length($field)==1) ? "$field.".substr($fraction, 0, 1).'G' : "$field$units";
    }
    elsif ($options=~/g/)
    {
      # since the fraction follows the 'g', just chop the thing to 4 chars
      $result=substr("${field}g".$fraction, 0, 4);
    }
  }
  return($result);
}

# Time Format1 - convert time in jiffies to something ps-esque
# Seconds.hsec only (not suitable for longer times such as accumulated cpu)
sub cvtT1
{
  my $jiffies=shift;
  my $nsFlag= shift;
  my ($secs, $hsec);

  # set formatting for minutes according to 'no space' flag
  $MF=(!$nsFlag) ? '%2d' : '%d';

  $secs=int($jiffies/$HZ);
  $jiffies=$jiffies-$secs*$HZ;
  $hsec=$jiffies/$HZ*100;
  return(sprintf("$MF.%02d", $secs, $hsec));
}

# Time Format1 - convert time in jiffies to something ps-esque
# we're not doing hours to save a couple of columns
sub cvtT2
{
  my $jiffies=shift;
  my $nsFlag= shift;
  my ($hour, $mins, $secs, $time, $hsec);

  $secs=int($jiffies/$HZ);
  $jiffies=$jiffies-$secs*$HZ;
  $hsec=$jiffies/$HZ*100;

  $mins=int($secs/60);
  $secs=$secs-$mins*60;
  $time=($mins<60) ? sprintf("%02d:%02d.%02d", $mins % 60, $secs, $hsec) : 
		    sprintf("%02d:%02d:%02d", int($mins/60), $mins % 60, $secs);
  $time=" $time"    if !$nsFlag && length($time)==8;    # usually 8, but room for 3 digit mins
  return($time);
}

sub cvtT3
{
  my $secs=shift;

  $secs/=100;    # $secs really is msec
  my $hours=int($secs/3600);
  my $mins= int(($secs-$hours*3600)/60);
  return(sprintf("%d:%02d:%02d", $hours, $mins, $secs-$hours*3600-$mins*60));
}

# convert time in seconds to date/time
sub cvtT4
{
  my $seconds=shift;

  my $msec=($options=~/m/) ? sprintf(".%s", (split(/\./, $seconds))[1]) : '';
  my ($ss, $mm, $hh, $mday, $mon, $year)=localtime($seconds);
  my $date=($options=~/d/) ?
         sprintf("%02d/%02d", $mon+1, $mday) :
         sprintf("%d%02d%02d", $year+1900, $mon+1, $mday);
  my $time= sprintf("%02d:%02d:%02d%s", $hh, $mm, $ss, $msec);
  return($date, $time);
}

sub cvtT5
{
  my $time=shift;

  my $realTime=$boottime+$time/100;    # time in jiffies
  my ($ss, $mm, $hh, $day, $mon)=localtime($realTime);

  my $timestr;
  if ($procOpts=~/s/)
  {
    $timestr=sprintf("%02d:%02d:%02d", $hh, $mm, $ss);
  }
  else
  {
    my $month=substr("JanFebMarAprMayJunJulAugSepOctNovDec", $mon*3, 3);
    $timestr=sprintf("%s%02d-%02d:%02d:%02d", $month, $day, $hh, $mm, $ss);
  }

  return($timestr);
}

sub cvtP
{
  my $jiffies=shift;
  my ($secs, $percent);

  # when using --from, we sometimes have not set $interval2SecsReal for the
  # first sample so use i2 which is a good approximation
  $secs=$jiffies/$HZ;
  $interval2SecsReal=$interval2    if $interval2SecsReal==0;
  $percent=sprintf("%3d", 100*$secs/$interval2SecsReal);
  return($percent);
}

# Like printInterval, this is also used for terminal/socket output and therefore
# not something we need to worry about for logging!
sub printText
{ 
  my $text=shift;
  my $eol= shift;

  print $text    if !$sockFlag;

  # just like in writeData, we need to make sure each line preceed
  # with host name if not in server mode BUT only if not shutting down.
  if ($sockFlag && scalar(@sockets) && !$doneFlag)
  {
    $text=~s/^(.*)$/$Host $1/mg    if !$serverFlag;

    $text.=">>><<<\n"    if defined($eol);
    foreach my $socket (@sockets)
    {
      my $length=length($text);
      for (my $offset=0; $offset<$length;)
      {
        # When in client mode this WILL generate an error when the process who
        # started us terminates.
        my $bytes=syswrite($socket, $text, $length, $offset);
        if (!defined($bytes))
        {
          logmsg('E', "Error '$!' writing to socket")    if $serverFlag;
          last;
        }
        $offset+=$bytes;
        $length-=$bytes;
      }
    }
  }
}

# see if time to print header
sub printHeader
{
  # It might also be time to print a separator
  printSeparator($seconds, $usecs)    if !$separatorHeaderPrinted;
  $separatorHeaderPrinted=1;

  #    S p e c i a l    C a s e s

  # Unless we say so explicitly we won't print a header and since we never do so under the
  # following specific case of --top, let's get it out of the way first.
  return(0)    if $numTop && $headerRepeat==0 && $sameColsFlag;

  return(1)    if $subsys=~/[YZ]/ && $procFilt eq '' && $slabFilt eq '' && $slabOpts!~/S/;
  return(1)    if $numTop && $playback eq '';
  return(1)    if $headerRepeat==1;   # brute force!

  #    S t a n d a r d    P r o c e s s i n g

  # The most common is when different column names and we simply do a new header every
  # interval or when using --home to look top-ish output.  Not sure why $totalCounter...
  return(1)    if $headerRepeat>-1 && (!$sameColsFlag || $totalCounter==1 || $homeFlag);

  # Note that in detail mode (and that includes processes/slabs with filters) there's no
  # real easy way to tell when to redo the header so rather we'll just repeat them every
  # --hr set of intervals rather than lines.
  return(1)    if ($headerRepeat>0 &&
                     ( ($interval1Counter % $headerRepeat)==1 ||
                       (($interval2Counter % $headerRepeat)==1 && $interval2Print) ||
                       (($interval3Counter % $headerRepeat)==1 && $interval3Print)) );

  # do NOT print a header...
  return(0);
}

# This routine gets called when it MIGHT be time to print a record separator since we've
# not printed one yet and are printing data for a new intercal.
sub printSeparator
{
  my $seconds=shift;
  my $usecs=  shift;

  # here's where we decide whether or not we really want the interval headers.  This is also
  # where all the special cases come in.
  return    if !$numTop && $sameColsFlag && $subsys!~/[YZ]/ && !$homeFlag;
  return    if  $numTop && $playback eq '' && !$detailFlag;
  return    if $subsys eq 'Y' && ($slabFilt ne '' || $slabOpts=~/S/);
  return    if $subsys eq 'Z' && $procFilt ne '';

  my $date=localtime($seconds);
  if ($options=~/m/)
  {
    my ($dow, $mon, $day, $time, $year)=split(/ /, $date);
    $date="$dow $mon $day $time.$usecs $year";
  }

  # Remember that -A with logging never writes to terminals.
  my $temp=sprintf("%s", $homeFlag ? $clscr : "\n");
  $temp.=sprintf("### RECORD %4d >>> $HostLC <<< ($seconds) ($date) ###\n", ++$separatorCounter);
  printText($temp);
}

sub getHeader
{
  my $file=shift;
  my ($gzFlag, $header, $TEMP, $line);

  $gzFlag=$file=~/gz$/ ? 1 : 0;
  if ($gzFlag)
  {
    $TEMP=Compress::Zlib::gzopen($file, "rb") or logmsg("F", "Couldn't open '$file'");
  }
  else
  {
    open TEMP, "<$file" or logmsg("F", "Couldn't open '$file'");
  }

  $header="";
  while (1)
  {
    $TEMP->gzreadline($line)    if  $gzFlag;
    $line=<TEMP>                if !$gzFlag;

    last    if $line!~/^#/;
    $header.=$line;
  }
  close TEMP;
  print "*** Header For: $file ***\n$header"    if $debug & 16;
  return($header);
}

sub incomplete
{
  my $type=shift;
  my $secs=shift;
  my $special=shift;
  my ($seconds, $ss, $mm, $hh, $mday, $mon, $year, $date, $time);

  $seconds=(split(/\./, $secs))[0];
  ($ss, $mm, $hh, $mday, $mon, $year)=localtime($seconds);
  $date=sprintf("%d%02d%02d", $year+1900, $mon+1, $mday);
  $time=sprintf("%02d:%02d:%02d", $hh, $mm, $ss);

  my $message=(!defined($special)) ? "Incomplete" : $special;
  my $where=($playback eq '') ? "on $date" : "in $playbackFile";
  logmsg("W", "$message data record skipped for $type data $where at $time");
}

# Handy for debugging
sub getTime
{
  my $seconds=shift;
  my ($ss, $mm, $hh, $mday, $mon, $year);
  ($ss, $mm, $hh, $mday, $mon, $year)=localtime($seconds);
  return(sprintf("%02d:%02d:%02d", $hh, $mm, $ss));
}

########################################
#      Brief Mode is VERY Special
########################################

sub printBrief
{
  my ($command, $pad, $i);
  my $line='';

  # We want to track elapsed time.  This is only looked at in interactive mode.
  $miniStart=$seconds    if !defined($miniStart) || $miniStart==0;

  if ( $headerRepeat==1 ||
      ($headerRepeat==0 && !$headersPrinted) ||
      ($headerRepeat>0 && ($totalCounter % $headerRepeat)==1))
  {
    $cpuDisabledMsg=~s/^://;    # just in case non-null
    $pad=' ' x length($miniDateTime);
    $fill1=($Hyper eq '') ? "----" : "";
    $fill2=($Hyper eq '') ? "----" : "-";
    $line.="$clscr";
    $line.="#$cpuDisabledMsg\n"    if $cpuDisabledMsg ne '';
    $line.="#$pad";
    $line.="<----${fill1}CPU$Hyper$fill2---->"     if $subsys=~/c/;
    if ($subsys=~/j/)
    {
      my $num=int(($NumCpus-1)*5/2);
      my $pad1='-'x$num;
      my $pad2=$pad1;
      $line.="<${pad1}Int$pad2->";
    }

    # sooo ugly...
    my ($tcp1,$tcp2);
    if ($subsys=~/t/)
    {
      $tcp2='';
      $tcp2.='  IP '     if $tcpFilt=~/i/;
      $tcp2.=' Tcp '     if $tcpFilt=~/t/;
      $tcp2.=' Udp '     if $tcpFilt=~/u/;
      $tcp2.='Icmp '     if $tcpFilt=~/c/;
      $tcp2.='TcpX '     if $tcpFilt=~/T/;

      my $num=int((length($tcp2)-5)/2);
      my $num2=((length($tcp2) % 2)==0) ? $num+1 : $num;
      my $pre= '-' x $num;
      my $post='-' x $num2;
      $tcp1="<${pre}TCP$post>";
      $tcp1="<ERR>"    if length($tcp2)==5;
    }

    $line.="<--Memory-->"                                 if $subsys!~/m/ && $subsys=~/b/;
    if ($memOpts!~/R/)
    {
      $line.="<-----------Memory----------->"              if $subsys=~/m/ && $subsys!~/b/;
      $line.="<-----------------Memory----------------->"  if $subsys=~/m/ && $subsys=~/b/;
    }
    else
    {
      $line.="<--------------Memory-------------->"              if $subsys=~/m/ && $subsys!~/b/;
      $line.="<--------------------Memory-------------------->"  if $subsys=~/m/ && $subsys=~/b/;
    }

    $line.="<-----slab---->"                           if $subsys=~/y/;
    $line.="<----------Disks----------->"              if $subsys=~/d/ && !$ioSizeFlag && $dskOpts!~/i/;
    $line.="<---------------Disks---------------->"    if $subsys=~/d/ && ($ioSizeFlag || $dskOpts=~/i/);
    $line.="<----------Network---------->"             if $subsys=~/n/ && !$ioSizeFlag && $netOpts!~/i/;
    $line.="<---------------Network--------------->"   if $subsys=~/n/ && ($ioSizeFlag || $netOpts=~/i/);
    $line.=$tcp1                                       if $subsys=~/t/;
    $line.="<------Sockets----->"                      if $subsys=~/s/;
    $line.="<----Files--->"                            if $subsys=~/i/;
    $line.="<---------------Elan------------->"        if $subsys=~/x/ && $NumXRails;
    $line.="<-----------InfiniBand----------->"        if $subsys=~/x/ && ($NumHCAs || $NumHCAs+$NumXRails==0) && (!$ioSizeFlag && $xOpts!~/i/);
    $line.="<----------------InfiniBand---------------->" if $subsys=~/x/ && ($NumHCAs || $NumHCAs+$NumXRails==0) && ($ioSizeFlag || $xOpts=~/i/);

    # probably a better way to handle iosize too
    $line=~s/Network/---Network---/    if $netOpts=~/e/;

    # a bunch of extra work but worth it!
    if ($subsys=~/f/)
    {
      # If all filters specified, no room!
      if ($nfsFilt eq '' || length($nfsFilt)==17)
      {
        $line.="<------NFS Totals------>";
      }
      else
      {
	my $padL=$padR=int((14-length($nfsFilt))/2);
        $padL++    if length($nfsFilt) & 1;   # handle odd number of -'s
        $padL='-'x$padL;
        $padR='-'x$padR;
        $line.="<$padL-NFS [$nfsFilt]-$padR>";
      }
    }

    $line.="<--------Lustre MDS-------->"              if $subsys=~/l/ && $reportMdsFlag;
    $line.="<---------Lustre OST--------->"            if $subsys=~/l/ && $reportOstFlag && !$ioSizeFlag;
    $line.="<--------------Lustre OST-------------->"  if $subsys=~/l/ && $reportOstFlag &&  $ioSizeFlag;
 
    if ($subsys=~/l/ && $reportCltFlag)
    {
      $line.="<--------Lustre Client-------->"                 if !$ioSizeFlag && $lustOpts!~/R/;
      $line.="<---------------Lustre Client--------------->"   if !$ioSizeFlag && $lustOpts=~/R/;
      $line.="<-------------Lustre Client------------->"                 if  $ioSizeFlag && $lustOpts!~/R/;
      $line.="<--------------------Lustre Client-------------------->"   if  $ioSizeFlag && $lustOpts=~/R/;
    }
    for (my $i=0; $i<$impNumMods; $i++) { &{$impPrintBrief[$i]}(1, \$line); }
    $line.="\n";

    $line.="#$miniDateTime";
    $line.="cpu sys inter  ctxsw "                 if $subsys=~/c/;

    if ($subsys=~/j/)
    {
      # If < 10 cpus, use header of 'Cpu'.  otherwiswe use 'Cp', 'C' or just the number.
      # Naturally if more than a couple of dozen we'll need a very wide monitor.
      $line.=sprintf("Cpu%d "x($NumCpus>10?10:$NumCpus),        0..$NumCpus);
      $line.=sprintf("Cp%d "x($NumCpus>100?90:$NumCpus-10),    10..$NumCpus);
      $line.=sprintf("C%d "x($NumCpus>1000?900:$NumCpus-100), 100..$NumCpus);
      $line.=sprintf("%d "x($NumCpus-1000),                  1000..$NumCpus);

      # Rare, but if a cpu is offline, change its name in the header
      if ($cpusDisabled)
      {
	for (my $i=0; $i<$NumCpus; $i++)
        {
	  $line=~s/Cpu$i/CpuX/    if !$cpuEnabled[$i];
	  $line=~s/Cp$i/CpXX/     if !$cpuEnabled[$i] && length($i)==2;
	  $line=~s/C$i/CXXX/      if !$cpuEnabled[$i] && length($i)==3;
	  $line=~s/$i/XXXX/       if !$cpuEnabled[$i] && length($i)==4;
        }
      }
    }

    if ($memOpts!~/R/)
    {
      $line.="Free Buff Cach Inac Slab  Map "          if $subsys=~/m/;
    }
    else
    {
      $line.=" Free  Buff  Cach  Inac  Slab   Map "    if $subsys=~/m/;
    }
    $line.="  Fragments "                            if $subsys=~/b/;

    $line.=" Alloc   Bytes "	 		     if $subsys=~/y/ && $slabinfoFlag;
    $line.=" InUse   Total "	 		     if $subsys=~/y/ && $slubinfoFlag;
    $line.="KBRead  Reads KBWrit Writes "            if $subsys=~/d/ && !$ioSizeFlag && $dskOpts!~/i/;
    $line.="KBRead  Reads Size KBWrit Writes Size "  if $subsys=~/d/ && ($ioSizeFlag || $dskOpts=~/i/);
    $line.="  KBIn  PktIn  KBOut  PktOut "           if $subsys=~/n/ && !$ioSizeFlag && $netOpts!~/i/;
    $line.="  KBIn  PktIn Size  KBOut  PktOut Size " if $subsys=~/n/ && ($ioSizeFlag || $netOpts=~/i/);
    $line.="Error "                                  if $netOpts=~/e/;
    $line.=$tcp2                                     if $subsys=~/t/;
    $line.=" Tcp  Udp  Raw Frag "                    if $subsys=~/s/;
    $line.="Handle Inodes "                          if $subsys=~/i/;
    $line.="   KBIn  PktIn   KBOut PktOut Errs "     if $subsys=~/x/ && $NumXRails;
    $line.="   KBIn  PktIn   KBOut PktOut Errs "     if $subsys=~/x/ && ($NumHCAs || $NumHCAs+$NumXRails==0) && (!$ioSizeFlag && $xOpts!~/i/);
    $line.="   KBIn  PktIn Size   KBOut PktOut Size Errs " if $subsys=~/x/ && ($NumHCAs || $NumHCAs+$NumXRails==0) && ($ioSizeFlag || $xOpts=~/i/);
    $line.=" Reads Writes Meta Comm "                 if $subsys=~/f/;

    if ($subsys=~/l/ && $reportMdsFlag) 
    {
      $line.="Gattr+ Sattr+   Sync  ";
      $line.=($cfsVersion lt '1.6.5') ? 'Reint ' : 'Unlnk ';
    }

    $line.=" KBRead  Reads  KBWrit Writes "           if $subsys=~/l/ && $reportOstFlag && !$ioSizeFlag;
    $line.=" KBRead  Reads Size  KBWrit Writes Size " if $subsys=~/l/ && $reportOstFlag &&  $ioSizeFlag;

    if ($subsys=~/l/ && $reportCltFlag)
    {
      $line.=" KBRead  Reads  KBWrite Writes"              if !$ioSizeFlag;
      $line.=" KBRead  Reads Size  KBWrite Writes Size"    if $ioSizeFlag;
      $line.="   Hits Misses"                              if $lustOpts=~/R/;
    }

    for (my $i=0; $i<$impNumMods; $i++) { &{$impPrintBrief[$i]}(2, \$line); }
    $line.="\n";
    $headersPrinted=1;

    if ($showColFlag)
    { printText($line); exit(0); }
  }
  goto statsSummary    if $statsFlag && $statOpts!~/i/i;

  # leading space not needed for date/time
  $line.=sprintf(' ')    if !$miniDateFlag && !$miniTimeFlag;

  # First part always the same...
  $line.=sprintf("%s ", $datetime)    if $miniDateFlag || $miniTimeFlag;

  my $preambleLength=length($line);    # save for later...

  if ($subsys=~/c/)
  {
    $i=$NumCpus;
    $sysTot=$sysP[$i]+$irqP[$i]+$softP[$i]+$stealP[$i];
    $cpuTot=$userP[$i]+$niceP[$i]+$sysTot;
    $line.=sprintf("%3d %3d %5s %6s ",
        $cpuTot, $sysTot, cvt($intrpt/$intSecs,5), cvt($ctxt/$intSecs,6));
  }

  if ($subsys=~/j/)
  {
    for (my $i=0; $i<$NumCpus; $i++)
    {
      $line.=sprintf("%4s ", cvt($intrptTot[$i]/$intSecs,4,0,0));
    }
  }

  if ($subsys=~/m/)
  {
    if ($memOpts!~/R/)
    {
      $line.=sprintf("%4s %4s %4s %4s %4s %4s ",
          cvt($memFree,4,1,1),   cvt($memBuf,4,1,1), 
	  cvt($memCached,4,1,1), cvt($memInact,4,1,1),
	  cvt($memSlab,4,1,1),   cvt($memMap+$memAnon,4,1,1));
    }
    else
    {
      $line.=sprintf("%5s %5s %5s %5s %5s %5s ",
          cvt($memFreeC/$intSecs,4,1,1),   cvt($memBufC/$intSecs,4,1,1),
          cvt($memCachedC/$intSecs,4,1,1), cvt($memInactC/$intSecs,4,1,1),
          cvt($memSlabC/$intSecs,4,1,1),   cvt($memMapC+$memAnonC/$intSecs,4,1,1));
    }
  }

  if ($subsys=~/b/)
  {
    $line.=sprintf("%s ", base36(@buddyInfoTot));
  }

  if ($subsys=~/y/)
  {
    if ($slabinfoFlag)
    {
      $line.=sprintf("%6s %7s ",
	cvt($slabSlabAllTotal,6), cvt($slabSlabAllTotalB,7,0,1));
    }
    else
    {
      $line.=sprintf("%6s %7s ",
	cvt($slabNumObjTot,7),  cvt($slabTotalTot,7,0,1));
    }
  }

  if ($subsys=~/d/)
  {
    if (!$ioSizeFlag && $dskOpts!~/i/)
    {
      $line.=sprintf("%6s %6s %6s %6s ",
          cvt($dskReadKBTot/$intSecs,6,0,1),  cvt($dskReadTot/$intSecs,6),
          cvt($dskWriteKBTot/$intSecs,6,0,1), cvt($dskWriteTot/$intSecs,6));
    }
    else
    {
      $dskReadSizeTot= ($dskReadTot)  ? $dskReadKBTot/$dskReadTot : 0; 
      $dskWriteSizeTot=($dskWriteTot) ? $dskWriteKBTot/$dskWriteTot : 0; 
      $line.=sprintf("%6s %6s %4s %6s %6s %4s ",
          cvt($dskReadKBTot/$intSecs,6,0,1),  cvt($dskReadTot/$intSecs,6),  cvt($dskReadSizeTot, 4),
          cvt($dskWriteKBTot/$intSecs,6,0,1), cvt($dskWriteTot/$intSecs,6), cvt($dskWriteSizeTot, 4));
    }
  }

  # Network always the same
  my $netErrors=$netRxErrsTot+$netTxErrsTot;
  if ($subsys=~/n/)
  {
    if (!$ioSizeFlag && $netOpts!~/i/)
    {
      $line.=sprintf("%6s %6s %6s  %6s ",
          cvt($netRxKBTot/$intSecs,6,0,1), cvt($netRxPktTot/$intSecs,6),
          cvt($netTxKBTot/$intSecs,6,0,1), cvt($netTxPktTot/$intSecs,6));
    }
    else
    {
      $netRxSizeTot=($netRxPktTot) ? $netRxKBTot*1024/$netRxPktTot : 0;
      $netTxSizeTot=($netTxPktTot) ? $netTxKBTot*1024/$netTxPktTot : 0;
      $line.=sprintf("%6s %6s %4s %6s  %6s %4s ",
          cvt($netRxKBTot/$intSecs,6,0,1), cvt($netRxPktTot/$intSecs,6), cvt($netRxSizeTot,4,0,1),
          cvt($netTxKBTot/$intSecs,6,0,1), cvt($netTxPktTot/$intSecs,6), cvt($netTxSizeTot,4,0,1));
    }

    # if --netops E and no errors, don't print ANYTHING!!!
    $line.=sprintf("%5s ", cvt($netErrors/$intSecs,5))    if $netOpts=~/e/;
  }

  # TCP Stack
  if ($subsys=~/t/)
  {
    $line.=sprintf("%4s ", cvt($ipErrors, 4))       if $tcpFilt=~/i/; 
    $line.=sprintf("%4s ", cvt($tcpErrors, 4))      if $tcpFilt=~/t/;
    $line.=sprintf("%4s ", cvt($udpErrors, 4))      if $tcpFilt=~/u/;
    $line.=sprintf("%4s ", cvt($icmpErrors, 4))     if $tcpFilt=~/c/;
    $line.=sprintf("%4s ", cvt($tcpExErrors,4))     if $tcpFilt=~/T/;
  }

  if ($subsys=~/s/)
  {
    $line.=sprintf("%4s %4s %4s %4s ", 
	cvt($sockUsed,4), cvt($sockUdp,4), cvt($sockRaw,4), cvt($sockFrag,4));
  }

  if ($subsys=~/i/)
  {
    $line.=sprintf("%6s %6s ", cvt($filesAlloc, 6), cvt($inodeUsed, 6));
  }

  # and so is elan
  if ($subsys=~/x/)
  {
    if ($NumXRails)
    {
      $elanErrors=$elanSendFailTot+$elanNeterrAtomicTot+$elanNeterrDmaTot;
      $line.=sprintf("%7s %6s %7s %6s %4s ",
          cvt($elanRxKBTot/$intSecs,7,0,1), cvt($elanRxTot/$intSecs,6),
          cvt($elanTxKBTot/$intSecs,7,0,1), cvt($elanTxTot/$intSecs,6),
	  cvt($elanErrors/$intSecs,4));
    }
    if ($NumHCAs || $NumXRails+$NumHCAs==0)
    {
      if (!$ioSizeFlag && $xOpts!~/i/)
      {
        $line.=sprintf("%7s %6s %7s %6s %4s ",
            cvt($ibRxKBTot/$intSecs,7,0,1), cvt($ibRxTot/$intSecs,6),
            cvt($ibTxKBTot/$intSecs,7,0,1), cvt($ibTxTot/$intSecs,6),
	    cvt($ibErrorsTotTot,4));
      }
      else
      {
        $line.=sprintf("%7s %6s %4s %7s %6s %4s %4s ",
            cvt($ibRxKBTot/$intSecs,7,0,1), cvt($ibRxTot/$intSecs,6),
	    $ibRxTot ? cvt($ibRxKBTot*1024/$ibRxTot,4,0,1) : 0,
            cvt($ibTxKBTot/$intSecs,7,0,1), cvt($ibTxTot/$intSecs,6),
            $ibTxTot ? cvt($ibTxKBTot*1024/$ibTxTot,4,0,1) : 0,
            cvt($ibErrorsTotTot,4));
      }
    }
  }

  if ($subsys=~/f/)
  {
    $line.=sprintf("%6s %6s %4s %4s ", 
	cvt($nfsReadsTot/$intSecs,6), cvt($nfsWritesTot/$intSecs,6),
	cvt($nfsMetaTot/$intSecs),  cvt($nfsCommitTot/$intSecs));
  }

  # MDS
  if ($subsys=~/l/ && $reportMdsFlag)
  {
    my $setattrPlus=$lustreMdsReintSetattr+$lustreMdsSetxattr;
    my $getattrPlus=$lustreMdsGetattr+$lustreMdsGetattrLock+$lustreMdsGetxattr;
    my $variableParam=($cfsVersion lt '1.6.5') ? $lustreMdsReint : $lustreMdsReintUnlink;
    $line.=sprintf("%6s %6s %6s %6s ",
        cvt($getattrPlus/$intSecs,6),   cvt($setattrPlus/$intSecs,6),
        cvt($lustreMdsSync/$intSecs,6), cvt($variableParam/$intSecs,6));
  }

  # OST
  if ($subsys=~/l/ && $reportOstFlag)
  {
    if (!$ioSizeFlag)
    {
      $line.=sprintf("%7s %6s %7s %6s ",
          cvt($lustreReadKBytesTot/$intSecs,7,0,1),  cvt($lustreReadOpsTot/$intSecs,6),
          cvt($lustreWriteKBytesTot/$intSecs,7,0,1), cvt($lustreWriteOpsTot/$intSecs,6));
    }
    else
    {
      $line.=sprintf("%7s %6s %4s %7s %6s %4s ",
          cvt($lustreReadKBytesTot/$intSecs,7,0,1),  cvt($lustreReadOpsTot/$intSecs,6),
          $lustreReadOpsTot ? cvt($lustreReadKBytesTot/$lustreReadOpsTot,4,0,1) : 0,
          cvt($lustreWriteKBytesTot/$intSecs,7,0,1), cvt($lustreWriteOpsTot/$intSecs,6),
          $lustreWriteOpsTot ? cvt($lustreWriteKBytesTot/$lustreWriteOpsTot,4,0,1) : 0);
    }
  }

  #Lustre Client
  if ($subsys=~/l/ && $reportCltFlag)
  {
    if (!$ioSizeFlag)
    {
      $line.=sprintf("%7s %6s  %7s %6s", 
	  cvt($lustreCltReadKBTot/$intSecs,7,0,1),  cvt($lustreCltReadTot/$intSecs),
          cvt($lustreCltWriteKBTot/$intSecs,7,0,1), cvt($lustreCltWriteTot/$intSecs,6));
    }
    else
    {
      $line.=sprintf("%7s %6s %4s  %7s %6s %4s",
          cvt($lustreCltReadKBTot/$intSecs,7,0,1),  cvt($lustreCltReadTot/$intSecs),
	  $lustreCltReadTot ? cvt($lustreCltReadKBTot/$lustreCltReadTot,4,0,1) : 0,
          cvt($lustreCltWriteKBTot/$intSecs,7,0,1), cvt($lustreCltWriteTot/$intSecs,6),
          $lustreCltWriteTot ? cvt($lustreCltWriteKBTot/$lustreCltWriteTot,4,0,1) : 0);
    }

    # Add in cache hits/misses if --lustopts R
    $line.=sprintf(" %6d %6d", $lustreCltRAHitsTot, $lustreCltRAMissesTot)    if $lustOpts=~/R/;
  }

  for (my $i=0; $i<$impNumMods; $i++) { &{$impPrintBrief[$i]}(3, \$line); }
  $line.="\n";

  #   S p e c i a l    ' h o t '    K e y    P r o c e s s i n g

  # First time through when an attached terminal
  if ($termFlag && !defined($mini1select))
  {
    $mini1select=new IO::Select(STDIN);
    resetBriefCounters();
    `stty -echo`    if !$PcFlag && !$backFlag && $termFlag && $playback eq '';
  }

  # See if user entered a command.  If not, @ready will never be
  # non-zero so the 'if' below will never fire.  Also, if we haven't
  # done one interval, ignore becuase $miniInstances will be 0
  @ready=$mini1select->can_read(0)    if $termFlag;
  if (scalar(@ready))
  {
    $command=<STDIN>;
    if ($miniInstances)
    {
      $resetType='T';
      $resetType=$command    if $command=~/a|t|z/i;
      printBriefCounters($resetType);
      resetBriefCounters()    if $resetType=~/Z/i;
    }
  }

# come here from collectl's ONLY goto statement!
statsSummary:

  # Minor subtlety - we want to print the totals as soon as the hot-key
  # is entered and so we print the sub-total so far which DOESN'T
  # include this latest line!  Then we count the data.
  countBriefCounters();
  $miniInstances++;

  # The only time we don't print the line is if it doesn't contain any data, wich can only happen
  # when data was imported at a different interval and played back with -s-all, OR we're only 
  # doing network error reporting and this interval is clean.  In that cast reset '$totalCounter'
  # so header printing works correctly.
  $empty=0;
  $empty=1            if ($import ne '' && $subsys eq '' && (substr($line, $preambleLength) eq "\n"));
  printText($line)    if !$empty && ($netOpts!~/E/ || $netErrors);
  $totalCounter--     if $netOpts=~/E/ && !$netErrors
}

sub resetBriefCounters
{
  # talk about a mouthful!
  $miniStart=0;
  $miniInstances=0;
  $cpuTOT=$sysPTOT=$intrptTOT=$ctxtTOT=0;
  $memFreeTOT=$memBufTOT=$memCachedTOT=$memInactTOT=$memSlabTOT=$memMapTOT=0;
  $memFreeCTOT=$memBufCTOT=$memCachedCTOT=$memInactCTOT=$memSlabCTOT=$memMapCTOT=0;
  $slabSlabAllTotalTOT=$slabSlabAllTotalBTOT=0;
  $dskReadKBTOT=$dskReadTOT=$dskWriteKBTOT=$dskWriteTOT=0;
  $netRxKBTOT=$netRxPktTOT=$netTxKBTOT=$netTxPktTOT=$netErrTOT=0;
  $tcpIpErrTOT=$tcpIcmpErrTOT=$tcpTcpErrTOT=$tcpUdpErrTOT=$tcpTcpExErrTOT=0;
  $sockUsedTOT=$sockUdpTOT=$sockRawTOT=$sockFragTOT=0;
  $filesAllocTOT=$inodeUsedTOT=0;
  $elanRxKBTOT=$elanRxTOT=$elanTxKBTOT=$elanTxTOT=$elanErrorsTOT=0;
  $ibRxKBTOT=$ibRxTOT=$ibTxKBTOT=$ibTxTOT=$ibErrorsTOT=0;
  $nfsReadsTOT=$nfsWritesTOT=$nfsMetaTOT=$nfsCommitTOT=0;
  $lustreMdsGetattrPlusTOT=$lustreMdsSetattrPlusTOT=$lustreMdsSyncTOT=0;
  $lustreMdsReintTOT=$lustreMdsReintUnlinkTOT=0;
  $lustreReadKBytesTOT=$lustreReadOpsTOT=$lustreWriteKBytesTOT=$lustreWriteOpsTOT=0;
  $lustreCltReadTOT=$lustreCltReadKBTOT=$lustreCltWriteTOT=$lustreCltWriteKBTOT=0;
  $lustreCltRAHitsTOT=$lustreCltRAMissesTOT=0;
  for (my $i=0; $i<$numBrwBuckets; $i++)
  { $lustreBufReadTOT[$i]=$lustreBufWriteTOT[$i]=0; }
  for (my $i=0; $i<$NumCpus; $i++)
  { $intrptTOT[$i]=0; }
  for (my $i=0; $i<11; $i++)
  { $buddyInfoTOT[$i]=0; }

  for (my $i=0; $i<$impNumMods; $i++) { &{$impPrintBrief[$i]}(4); }
}

sub countBriefCounters
{
  my $i=$NumCpus;
  $cpuTOT+=   $userP[$i]+$niceP[$i]+$sysP[$i];
  $sysPTOT+=  $sysP[$i];

  $intrptTOT+=$intrpt;
  $ctxtTOT+=  $ctxt;

  for ($i=0; $i<$NumCpus; $i++)
  { $intrptTOT[$i]+=$intrptTot[$i]; }

  # the default, it so add up the amount of actual memory used
  # could have reused the TOT counter names, but let's not
  if ($memOpts!~/R/)
  {
    $memFreeTOT+=  $memFree;
    $memBufTOT+=   $memBuf;
    $memCachedTOT+=$memCached;
    $memInactTOT+= $memInact;
    $memSlabTOT+=  $memSlab;
    $memMapTOT+=   $memMap+$memAnon;
  }
  else    # in this case we add up the changes
  {
    $memFreeCTOT+=  $memFreeC;
    $memBufCTOT+=   $memBufC;
    $memCachedCTOT+=$memCachedC;
    $memInactCTOT+= $memInactC;
    $memSlabCTOT+=  $memSlabC;
    $memMapCTOT+=   $memMapC+$memAnonC;
  }

  $slabSlabAllTotalTOT+= $slabSlabAllTotal;
  $slabSlabAllTotalBTOT+=$slabSlabAllTotalB;

  $dskReadKBTOT+=   $dskReadKBTot;
  $dskReadTOT+=     $dskReadTot;
  $dskWriteKBTOT+=  $dskWriteKBTot;
  $dskWriteTOT+=    $dskWriteTot;

  $netRxKBTOT+=     $netRxKBTot;
  $netRxPktTOT+=    $netRxPktTot;
  $netTxKBTOT+=     $netTxKBTot;
  $netTxPktTOT+=    $netTxPktTot;
  $netErrTOT+=      $netRxErrsTot+$netTxErrsTot;

  $tcpIpErrTOT+=   $ipErrors;
  $tcpIcmpErrTOT+= $icmpErrors;
  $tcpTcpErrTOT+=  $tcpErrors;
  $tcpUdpErrTOT+=  $udpErrors;
  $tcpTcpExErrTOT+=$tcpExErrors;

  $sockUsedTOT+=   $sockUsed;
  $sockUdpTOT+=	   $sockUdp;
  $sockRawTOT+=    $sockRaw;
  $sockFragTOT+=   $sockFrag;

  $filesAllocTOT+= $filesAlloc;
  $inodeUsedTOT+=  $inodeUsed;

  $elanRxKBTOT+=   $elanRxKBTot;
  $elanRxTOT+=     $elanRxTot;
  $elanTxKBTOT+=   $elanTxKBTot;
  $elanTxTOT+=     $elanTxTot;
  $elanErrorsTOT+= $elanErrors;

  $ibRxKBTOT+=     $ibRxKBTot;
  $ibRxTOT+=       $ibRxTot;
  $ibTxKBTOT+=     $ibTxKBTot;
  $ibTxTOT+=       $ibTxTot;
  $ibErrorsTOT+=   $ibErrorsTotTot;

  $nfsReadsTOT+=   $nfsReadsTot;
  $nfsWritesTOT+=  $nfsWritesTot;
  $nfsMetaTOT+=    $nfsMetaTot;
  $nfsCommitTOT+=  $nfsCommitTot;

  if ($NumMds)
  {
    # Although some apply to versions < 1.6.5, easier to just count everything
    $lustreMdsGetattrPlusTOT+=$lustreMdsGetattr+$lustreMdsGetattrLock+$lustreMdsGetxattr;
    $lustreMdsSetattrPlusTOT+=$lustreMdsReintSetattr+$lustreMdsSetxattr;
    $lustreMdsSyncTOT+=       $lustreMdsSync;
    $lustreMdsReintTOT+=      $lustreMdsReint;
    $lustreMdsReintUnlinkTOT+=$lustreMdsReintUnlink;
  }

  if ($NumOst)
  {
    $lustreReadKBytesTOT+= $lustreReadKBytesTot;
    $lustreReadOpsTOT+=    $lustreReadOpsTot;
    $lustreWriteKBytesTOT+=$lustreWriteKBytesTot;
    $lustreWriteOpsTOT+=   $lustreWriteOpsTot;
  }

  if ($reportCltFlag)
  {
    $lustreCltReadTOT+=   $lustreCltReadTot;
    $lustreCltReadKBTOT+= $lustreCltReadKBTot;
    $lustreCltWriteTOT+=  $lustreCltWriteTot;
    $lustreCltWriteKBTOT+=$lustreCltWriteKBTot;

    $lustreCltRAHitsTOT+=  $lustreCltRAHitsTot;
    $lustreCltRAMissesTOT+=$lustreCltRAMissesTot;
  }

  if ($NumBud)
  {
    for ($i=0; $i<11; $i++)
    {
      $buddyInfoTOT[$i]+=$buddyInfoTot[$i];
    }
  }

  for (my $i=0; $i<$impNumMods; $i++) { &{$impPrintBrief[$i]}(5); }
}

sub printBriefCounters
{
  my $type=shift;
  my $i;

  # For things that totals don't make sense, like CPUs or sockets, just do averags all the time
  # by using the number of instances
  my $mi=$miniInstances;
  my $totSecs=$interval;    # makes calculation of total easy
  if ($type=~/a/i)
  {
    # Totals are NOT normalized so for averages we need to divide by total seconds.
    $totSecs=($playback eq '') ? $seconds-$miniStart+$interval : $elapsedSecs;
    $datetime=' ' x length($datetime)    if $statOpts!~/s/i;    # when not in summary mode, include date/time stamps
  }

  chomp $type;
  printf "%s", $datetime     if $miniDateFlag || $miniTimeFlag;
  printf "%s", uc($type);

  printf "%3d %3d %5s %6s ",
	$cpuTOT/$mi, $sysPTOT/$mi, cvt($intrptTOT/$totSecs,5), cvt($ctxtTOT/$totSecs,6)
  	          if $subsys=~/c/;

  if ($subsys=~/j/)
  {
    for (my $i=0; $i<$NumCpus; $i++)
    {
      printf "%4s ", cvt($intrptTOT[$i]/$totSecs,4,0,0);
    }
  }

  if ($subsys=~/m/)
  {
    if ($memOpts!~/R/)
    {
      printf "%4s %4s %4s %4s %4s %4s ",
        cvt($memFreeTOT/$mi,4,1,1),  cvt($memBufTOT/$mi,4,1,1),  cvt($memCachedTOT/$mi,4,1,1), 
	cvt($memInactTOT/$mi,4,1,1), cvt($memSlabTOT/$mi,4,1,1), cvt($memMapTOT/$mi,4,1,1);
    }
    else
    {
      printf "%5s %5s %5s %5s %5s %5s ",
        cvt($memFreeCTOT/$mi,4,1,1),  cvt($memBufCTOT/$mi,4,1,1),  cvt($memCachedCTOT/$mi,4,1,1), 
	cvt($memInactCTOT/$mi,4,1,1), cvt($memSlabCTOT/$mi,4,1,1), cvt($memMapCTOT/$mi,4,1,1);
    }
  }

  # Need to average each field before converting
  if ($subsys=~/b/)
  {
    for ($i=0; $i<11; $i++)
    { $buddyInfoAVG[$i]=$buddyInfoTOT[$i]/$mi; }
    printf "%s ", base36(@buddyInfoAVG);
  }

  # Will probably never be used again
  printf "%6s %7s ",
	cvt($slabSlabAllTotalTOT/$mi,6,0,1), cvt($slabSlabAllTotalBTOT/$mi,7,0,1)
		  if $subsys=~/y/;

  if ($subsys=~/d/)
  { 
    if (!$ioSizeFlag && $dskOpts!~/i/)
    {
      printf "%6s %6s %6s %6s ", 
	cvt($dskReadKBTOT/$totSecs,6,0,1),  cvt($dskReadTOT/$totSecs,6), 
	cvt($dskWriteKBTOT/$totSecs,6,0,1), cvt($dskWriteTOT/$totSecs,6);
    }
    else
    {
      printf "%6s %6s %4s %6s %6s %4s ",
        cvt($dskReadKBTOT/$totSecs,6,0,1),  cvt($dskReadTOT/$totSecs,6), 
	$dskReadTOT ? cvt($dskReadKBTOT/$dskReadTOT,4,0,1) : 0,
        cvt($dskWriteKBTOT/$totSecs,6,0,1), cvt($dskWriteTOT/$totSecs,6), 
        $dskWriteTOT ? cvt($dskWriteKBTOT/$dskWriteTOT,4,0,1) : 0;
    }
   }

  if ($subsys=~/n/)
  {
    if (!$ioSizeFlag && $netOpts!~/i/)
    {
      printf "%6s %6s %6s  %6s ",
          cvt($netRxKBTOT/$totSecs,6,0,1), cvt($netRxPktTOT/$totSecs,6),
          cvt($netTxKBTOT/$totSecs,6,0,1), cvt($netTxPktTOT/$totSecs,6);
    }
    else
    {
      printf "%6s %6s %4s %6s  %6s %4s ", 
	  cvt($netRxKBTOT/$totSecs,6,0,1), cvt($netRxPktTOT/$totSecs,6), 
	  $netRxPktTOT ? cvt($netRxKBTOT*1024/$netRxPktTOT,4,0,1) : 0, 
	  cvt($netTxKBTOT/$totSecs,6,0,1), cvt($netTxPktTOT/$totSecs,6),
          $netTxPktTOT ? cvt($netTxKBTOT*1024/$netTxPktTOT,4,0,1) : 0;
    }
    printf "%5s ", cvt($netErrTOT/$totSecs,5)    if $netOpts=~/e/;
  }

  if ($subsys=~/t/)
  {
    printf "%4s ", cvt($tcpIpErrTOT/$totSecs,4)       if $tcpFilt=~/i/;
    printf "%4s ", cvt($tcpTcpErrTOT/$totSecs,4)      if $tcpFilt=~/t/;
    printf "%4s ", cvt($tcpUdpErrTOT/$totSecs,4)      if $tcpFilt=~/u/;
    printf "%4s ", cvt($tcpIcmpErrTOT/$totSecs,4)     if $tcpFilt=~/c/;
    printf "%4s ", cvt($tcpTcpExErrTOT/$totSecs,4)    if $tcpFilt=~/T/;
  }

  printf "%4d %4d %4d %4d ",
	cvt(int($sockUsedTOT/$mi),6), cvt(int($sockUdpTOT/$mi),6), 
	cvt(int($sockRawTOT/$mi),6),  cvt(int($sockFragTOT/$mi),6)
                  if $subsys=~/s/;

  printf "%6s %6s ", cvt($filesAllocTOT/$mi, 6), cvt($inodeUsedTOT/$mi, 6)
		  if $subsys=~/i/;

  printf "%7s %6s %7s %6s %6s ", 
	cvt($elanRxKBTOT/$totSecs,6,0,1), cvt($elanRxTOT/$totSecs,6), 
        cvt($elanTxKBTOT/$totSecs,6,0,1), cvt($elanTxTOT/$totSecs,6),
        cvt($elanErrorsTOT/$totSecs,6)
		  if $subsys=~/x/ && $NumXRails;

  if ($subsys=~/x/ && $NumHCAs)
  {
    if (!$ioSizeFlag && $xOpts!~/i/)
    {
      printf "%7s %6s %7s %6s %4s ", 
	  cvt($ibRxKBTOT/$totSecs,7,0,1), cvt($ibRxTOT/$totSecs,6), 
          cvt($ibTxKBTOT/$totSecs,7,0,1), cvt($ibTxTOT/$totSecs,6),
          cvt($ibErrorsTOT,4);
    }
    else
    {
      printf "%7s %6s %4s %7s %6s %4s %4s ",
          cvt($ibRxKBTOT/$totSecs,7,0,1), cvt($ibRxTOT/$totSecs,6), 
	  $ibRxTOT ? cvt($ibRxKBTOT*1024/ibRxTOT,4,0,1) : 0,
          cvt($ibTxKBTOT/$totSecs,7,0,1), cvt($ibTxTOT/$totSecs,6),
          $ibTxTOT ? cvt($ibTxKBTOT*1024/ibTxTOT,4,0,1) : 0,
          cvt($ibErrorsTOT,4);
    }
  }

  printf "%6s %6s %4s %4s ", 
	cvt($nfsReadsTOT/$totSecs,6), cvt($nfsWritesTOT/$totSecs,6), 
	cvt($nfsMetaTOT/$totSecs),    cvt($nfsCommitTOT/$totSecs)
	          if $subsys=~/f/;

  if ($subsys=~/l/ && $reportMdsFlag)
  {
    my $variableParam=($cfsVersion lt '1.6.5') ? $lustreMdsReintTOT : $lustreMdsReintUnlinkTOT;
    printf "%6s %6s %6s %6s ",
        cvt($lustreMdsGetattrPlusTOT/$totSecs,6), cvt($lustreMdsSetattrPlusTOT/$totSecs,6),
        cvt($lustreMdsSyncTOT/$totSecs,6),        cvt($variableParam/$totSecs,6);
  }

  if ($subsys=~/l/ && $reportOstFlag)
  {
    if (!$ioSizeFlag)
    {
      printf "%7s %6s %7s %6s ",
         cvt($lustreReadKBytesTOT/$totSecs,7,0,1),  cvt($lustreReadOpsTOT/$totSecs,6),
	 cvt($lustreWriteKBytesTOT/$totSecs,7,0,1), cvt($lustreWriteOpsTOT/$totSecs,6);
    }
    else
    {
      printf "%7s %6s %4s %7s %6s %4s ",
         cvt($lustreReadKBytesTOT/$totSecs,7,0,1),  cvt($lustreReadOpsTOT/$totSecs,6),
         $lustreReadOpsTOT ? cvt($lustreReadKBytesTOT/$lustreReadOpsTOT,4,0,1) : 0,
         cvt($lustreWriteKBytesTOT/$totSecs,7,0,1), cvt($lustreWriteOpsTOT/$totSecs,6),
         $lustreWriteOpsTOT ? cvt($lustreWriteKBytesTOT/$lustreWriteOpsTOT,4,0,1) : 0;
    }
  }

  if ($subsys=~/l/ && $reportCltFlag)
  {
    if (!$ioSizeFlag)
    {
      printf "%7s %6s  %7s %6s", 
	  cvt($lustreCltReadKBTOT/$totSecs,7,0,1),  cvt($lustreCltReadTOT/$totSecs,6),
  	  cvt($lustreCltWriteKBTOT/$totSecs,7,0,1), cvt($lustreCltWriteTOT/$totSecs,6);
    }
    else
    {
      printf "%7s %6s %4s  %7s %6s %4s",
          cvt($lustreCltReadKBTOT/$totSecs,7,0,1),  cvt($lustreCltReadTOT/$totSecs,6),
          $lustreCltReadTOT ?  cvt($lustreCltReadKBTOT/$lustreCltReadTOT,4,0,1) : 0,
          cvt($lustreCltWriteKBTOT/$totSecs,7,0,1), cvt($lustreCltWriteTOT/$totSecs,6),
	  $lustreCltWriteTOT ?  cvt($lustreCltWriteKBTOT/$lustreCltWriteTOT,4,0,1) : 0;
    }
    printf " %6s %6s", 
	cvt($lustreCltRAHitsTOT/$totSecs,6),cvt($lustreCltRAMissesTOT/$totSecs,6)
	    if $lustOpts=~/R/;
  }

  for (my $i=0; $i<$impNumMods; $i++) { &{$impPrintBrief[$i]}(6); }
  print "\n";
}

sub base36
{
  my @buddies=@_;
  my $frags;
  for (my $i=0; $i<scalar(@buddies); $i++)
  {
    my $map;
    my $num=$buddies[$i];
    if ($num>=1000)
    {
      # 1000->the res => 30->36
      $map=int(log($num)/log(10))-3;
      $map=8    if $map>8;
      $frag=substr('stuvwxyz', $map, 1);
    }
    elsif ($num>=100)
    {
      # 100->999 => 20->29
      $map=int($num)/100-1;
      $frag=substr('jklmnopqr', $map, 1);
    }
    elsif ($num>=10)
    {
      # 10->99 => 10->19
      $map=int($num)/10-1;
      $frag=substr('abcdefghi', $map, 1);
    }
    else
    {
      # 0->9 => 0->9
      $frag=int($num);
    }
    $frags.=$frag;
  }
  return($frags);
}

####################################################
#    T a s k    P r o c e s s i n g    S u p p o r t
####################################################

sub nextAvailProcIndex
{
  my $next;

  if (scalar(@procIndexesFree)>0)
  { $next=pop @procIndexesFree; }
  else
  { $next=$procNextIndex++; }

  printf "### Index allocated: $next NextIndex: $procNextIndex IndexesFree: %d\n",
	scalar(@procIndexesFree)    if $debug & 256;
  return($next);
}

# If we're not processing by pid-only, the processes we're reporting on come
# and go.  Therefore right before we print we need to see if a process we 
# were reporting on disappeared by noticing its pid went away and therefore 
# need to remove it from the $procIndexes{} hash.  Is there a better/more 
# efficient way to do this?  If so, fix 'cleanStalePids()' too.
sub cleanStaleTasks
{
  my ($removeFlag, %indexesTemp, $pid);

  if ($debug & 512)
  {
    print "### CleanStaleTasks()\n";
    foreach $pid (sort keys %procSeen)
    { print "### PIDPROC: $pid\n"; }
  }

  # make a list of only those pids we've seen during last cycle
  $removeFlag=0;
  foreach $pid (sort keys %procIndexes)
  {
    if (defined($procSeen{$pid}))
    {
      $indexesTemp{$pid}=$procIndexes{$pid};
      print "### indexesTemp[$pid] set to $indexesTemp{$pid}\n"
	if $debug & 256;
    }
    else
    {
      push @procIndexesFree, $procIndexes{$pid};
      $removeFlag=1; 
      print "### added $pid with index of $procIndexes{$pid} to free list\n"
	if $debug & 256;
    }
  }

  # only need to do a swap if we need to remove a pid.
  if ($removeFlag)
  {
    undef %procIndexes;
    %procIndexes=%indexesTemp;
    if ($debug & 512)
    {
      print "### Indexes Swapped!  NEW procIndexes{}\n";
      foreach $key (sort keys %procIndexes)
      { print "procIndexes{$key}=$procIndexes{$key}\n"; }
    }
  }
  undef %procSeen;
}

# This output only goes to the .prc file
sub printPlotProc
{
  my $date=shift;
  my $time=shift;
  my ($procHeaders, $procPlot, $pid, $i);

  $procHeaders='';
  if (!$headersPrintedProc)
  {
    $procHeaders=$commonHeader    if $logToFileFlag;
    $procHeaders.=(!$utcFlag) ? "#Date${SEP}Time" : '#UTC';;
    $procHeaders.="${SEP}PID${SEP}User${SEP}PR${SEP}PPID${SEP}THRD${SEP}S${SEP}VmSize${SEP}";
    $procHeaders.="VmLck${SEP}VmRSS${SEP}VmData${SEP}VmStk${SEP}VmExe${SEP}VmLib${SEP}";
    $procHeaders.="CPU${SEP}SysT${SEP}UsrT${SEP}PCT${SEP}AccumT${SEP}";
    $procHeaders.="RKB${SEP}WKB${SEP}RKBC${SEP}WKBC${SEP}RSYS${SEP}WSYS${SEP}CNCL${SEP}";
    $procHeaders.="MajF${SEP}MinF${SEP}Command\n";
    $headersPrintedProc=1;
  }

  $procPlot=$procHeaders;
  foreach $pid (sort keys %procIndexes)
  {
    $i=$procIndexes{$pid};
    next    if (!defined($procSTimeTot[$i]));
    next    if $procState ne '' && $procState[$i]!~/[$procState]/;

    # Handle -oF
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

    my $datetime=(!$utcFlag) ? "$date$SEP$time": time;
    $datetime.=".$usecs"    if $options=~/m/;

    # Username comes from translation hash OR we just print the UID
    $procPlot.=sprintf("%s${SEP}%d${SEP}%s${SEP}%s${SEP}%s${SEP}%d${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%d${SEP}%s${SEP}%d${SEP}%d${SEP}%d${SEP}%d${SEP}%d${SEP}%d${SEP}%d${SEP}%s${SEP}%s${SEP}%s",
          $datetime, $procPid[$i], $procUser[$i],  $procPri[$i], 
	  $procPpid[$i],  $procThread[%i], $procState[$i],  
	  defined($procVmSize[$i]) ? $procVmSize[$i] : 0, 
	  defined($procVmLck[$i])  ? $procVmLck[$i]  : 0,
	  defined($procVmRSS[$i])  ? $procVmRSS[$i]  : 0,
	  defined($procVmData[$i]) ? $procVmData[$i] : 0,
	  defined($procVmStk[$i])  ? $procVmStk[$i]  : 0,  
	  defined($procVmExe[$i])  ? $procVmExe[$i]  : 0,
	  defined($procVmLib[$i])  ? $procVmLib[$i]  : 0,
	  $procCPU[$i],
	  cvtT1($procSTime[$i],1), cvtT1($procUTime[$i],1),
          ($procSTime[$i]+$procUTime[$i])/$interval2SecsReal,
	  cvtT2($procSTimeTot[$i]+$procUTimeTot[$i],1),
	  defined($procRKB[$i])    ? $procRKB[$i]/$interval2Secs  : 0,
	  defined($procWKB[$i])    ? $procWKB[$i]/$interval2Secs  : 0,
	  defined($procRKBC[$i])   ? $procRKBC[$i]/$interval2Secs : 0,
	  defined($procWKBC[$i])   ? $procWKBC[$i]/$interval2Secs : 0,
	  defined($procRSys[$i])   ? $procRSys[$i]/$interval2Secs : 0,
	  defined($procWSys[$i])   ? $procWSys[$i]/$interval2Secs : 0,
	  defined($procCKB[$i])    ? $procCKB[$i]/$interval2Secs  : 0,
	  cvt($majFlt), cvt($minFlt),
	  defined($procCmd[$i])    ? $procCmd[$i] : $procName[$i]);

    # This is a little messy (sorry about that).  The way writeData works is that
    # on writeData(0) calls, it builds up a string in $oneline which can be appended
    # to the current string (for displaying multiple subsystems in plot format on
    # the terminal and the final call writes it out.  In order for all the paths
    # to work with sockets, etc we need to do it this way.  And since writeData takes
    # care of \n be sure to leave OFF each line being written.
    $oneline='';
    writeData(0, '', \$procPlot, PRC, $ZPRC, 'proc', \$oneline);
    if (!$logToFileFlag || ($sockFlag && $export eq ''))
    {
      last    if writeData(1, '', undef, $LOG, undef, undef, \$oneline)==0;
    }
    $procPlot='';
  }
}

sub procAnalyze
{
  my $seconds=shift;
  my $usevs=  shift;

  my ($vmSize, $vmLck, $vmRSS, $vmData, $vmStk, $vmLib, $vmExe);
  my ($rkb, $wkb, $rkbc, $wkbc, $rsys, $wsys, $cncl, $threads);

  # Would have been nice to use $interval2Counter, but that only increments
  # during terminal output.
  $procAnalCounter++;

  # loops through all processes for this interval and copy data to simpler variables
  foreach my $pid (keys %procIndexes)
  {
    # Global which indicates at least 1 piece of process data recorded.
    # we also need to save pids so we'll know what to print to file
    $procAnalyzed=1;
    $analyzed{$pid}=1;

    my $i=$procIndexes{$pid};
    my $user=$procUser[$i];
    my $ppid=$procPpid[$i];
    my $threads=$procTCount[$i];

    my $cpu=$procCPU[$i];
    my $sysT=$procSTime[$i];
    my $usrT=$procUTime[$i];
    my $accum=cvtT2($procSTimeTot[$i]+$procUTimeTot[$i]);
    my $majF=$procMajFlt[$i];
    my $minF=$procMinFlt[$i];
    my $command=(defined($procCmd[$i])) ? $procCmd[$i] : $procName[$i];

    $accum=~s/^\s*//g;
    $command=~s/\s+$//g;

    if (defined($procVmSize[$i]))
    {
      $vmSize=$procVmSize[$i];
      $vmLck=$procVmLck[$i];
      $vmRSS=$procVmRSS[$i];
      $vmData=$procVmData[$i];
      $vmStk=$procVmStk[$i];
      $vmLib=$procVmLib[$i];
      $vmExe=$procVmExe[$i];
    }
    else
    {
      $vmSize=$vmLck=$vmRSS=$vmData=$vmStk=$vmLib=$vmExe=0;
    }

    if ($processIOFlag)
    {
      $rkb=$procRKB[$i];   $wkb=$procWKB[$i];   $rkbc=$procRKBC[$i]; $wkbc=$procWKBC[$i];
      $rsys=$procRSys[$i]; $wsys=$procWSys[$i]; $cncl=$procCKB[$i];
    }

    # Here's what's going on.  We're identifying a unique command by its pid and
    # name.  That way if pids are reused the probability of the same pid showing
    # up for the same command are slim.  BUT, when processing multiple logs for
    # the same day it CAN happen, so we're adding a filename discriminator as well.
    my $unique="$fileRoot:$pid:$command";
    if (!defined($summary[$pid]))
    {
      $summary[$pid]={
            date=>$date,        timefrom=>$seconds, threadsMin=>$threads, threadsMax=>$threads,
            pid=>$pid,          user=>$user,        ppid=>$ppid,        vmExe=>$vmExe,
            vmSizeMin=>$vmSize, vmSizeMax=>$vmSize, vmLckMin=>$vmLck,   vmLckMax=>$vmLck,
            vmRSSMin=>$vmRSS,   vmRSSMax=>$vmRSS,   vmDataMin=>$vmData, vmDataMax=>$vmData, 
            vmStkMin=>$vmStk,   vmStkMax=>$vmStk,   vmLibMin=>$vmLib,   vmLibMax=>$vmLib,
            sysT=>0,  usrT=>0,  majF=>0,  minF=>0,  RKB=>0,  WKB=>0,  RKBC=>0,
            WKBC=>0,  RSYS=>0,  WSYS=>0,  CNCL=>0,  command=>$command
      }
    }

    #    U p d a t e    S u m m a r y

    $summary[$pid]->{timethru}=$seconds;
 
    # thread counts  not necessarily included in raw file
    $summary[$pid]->{threadsMin}=$threads  if defined($threads) && $threads<$summary[$pid]->{threadsMin};
    $summary[$pid]->{threadsMax}=$threads  if defined($threads) && $threads>$summary[$pid]->{threadsMax};

    $summary[$pid]->{vmSizeMin}=$vmSize    if $vmSize<$summary[$pid]->{vmSizeMin};
    $summary[$pid]->{vmSizeMax}=$vmSize    if $vmSize>$summary[$pid]->{vmSizeMax};
    $summary[$pid]->{vmLckMin}=$vmLck      if $vmLck< $summary[$pid]->{vmLckMin};
    $summary[$pid]->{vmLckMax}=$vmLck      if $vmLck> $summary[$pid]->{vmLckMax};
    $summary[$pid]->{vmRSSMin}=$vmRSS      if $vmRSS< $summary[$pid]->{vmRSSMin};
    $summary[$pid]->{vmRSSMax}=$vmRSS      if $vmRSS> $summary[$pid]->{vmRSSMax};
    $summary[$pid]->{vmDataMin}=$vmData    if $vmData<$summary[$pid]->{vmDataMin};
    $summary[$pid]->{vmDataMax}=$vmData    if $vmData>$summary[$pid]->{vmDataMax};
    $summary[$pid]->{vmStkMin}=$vmStk      if $vmStk< $summary[$pid]->{vmStkMin};
    $summary[$pid]->{vmStkMax}=$vmStk      if $vmStk> $summary[$pid]->{vmStkMax};
    $summary[$pid]->{vmLibMin}=$vmLib      if $vmLib< $summary[$pid]->{vmLibMin};
    $summary[$pid]->{vmLibMax}=$vmLib      if $vmLib> $summary[$pid]->{vmLibMax};

    $summary[$pid]->{sysT}+=$sysT;
    $summary[$pid]->{usrT}+=$usrT;
    $summary[$pid]->{accumT}=$accum;

    if ($processIOFlag)
    {
      $summary[$pid]->{RKB}+=$rkb;
      $summary[$pid]->{WKB}+=$wkb;
      $summary[$pid]->{RKBC}+=$rkbc;
      $summary[$pid]->{WKBC}+=$wkbc;
      $summary[$pid]->{RSYS}+=$rsys;
      $summary[$pid]->{WSYS}+=$wsys;
      $summary[$pid]->{CNCL}+=$cncl;
      $summary[$pid]->{majF}+=$majF;
      $summary[$pid]->{minF}+=$minF;
    }
  }
}

# This gets called twice!  Once when we're ready to process a NEW file and
# again to write out the process summary data for the LAST log we processed
sub printProcAnalyze
{
  print "Write process summary data to: $lastLogPrefix\n"    if $debug & 8192;

  # Note that since this is the only place we write to these files, lets open
  # them here instead of trying to do it in newlog especially since newlog has
  # no way of knowing if there will even be any data to write to them!
  open PRCS, ">$lastLogPrefix.prcs" or
        logmsg("F", "Couldn't create '$lastLogPrefix.prcs'")  if !$zFlag;
  $ZPRCS=Compress::Zlib::gzopen("$lastLogPrefix.prcs.gz", 'wb') or
        logmsg("F", "Couldn't create '$lastLogPrefix.prcs.gz'")    if  $zFlag;

  # NOTE - we're not printing the CPU since processes can migrate and it's not really
  #        meaningful yet.  Perhaps someday I'll do more with it.
  my $header;
  $header= "Date${SEP}From${SEP}Thru${SEP}Pid${SEP}User${SEP}PPid${SEP}ExeSize${SEP}SizeMin${SEP}";
  $header.="SizeMax${SEP}LckMin${SEP}LckMax${SEP}RSSMin${SEP}RSSMax${SEP}DataMin${SEP}DataMax${SEP}";
  $header.="StkMin${SEP}StkMax${SEP}LibMin${SEP}LibMax${SEP}sysT${SEP}usrT${SEP}PCT${SEP}accumT${SEP}";
  $header.="RKB${SEP}WKB${SEP}RKBC${SEP}WKBC${SEP}RSYS${SEP}WSYS${SEP}CNCL${SEP}"    if $processIOFlag;
  $header.="threadsMin${SEP}threadsMax${SEP}";
  $header.="majF${SEP}minF${SEP}Command\n";

  print PRCS $header    if !$zFlag;
  $ZPRCS->gzwrite($header) or logmsg("E", "Error writing PCRS header")    if  $zFlag;

  my $line;
  my ($date, $timefrom, $timethru);
  foreach my $pid (keys %analyzed)
  {
    # Date always come from 'from' field
    ($date,$timefrom)=cvtT4($summary[$pid]->{timefrom});

    # if process only ran for one interval the duration would be 0 and we can't allow that to be a divisor below.
    my $pidDuration=$summary[$pid]->{timethru}-$summary[$pid]->{timefrom};
    $pidDuration=1    if $pidDuration==0;

    # NOTE - since sys/usr times in jiffies DON'T multiply by 100
    $line=sprintf("%s$SEP%s$SEP%s$SEP%d$SEP%s$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%s$SEP%s$SEP%6.2f$SEP%s$SEP",
      $date, $timefrom, (cvtT4($summary[$pid]->{timethru}))[1],
      $summary[$pid]->{pid},
      $summary[$pid]->{user},
      $summary[$pid]->{ppid},

      $summary[$pid]->{vmExe},
      $summary[$pid]->{vmSizeMin},
      $summary[$pid]->{vmSizeMax},
      $summary[$pid]->{vmLckMin},
      $summary[$pid]->{vmLckMax},
      $summary[$pid]->{vmRSSMin},
      $summary[$pid]->{vmRSSMax},
      $summary[$pid]->{vmDataMin},
      $summary[$pid]->{vmDataMax},
      $summary[$pid]->{vmStkMin},
      $summary[$pid]->{vmStkMax},
      $summary[$pid]->{vmLibMin},
      $summary[$pid]->{vmLibMax},

      cvtT3($summary[$pid]->{sysT}),
      cvtT3($summary[$pid]->{usrT}),
      ($summary[$pid]->{sysT}+$summary[$pid]->{usrT})/$pidDuration/$procAnalCounter,
      $summary[$pid]->{accumT});

    $line.=sprintf("%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP",
      $summary[$pid]->{RKB},
      $summary[$pid]->{WKB},
      $summary[$pid]->{RKBC},
      $summary[$pid]->{WKBC},
      $summary[$pid]->{RSYS},
      $summary[$pid]->{WSYS},
      $summary[$pid]->{CNCL})
            if $processIOFlag;

    $line.=sprintf("%d$SEP%d$SEP", $summary[$pid]->{threadsMin}, $summary[$pid]->{threadsMax});
    $line.=sprintf("%d$SEP%d$SEP%s\n", $summary[$pid]->{majF}, $summary[$pid]->{minF}, $summary[$pid]->{command});
    print PRCS $line     if !$zFlag;
    $ZPRCS->gzwrite($line) or logmsg('E', "Error writing to prcs")     if  $zFlag;
  }
  undef %summary;
  $procAnalyzed=0;
  close PRCS;
  $ZPRCS->gzclose()    if $zFlag;

  $procAnalCounter=0;
}

sub slabAnalyze
{
  $slabAnalCounter++;
  if ($slabinfoFlag)
  {
    for (my $i=0; $i<$slabIndexNext; $i++)
    {
      slabAnalyze2($slabName[$i], $slabSlabAllTotB[$i]); 
    }
  }
  else
  {
    foreach my $first (sort keys %slabfirst)
    {
      slabAnalyze2($slabfirst{$first}, $slabdata{$slab}->{total}); 
    }
  }
}

sub slabAnalyze2
{
  my $name=shift;
  my $size=shift;

  if (!defined($slabMemTotMin{$name}))
  {
    $slabMemTotMin{$name}=1024*1024*1024*1024;    # 1TB
    $slabMemTotMax{$name}=0;
    $slabMemTotFirst{$name}=$size;
  }
  $slabMemTotMin{$name}=$size    if $size<$slabMemTotMin{$name};
  $slabMemTotMax{$name}=$size    if $size>$slabMemTotMax{$name};
  $slabMemTotLast{$name}=$size;
}

sub printSlabAnalyze
{
  print "Write slab summary data to: $lastLogPrefix\n"    if $debug & 8192;

  open SLBS, ">$lastLogPrefix.slbs" or
        logmsg("F", "Couldn't create '$lastLogPrefix.slbs'")  if !$zFlag;
  $ZSLBS=Compress::Zlib::gzopen("$lastLogPrefix.slbs.gz", 'wb') or
        logmsg("F", "Couldn't create '$lastLogPrefix.slbs.gz'")    if  $zFlag;

  my $header=sprintf("%-20s  %10s  %10s  %10s  %10s  %8s  %8s\n",
	'Slab Name', 'Start', 'End', 'Minimum', 'Maximum', 'Change', 'Pct');
  print SLBS $header    if !$zFlag;
  $ZSLBS->gzwrite($header) or logmsg("E", "Error writing SLBS header")    if  $zFlag;

  foreach my $name (sort keys %slabMemTotMin)
  {
    next    if $slabMemTotMax{$name}==0;

    my $diff=$slabMemTotMax{$name}-$slabMemTotMin{$name};
    my $line=sprintf("%-20s  %10d  %10d  %10d  %10d  %8d  %8.2f\n", 
                     $name, $slabMemTotFirst{$name}, $slabMemTotLast{$name}, 
    		     $slabMemTotMin{$name}, $slabMemTotMax{$name}, $diff,
		     $slabMemTotMin{$name} ? 100*$diff/$slabMemTotMin{$name} : 0);

    print SLBS $line     if !$zFlag;
    $ZSLBS->gzwrite($line) or logmsg('E', "Error writing to slbs")     if  $zFlag;
  }
  close SLBS;
  $ZSLBS->gzclose()    if $zFlag;

  # Reset for next time
  $slabAnalCounter=0;
  undef %slabTotalMemLast;
  undef %slabMemTotMin;
  undef %slabMemTotMax;
  undef %slabMemTotLast;
}

# like printPlotProc(), this only goes to .slb and we don't care about --logtoo
sub printPlotSlab
{
  my $date=shift;
  my $time=shift;
  my ($slabHeaders, $slabPlot);

  $slabHeaders='';
  if (!$headersPrintedSlab)
  {
    $slabHeaders=$commonHeader    if $logToFileFlag;
    $slabHeaders.=$slubHeader     if $logToFileFlag && $slubinfoFlag;
    $slabHeaders.=(!$utcFlag) ? "#Date${SEP}Time" : '#UTC';
    if ($slabinfoFlag)
    {
      $slabHeaders.="${SEP}SlabName${SEP}ObjInUse${SEP}ObjInUseB${SEP}ObjAll${SEP}ObjAllB${SEP}";
      $slabHeaders.="SlabInUse${SEP}SlabInUseB${SEP}SlabAll${SEP}SlabAllB${SEP}SlabChg${SEP}SlabPct\n";
    }
    else
    {
      $slabHeaders.="${SEP}SlabName${SEP}ObjSize${SEP}ObjPerSlab${SEP}ObjInUse${SEP}ObjAvail${SEP}";
      $slabHeaders.="SlabSize${SEP}SlabNumber${SEP}MemUsed${SEP}MemTotal${SEP}SlabChg${SEP}SlabPct\n";
    }
    $headersPrintedSlab=1;
  }

  my $datetime=(!$utcFlag) ? "$date$SEP$time": time;
  $datetime.=".$usecs"    if $options=~/m/;
  $slabPlot=$slabHeaders;

  #    O l d    S l a b    F o r m a t

  if ($slabinfoFlag)
  {
    for (my $i=0; $i<scalar(@slabSlabAllTot); $i++)
    {
      # Skip filtered data
      next    if ($slabOpts=~/s/ && $slabSlabAllTot[$i]==0) ||
                 ($slabOpts=~/S/ && $slabSlabAct[$i]==0 && $slabSlabAll[$i]==0);

      $slabPlot.=sprintf("%s$SEP%s$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d\n",
     	   $datetime, $slabName[$i],
	   $slabObjActTot[$i],  $slabObjActTotB[$i], $slabObjAllTot[$i],  $slabObjAllTotB[$i],
           $slabSlabActTot[$i], $slabSlabActTotB[$i],$slabSlabAllTot[$i], $slabSlabAllTotB[$i],
	   $slabTotMemChg[$i],  $slabTotMemPct[$i]);
    }
  }

  #    N e w    S l a b    F o r m a t

  else
  {
    foreach my $first (sort keys %slabfirst)
    {
      # This is all pretty much lifted from 'Slab Detail' reporting
      my $slab=$slabfirst{$first};
      my $numObjects=$slabdata{$slab}->{objects};
      my $numSlabs=  $slabdata{$slab}->{slabs};

      next    if ($slabOpts=~/s/ && $slabdata{$slab}->{objects}==0) ||
                 ($slabOpts=~/S/ && $slabdata{$slab}->{lastobj}==$numObjects &&
                                   $slabdata{$slab}->{lastslabs}==$numSlabs);

      $slabPlot.=sprintf("$datetime$SEP%s$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d$SEP%d\n",
            $first,      $slabdata{$slab}->{slabsize},  $slabdata{$slab}->{objper},
            $numObjects, $slabdata{$slab}->{avail},     ($PageSize<<$slabdata{$slab}->{order})/1024,
            $numSlabs,   $slabdata{$slab}->{used}/1024, $slabdata{$slab}->{total}/1024,
                         $slabdata{$slab}->{memchg},    $slabdata{$slab}->{mempct});

      # So we can tell when something changes
      $slabdata{$slab}->{lastobj}=  $numObjects;
      $slabdata{$slab}->{lastslabs}=$numSlabs;
    }
  }

  # See printPlotProc() for details on this...
  # Also note we're printing the whole thing in one call vs 1 call/line and we
  # only want to print when there's data since filtering can result in blank
  # lines.  Finally, since writeData() appends a find \n, we need to strip it.
  if ($slabPlot ne '')
  {
    $oneline='';
    $slabPlot=~s/\n$//;
    writeData(0, '', \$slabPlot, SLB, $ZSLB, 'slb', \$oneline);
    writeData(1, '', undef, $LOG, undef, undef, \$oneline)
        if !$logToFileFlag || ($sockFlag && $export eq '');
  }
}

sub elanCheck
{
  my $saveRails=$NumXRails;

  $NumXRails=0;
  if (!-e "/proc/qsnet")
  {
    logmsg('W', "no interconnect data found (/proc/qsnet missing)")
	if $inactiveElanFlag==0;
    $inactiveElanFlag=1;
  }
  else
  {
    $NumXRails++    if -e "/proc/qsnet/ep/rail0";
    $NumXRails++    if -e "/proc/qsnet/ep/rail1";

    # Now that I changed from using `cat` to cat(), let's just do
    # this each time.
    if ($NumXRails)
    {
      $XType='Elan';
      $XVersion=cat('/proc/qsnet/ep/version');
      chomp $XVersion;
    }
    else
    {
      logmsg('W', "/proc/qsnet exists but no rail stats found.  is the driver loaded?")
	  if $inactiveElanFlag==0;
      $inactiveElanFlag=1;
    }
  }

  print "ELAN Change -- OldRails: $saveRails  NewRails: $NumXRails\n"
        if $debug & 2 && $NumXRails ne $saveRails;

  return ($NumXRails ne $saveRails) ? 1 : 0;
}

sub ibCheck
{
  my $saveHCANames=$HCANames;
  my $activePorts=0;
  my ($line, @lines, $port);

  # Just because we have hardware doesn't mean any drivers installed and
  # the assumption for now is that's the case if you can't find vstat.
  # Since VStat can be a list, reset to the first that is found (if any)
  $NumHCAs=0;
  my $found=0;
  foreach my $temp (split(/:/, $VStat))
  {
    if (-e $temp)
    {
      $found=1;
      $VStat=$temp;
      last;
    }
  }

  # This error can only happen when NOT open fabric
  if (!-e $SysIB && !$found)
  {
    logmsg('E', "Found HCA(s) but no software OR monitoring disabled in $configFile")
        if $inactiveIBFlag==0;
    $mellanoxFlag=0;
    $inactiveIBFlag=1;
    return(0);
  }

  # We need the names of the interfaces and port info, but it depends on the
  # type of IB we're dealing with.  In the case of 'vib' we get them via 'vtstat'
  # and in the case of ofed via '/sys'.  However, in very rare cases someone might
  # have both stacks installed so just because we find 'vstat' doesn't mean vib is
  # loaded.
  my ($maxPorts, $numPorts)=(0,0);
  $HCANames='';
  if (-e $VStat)
  {
    @lines=`$VStat`;
    foreach $line (@lines)
    {
      if ($line=~/hca_id=(.+)/)
      {
	# We need to track max ports across all HCAs.  Most likely this
        # is a contant.
        $maxPorts=$numPorts    if $numPorts>$maxPorts;
        $numPorts=0;

        $NumHCAs++;
        $HCAName[$NumHCAs-1]=$1;
        $HCAPorts[$NumHCAs-1]=0;  # none active yet
        $HCANames.=" $1";
      }
      elsif ($line=~/port=(\d+)/)
      {
        $port=$1;
        $numPorts++;
      }
      elsif ($line=~/port_state=(.+)/)
      {
        $portState=($1 eq 'PORT_ACTIVE') ? 1 : 0;
        $HCAPorts[$NumHCAs-1][$port]=$portState;
        if ($portState)
        {
	  print "  VIB Port: $port\n"    if $debug & 2;
          $HCANames.=":$port";
          $activePorts++;
        }
      }
    $maxPorts=$numPorts    if $numPorts>$maxPorts;
    }

    # Only if we found any HCAs (since 'vib' may not actually be loaded...)
    $VoltaireStats=(-e '/proc/voltaire/adaptor-mlx/stats') ?
	  '/proc/voltaire/adaptor-mlx/stats' : '/proc/voltaire/ib0/stats'
		if $NumHCAs;
  }

  # To get here, either no 'vib' OR 'vib' is there but not loaded
  if ($NumHCAs==0)
  {
    my (@ports, $state, $file, $lid);
    @lines=ls($SysIB);
    foreach $line (@lines)
    {
      $line=~/(.*)(\d+)$/;
      $devname=$1;
      $devnum=$2;

      # While this should work for any ofed compliant adaptor, doing it this
      # way at least makes it more explicit which ones have been found to work.
      if ($devname=~/mthca|mlx4_|qib/)
      {
        $HCAName[$NumHCAs]=$devname;
        $HCAPorts[$NumHCAs]=0;  # none active yet
        $HCANames.=" $devname";
	$file=$SysIB;
	$file.="/$devname";
	$file.=$devnum;
	$file.="/ports";

        @ports=ls($file);
	$maxPorts=scalar(@ports)    if scalar(@ports)>$maxPorts;
        foreach $port (@ports)
        {
	  $port=~/(\d+)/;
	  $port=$1;
	  $state=cat("$file/$1/state");
          $state=~/.*: *(.+)/;
          $portState=($1 eq 'ACTIVE') ? 1 : 0;
          $HCAPorts[$NumHCAs][$port]=$portState;
	  chomp($lid=cat("$file/$port/lid"));
          $HCALids[$NumHCAs][$port]=$lid;
	  if ($portState)
          {
	    print "  OFED Port: $port  LID: $lid\n"    if $debug & 2;
            $HCANames.=":$port";
            $activePorts++;
           }
        }
      }
      $NumHCAs++;
    }
  }
  $HCANames=~s/^ //;

  # Now we need to know port states for header.
  $HCAPortStates='';
  for ($i=0; $i<$NumHCAs; $i++)
  {
    for (my $j=1; $j<=scalar($maxPorts); $j++)
    {
      # The expectation is the number of ports is contant on all HCAs
      # but just is case they're not, set extras to 0.
      $HCAPorts[$i][$j]=0    if !defined($HCAPorts[$i][$j]);
      $HCAPortStates.=$HCAPorts[$i][$j];
    }
    $HCAPortStates.=':';
  }
  $HCAPortStates=~s/:$//;

  # only report inactive status once per day OR after something changed
  if ($activePorts==0)
  {
    logmsg('E', "Found $NumHCAs HCA(s) but none had any active ports")
        if $inactiveIBFlag==0;
    $inactiveIBFlag=1;
  }

  # The names include active ports too so changes can be detected.
  $changeFlag=($HCANames ne $saveHCANames) ? 1 : 0;
  print "IB Change -- OldHCAs: $saveHCANames  NewHCAs: $HCANames\n"
        if $debug & 2 && $HCANames ne $saveHCANames;

  return ($activePorts && $HCANames ne $saveHCANames) ? 1 : 0;
}

sub lustreCheckClt
{
  # don't bother checking if specific services were specified and not this one
  return 0    if $lustreSvcs ne '' && $lustreSvcs!~/c/i;

  my ($saveFS, $saveOsts, $saveInfo, @lustreFS, @lustreDirs);
  my ($dir, $dirname, $inactiveFlag);

  # We're saving the info because as unlikely as it is, if the ost or fs state
  # changes without their numbers changing, we need to know!
  $saveFS=   $NumLustreFS;
  $saveOsts= $NumLustreCltOsts;
  $saveInfo= $lustreCltInfo;

  undef @lustreCltDirs;
  undef @lustreCltFS;
  undef @lustreCltFSCommon;
  undef @lustreCltOsts;
  undef @lustreCltOstFS;
  undef @lustreCltOstDirs;

  #    G e t    F i l e s y s t e m    N a m e s

  $FSWidth=0;
  @lustreFS=glob("/proc/fs/lustre/llite/*");
  $lustreCltInfo='';
  foreach my $dir (@lustreFS)
  {
    # in newer versions of lustre, the fs name was dropped from uuid, so look here instead
    # which does exist in earlier versions too, but we didn't look there sooner because
    # uuid is still used in other cases and I wanted to be consistent.
    my $commonName=cat("$dir/lov/common_name");
    chomp $commonName;
    my $fsName=(split(/-/, $commonName))[0];

    # we use the dirname for finding 'stats' and fsname for printing.
    # we may need the common name to make osts back to filesystems
    my $dirname=basename($dir);
    push @lustreCltDirs,     $dirname;
    push @lustreCltFS,       $fsName;
    push @lustreCltFSCommon, $commonName;

    $lustreCltInfo.="$fsName: ";
    $FSWidth=length($fsName)    if $FSWidth<length($fsName);
    $CltFlag=1;
  }
  $FSWidth++;
  $NumLustreFS=scalar(@lustreCltFS);

  # if the number of FS grew, we need to init more variables!
  initLustre('c', $saveFS, $NumLustreFS)    if $NumLustreFS>$saveFS;

  #    O n l y    F o r    ' - - l u s t o p t s  B / O '    G e t    O S T    N a m e s

  undef %lustreCltOstMappings;
  $inactiveFlag=0;
  $NumLustreCltOsts='-';    # only meaningful for --lustopts O
  if ($CltFlag && $lustOpts=~/[BO]/)
  {
    # we first need to get a list of all the OST uuids for all the filesystems, noting
    # the 1 passed to cat() tells it to read until EOF
    foreach my $commonName (@lustreCltFSCommon)
    {
      my $fsName=(split(/-/, $commonName))[0];
      my $obds=cat("/proc/fs/lustre/lov/$commonName/target_obd", 1);
      foreach my $obd (split(/\n/, $obds))
      {
        my ($uuid, $state)=(split(/\s+/, $obd))[1,2];
        next    if $state ne 'ACTIVE';
	$lustreCltOstMappings{$uuid}=$fsName;
      }
    }

    $lustreCltInfo='';      # reset by adding in OSTs
    $NumLustreCltOsts=0;
    @lustreDirs=glob("/proc/fs/lustre/osc/*");
    foreach $dir (@lustreDirs)
    {
      # Since we're looking for OST subdirectories, ignore anything not a directory
      # which for now is limted to 'num_refs', but who knows what the future will
      # hold.  As for the 'MNT' test, I think that only applied to older versions
      # of lustre, certainlu tp HP-SFS.
      next    if !-d $dir;   # currently only the 'num_refs' file
      next    if $cfsVersion lt '1.6.0' && $dir!~/\d+_MNT/;

      # Looks like if you're on a 1.6.4.3 system (and perhaps earlier) that is both
      # a client as well as an MDS, you'll see MDS specific directories with names
      # like - lustre-OST0000-osc, whereas lustre-OST0000-osc-000001012e950400 is the
      # client directory we want, so...
      next    if $dir=~/\-osc$/;

      # if ost closed (this happens when new filesystems get created), ignore it.
      # note that newer versions of lustre added a sstate and sets it to DEACTIVATED
      my ($uuid, $state,$sstate)=split(/\s+/, cat("$dir/ost_server_uuid"));
      next    if $state=~/CLOSED|DISCONN/ || $sstate=~/DEACT/;

      # uuids look something like 'xxx-ost_UUID' and you can actully have a - or _
      # following the xxx so drop the beginning/end this way in case an embedded _
      # in ost name itself.
      $ostName=$uuid;
      $ostName=~s/.*?[-_](.*)_UUID/$1/;
      $fsName=$lustreCltOstMappings{$uuid};

      $OstWidth=length($ostName)    if $OstWidth<length($ostName);

      $lustreCltInfo.="$fsName:$ostName ";
      $lustreCltOsts[$NumLustreCltOsts]=$ostName;
      $lustreCltOstFS[$NumLustreCltOsts]=$fsName;
      $lustreCltOstDirs[$NumLustreCltOsts]=$dir;
      $NumLustreCltOsts++;
    }
    $inactiveOstFlag=$inactiveFlag;
    $OstWidth=3    if $OstWidth<3;

    # If osts grew, need to init for new ones.
    initLustre('c2', $saveOsts, $NumLustreCltOsts)    if $NumLustreCltOsts>$saveOsts;
  }
  $lustreCltInfo=~s/ $//;

  # Change info is important even when not logging except during initialization
  if ($lustreCltInfo ne $saveInfo)
  {
    my $comment=($filename eq '') ? '#' : '';
    my $text="Lustre CLT OSTs Changed -- Old: $saveInfo  New: $lustreCltInfo";
    logmsg('W', "${comment}$text")    if !$firstPass;
    print "$text\n"       if $firstPass && $debug & 8;
  }

  return ($lustreCltInfo ne $saveInfo) ? 1 : 0;
}

sub lustreCheckMds
{
  # don't bother checking if specific services were specified and not this one
  return 0    if $lustreSvcs ne '' && $lustreSvcs!~/m/i;

  # if this wasn't an MDS and still isn't, nothing has changed
  my $type=($cfsVersion lt '1.6.0') ? 'MDT' : 'MDS';
  return 0    if !$NumMds && !-e "/proc/fs/lustre/mdt/$type/mds/stats";

  my ($saveMdsNames, @mdsDirs, $mdsName);
  $saveMdsNames=$MdsNames;

  $MdsNames='';
  $NumMds=$MdsFlag=0;
  @mdsDirs=glob("/proc/fs/lustre/mds/*");
  foreach $mdsName (@mdsDirs)
  {
    next    if $mdsName=~/num_refs/;
    $mdsName=basename($mdsName);
    $MdsNames.="$mdsName ";
    $NumMds++;
    $MdsFlag=1;    # for consistency with CltFlag and OstFlag
  }
  $MdsNames=~s/ $//;

  # Change info is important even when not logging except during initialization
  if ($MdsNames ne $saveMdsNames)
  {
    my $comment=($filename eq '') ? '#' : '';
    my $text="Lustre MDS FS Changed -- Old: $saveMdsNames  New: $MdsNames";
    logmsg('W', "${comment}$text")    if !$firstPass;
    print "$text\n"       if $firstPass && $debug & 8;
  }

  return ($MdsNames ne $saveMdsNames) ? 1 : 0;
}

sub lustreCheckOst
{ 
  # don't bother checking if specific services were specified and not this one
  return 0    if $lustreSvcs ne '' && $lustreSvcs!~/o/i;

  # if this wasn't an OST and still isn't, nothing has changed.
  return 0    if !$NumOst && !-e "/proc/fs/lustre/obdfilter";

  my ($saveOst, $saveOstNames, @ostFiles, $file, $ostName, $subdir);
  $saveOst=$NumOst;
  $saveOstNames=$OstNames;

  undef @lustreOstSubdirs;

  # check for OST files
  $OstNames='';
  $NumOst=$OstFlag=0;
  @ostFiles=glob("/proc/fs/lustre/obdfilter/*/stats");
  foreach $file (@ostFiles)
  {
    $file=~m[/proc/fs/lustre/obdfilter/(.*)/stats];
    $subdir=$1;
    push @lustreOstSubdirs, $subdir;

    $temp=cat("/proc/fs/lustre/obdfilter/$subdir/uuid");
    $ostName=transLustreUUID($temp);
    $OstWidth=length($ostName)    if $OstWidth<length($ostName);

    $lustreOsts[$NumOst]=$ostName;
    $OstNames.="$ostName ";
    $NumOst++;
    $OstFlag=1;   # for consistency with CltFlag and MdsFlag
  }
  $OstNames=~s/ $//;
  $OstWidth=3    if $OstWidth<3;
  initLustre('o', $saveOst, $NumOst)    if $NumOst>$saveOst;

  # Change info is important even when not logging except during initialization
  if ($OstNames ne $saveOstNames)
  {
    my $comment=($filename eq '') ? '#' : '';
    my $text="Lustre OSS OSTs Changed -- Old: $saveOstNames  New: $OstNames";
    logmsg('W', "${comment}$text")    if !$firstPass;
    print "$text\n"       if $firstPass && $debug & 8;
  }

  return ($OstNames ne $saveOstNames) ? 1 : 0;
}

sub transLustreUUID
{
  my $name=shift;
  my $hostRoot;

  # This handles names like OST_Lustre9_2_UUID or OST_Lustre9_UUID or in
  # the case of SFS something like ost123_UUID, changing them to just 0,9
  # or ost123.
  chomp $name;
  $hostRoot=$Host;
  $hostRoot=~s/\d+$//;
  $name=~s/OST_$hostRoot\d+//;
  $name=~s/_UUID//;
  $name=~s/_//;
  $name=0    if $name eq '';

  return($name);
}

# since it seems OFED changes the locations of perfquery and ofed_info
# with each release, we're gonna check for them here and if we can't find
# them, do an 'rpm -qal' and look for them there and on finding them,
# update /etc/collectl.conf (if we can)
sub getOfedPath
{
  my $list= shift;
  my $name= shift;
  my $label=shift;

  my $found='';
  foreach my $path (split(/:/, $list))
  {
    if (-e $path)
    {
      $found=$path;
      last;
    }
  }

  # RHEL54 stopped shipping it so we need to know RH version first
  my $RHVersion=($Distro=~/Red Hat.*(\d+\.\d+)/) ? $1 : '';

  # Can't find in standard places so ask rpm, but only if it's there
  if ($found eq '' && -e $Rpm && $RHVersion ne '' && $RHVersion<5.4)
  {
    # This is something we really don't want to have to be doing
    logmsg('W', "Cannot find '$name' in ${configFile}'s OFED search list, checking with rpm");

    $command="$Rpm -qal | $Grep $name | $Grep -v man";
    print "Command: $command\n"    if $debug & 2;
    $found=`$command`;
    if ($found ne '')
    {
      if (-w $configFile)
      {
        chomp($found);
        logmsg('I', "Adding '$found' to '$label' in $configFile");
        my $conf=`$Cat $configFile`;
        $conf=~s/($label\s+=\s+)(.*)$/$1$found:$2/m;
        open  CONF, ">$configFile" or logmsg("F", "Couldn't write to $configFile so do it manually!");
        print CONF $conf;
        close CONF;
      }
      else
      {
        logmsg('W', "found '$name' in rpm but $configFile not writeable so not updated");
      }
    }
  }
  return($found);
}

# While tempted to put this in collectl main line, this is really only used during formatting
sub loadEnvRules
{
  my $envStdFlag=($envRules eq '') ? 1 : 0;
  my $ruleFile=($envStdFlag) ? "$ReqDir${Sep}envrules.std" : $envRules;
  open TMP, "<$ruleFile" or logmsg('F', "Cannot open '$ruleFile'");

  my $skipFlag=1    if $envStdFlag;    # if 'std', need to find right stanza
  my ($index, $type);
  while (my $line=<TMP>)
  {
    next    if $line=~/^#|^\s*$/;
    chomp $line;

    if ($line=~/>(.*)</)
    {
      last           if !$skipFlag;    # already found so we're now done
      my $stanza=$1;
      $skipFlag=0    if $stanza=~/$ProductName/;
      print "Found '$ProductName' in envrules.std\n"    if $debug & 1 && !$skipFlag;
      next
    }
    next    if $skipFlag;

    if ($line eq '[pre]' || $line eq '[post]' || $line eq '[ignore]')
    {
      $line=~/(pre|post|ignore)/;
      $type=$1;
      $index=0;
      next;
    }

    if (!defined($type))
    {
      logmsg('E', "Ignoring '$line' in '$envRules' which preceeds [pre] or [post] entry");
      next;
    }

    # We need to append something to the end of the regx or a null replacement string
    # will result in '$f2' being undefined
    my ($f1, $f2)=(split(/\//, $line.'x'))[1,2];
    if (!defined($f1) || !defined($f2))
    {
      logmsg('E', "Ignoring '$line' in '$envRules' which does not look like a perl regx");
      next;
    }

    $ipmiFile->{$type}->[$index]->{f1}=$f1;
    $ipmiFile->{$type}->[$index]->{f2}=$f2;
    $index++;
  }
  close TMP;
}

##################################################
#    These are MUCH faster than the linux commands
#    since we don't have to start a new process!
##################################################

sub cat
{
  my $file=shift;
  my $eof= shift;
  my $temp;

  if (!open CAT, "<$file")
  {
    logmsg("W", "Can't open '$file'");
    $temp='';
  }
  else
  {
    # if 'eof' set, return entire file, otherwise just 1st line.
    while (my $line=<CAT>)
    {
      $temp.=$line; 
      last    if !defined($eof);
    }
    close CAT;
  }
  return($temp);
}

sub ls
{
  my @dirs;
  opendir DIR, $_[0];
  while (my $line=readdir(DIR))
  {
    next    if $line=~/^\./;
    push @dirs, $line;
  }
  close DIR;
  return(@dirs);
}

1;
