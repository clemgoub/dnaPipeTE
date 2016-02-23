#!/usr/bin/perl -w

# Copyright 2003-2012 Hewlett-Packard Development Company, L.P. 
#
# collectl may be copied only under the terms of either the Artistic License
# or the GNU General Public License, which may be found in the source kit

# debug
#    1 - print interesting stuff
#    2 - print Interconnect specific checks (mostly Infiniband)
#    4 - show each line processed by record(), replaces -H
#    8 - print lustre specific checks
#   16 - print headers of each file processed
#   32 - skip call to dataAnalyze during interactive processing
#   64 - socket processing
#  128 - show collectl.conf processing
#  256 - show detailed pid processing (this generates a LOT of output)
#  512 - show more pid details, specifically hash contents
#        NOTE - output from 256/512 are prefaced with %%% if from collectl.pl
#               and ### if from formatit.ph
# 1024 - show list of SLABS to be monitored
# 2048 - playback preprocessing 
# 4096 - report pidNew() management of pidSkip{}
# 8192 - show creation of RAW, PLOT and files

# debug tricks
# - use '-d36' to see each line of raw data as it would be logged but not 
#   generate any other output

# Equivalent Utilities
#  -s c      mpstat, iostat -c, vmstat
#  -s C      mpstat
#  -s d/D    iostat -d
#  -s f/F    nfsstat -c/s [c if -o C]
#  -s i      sar -v
#  -s m      sar -rB, free, vmstat (note - sar does pages by pagesizsie NOT bytes)
#  -s n/N    netstat -i
#  -s s      sar -n SOCK
#  -s y/Y    slabtop
#  -s Z      ps or top

# Subsystems
#  b - buddy
#  c - cpu
#  d - disks
#  E - environmental
#  i - inodes (and other file stuff)
#  f - NFS
#  l - lustre
#  m - memory
#  n - network
#  s - socket
#  t - tcp
#  x - interconnect
#  Z - processes (-sP now available but -P taken!)

use POSIX;
use Config;
use English;
use 5.008000;
use Getopt::Long;
Getopt::Long::Configure ("bundling");
Getopt::Long::Configure ("no_ignore_case");
Getopt::Long::Configure ("pass_through");
use File::Basename;
use Time::Local;
use IO::Socket;
use IO::Select;

$Cat=          '/bin/cat';
$Grep=         '/bin/grep';
$Egrep=        '/bin/egrep';
$Ps=           '/bin/ps';
$Rpm=          '/bin/rpm';
$Lspci=        '/sbin/lspci';
$Lctl=         '/usr/sbin/lctl';
$Dmidecode=    '/usr/sbin/dmidecode';
$ReqDir=       '/usr/share/collectl';    # may not exist

%TopProcTypes=qw(vsz '' rss '' syst '' usrt '' time '' accum '' rkb '' wkb '' iokb ''
                 rkbc '' wkbc '' iokbc '' ioall '' rsys '' wsys '' iosys  ''
                 iocncl '' majf '' minf '' flt '' pid '' cpu '' thread '' vctx '' nctx '');
%TopSlabTypes=qw(numobj '' name '' actobj '' objsize '' numslab '' objslab '' totsize '' totchg '' totpct '');

# Constants and removing -w warnings
$miniDateFlag=0;
$PageSize=0;
$Memory=$Swap=$Hyper=$Distro=$ProductName='';
$CpuVendor=$CpuMHz=$CpuCores=$CpuSiblings=$CpuNodes='';
$PidFile='/var/run/collectl.pid';    # default, unless --pname
$PQuery=$PCounter=$VStat=$VoltaireStats=$IBVersion=$HCALids=$OfedInfo='';
$numBrwBuckets=$cfsVersion=$sfsVersion='';
$Resize=$IpmiCache=$IpmiTypes=$ipmiExec='';
$i1DataFlag=$i2DataFlag=$i3DataFlag=0;
$lastSecs=$interval2Print=0;
$diskRemapFlag=$diskChangeFlag=$cpuDisabledFlag=$cpusDisabled=$cpusEnabled=$noCpusFlag=0;
$boottime=0;

# only used once here, but set in formatit.ph
our %netSpeeds;

# Find out ASAP if we're linux or WNT based as well as whether or not XC based
$PcFlag=($Config{"osname"}=~/MSWin32/) ? 1 : 0;
$XCFlag=(!$PcFlag && -e '/etc/hptc-release') ? 1 : 0;

# If we ever want to write something to /var/log/messages, we need this which
# we obviously can't include on a pc.
require "Sys/Syslog.pm"    if !$PcFlag;

# Always nice to know if we're root
$rootFlag=(!$PcFlag && `whoami`=~/root/) ? 1 : 0;
$SrcArch= $Config{"archname"};

$Version=  '3.6.7-1';
$Copyright='Copyright 2003-2012 Hewlett-Packard Development Company, L.P.';
$License=  "collectl may be copied only under the terms of either the Artistic License\n";
$License.= "or the GNU General Public License, which may be found in the source kit";

# get the path to the exe from the program location, noting different handling
# of path resolution for XC and non-XC, noting if a link and not XC, we
# need to follow it, possibly multiple times!  Furthermore, if the link is
# a relative one, we need to prepend with the original program location or
# $BinDir will be wrong.
if (!$XCFlag)
{
  $link=$0;
  $ExeName='';
  until($link eq $ExeName)
  {
    $ExeName=$link;    # possible exename
    $link=(!defined(readlink($link))) ? $link : readlink($link);
  }
}
else
{
  $ExeName=(!defined(readlink($0))) ? $0 : readlink($0);
  $ExeName=dirname($0).'/'.$ExeName    if $ExeName=~/^\.\.\//;
}

$BinDir=dirname($ExeName);
$Program=basename($ExeName);
$Program=~s/\.pl$//;    # remove extension for production

# Note that if someone redirects stdin or runs it out of a script it will look like 
# we're in the background.  We also need to know if STDOUT connected to a terminal.
if (!$PcFlag)
{
  $MyDir=`pwd`;
  $Cat=  'cat';
  $Sep=  '/';
  $backFlag=(getpgrp()!=tcgetpgrp(0)) ? 1 : 0;
  $termFlag= (-t STDOUT) ? 1 : 0;
}
else
{
  $MyDir=`cd`;
  $Cat=  'type';
  $Sep=  '\\';
  $backFlag=0;
  $termFlag=0;
}
chomp $MyDir;

# This is a little messy.  In playback mode of process data, we want to use
# usernames instead of UIDs, so we need to know if we need to know if it's
# the same node and hence we need our name.  This could be different than $Host
# which was recorded with the data file and WILL override in playback mode. 
# We also need our host name before calling initRecord() so we can log it at 
# startup as well as for naming the logfile.
$myHost=($PcFlag) ? `hostname` : `/bin/hostname`;
$myHost=(split(/\./, $myHost))[0];
chomp $myHost;
$Host=$myHost;

# may be overkill, but we want to throttle max errors/day to prevent runaway.
$zlibErrors=0;

# These variables only used once in this module and hence generate warnings
undef @dskOrder;
undef @netOrder;
undef @lustreCltDirs;
undef @lustreCltOstDirs;
undef @lustreOstSubdirs;
undef %playbackSettings;
$recHdr1=$recHeader=$miniDateTime=$miniFiller=$DaemonOptions='';
$OstNames=$MdsNames=$LusDiskNames=$LusDiskDir='';
$NumLustreCltOsts=$NumLusDisks=$MdsFlag=0;
$NumSlabs=$SlabGetProc=$newSlabFlag=0;
$wideFlag=$coreFlag=$newRawSlabFlag=0;
$totalCounter=$separatorCounter=0;
$NumCpus=$HZ='';
$NumOst=$NumBud=0;
$FS=$ScsiInfo=$HCAPortStates='';
$SlabVersion=$XType=$XVersion='';
$dentryFlag=$inodeFlag=$filenrFlag=$allThreadFlag=$procCmdWidth=0;
$clr=$clscr=$cleol=$home='';
$dskIndexNext=$netIndexNext=0;

# This tells us we have not yet made our first pass through the data
# collection loop and gets reset to 0 at the bottom.
$firstPass=1;

# Check the switches to make sure none requiring -- were specified with -
# since getopts doesn't!  Also save the list of switches we were called with.
$cmdSwitches=preprocSwitches();

# These are the defaults for interactive and daemon subsystems
$SubsysDefInt='cdn';
$SubsysDefDaemon='bcdfijlmnstx';

# We want to load any default settings so that user can selectively 
# override them.  We're giving these starting values in case not
# enabled in .conf file.  We later override subsys if interactive
$SubsysDef=$SubsysCore=$SubsysDefDaemon;
$Interval=     10;
$Interval2=    60;
$Interval3=   120;
$LimSVC=       30;
$LimIOS=       10 ;
$LimLusKBS=   100;
$LimLusReints=1000;
$LimBool=       0;
$Port=       2655;
$Timeout=      10;
$MaxZlibErrors=20;
$LustreSvcLunMax=10;
$LustreMaxBlkSize=512;
$LustreConfigInt=1;
$InterConnectInt=900;
$TermHeight=24;
$DefNetSpeed=10000;
$IbDupCheckFlag=1;
$TimeHiResCheck=1;
$PasswdFile='/etc/passwd';
$umask='';
$DiskMaxValue=-1;    # disabled

# NOTE - the following line should match what is in collectl.conf.  If uncommented there, it will be replaced
$DiskFilter='cciss/c\d+d\d+ |hd[ab] | sd[a-z]+ |dm-\d+ |xvd[a-z] |fio[a-z]+ | vd[a-z]+ |emcpower[a-z]+ |psv\d+ ';
$DiskFilterFlag=0;   # only set when filter set in collectl.conf
$ProcReadTest='yes';

# Standard locations
$SysIB='/sys/class/infiniband';

# These aren't user settable but are needed to build the list of ALL valid
# subsystems
$SubsysDet=   "BCDEFJLMNTXYZ";
$SubsysExcore='y';

# These are the subsystems allowed in brief mode
$BriefSubsys="bcdfijlmnstx";

# And the default environmentals
$envOpts='fpt';
$envRules='';
$envDebug=0;
$envTestFile='';
$envFilt=$envRemap='';

$hiResFlag=0;    # must be initialized before ANY calls to error/logmsg
$configFile='';
$ConfigFile='collectl.conf';
$daemonFlag=$debug=$formatitLoaded=0;
GetOptions('C=s'      => \$configFile,
           'D!'       => \$daemonFlag,
           'd=i'      => \$debug,
           'config=s' => \$configFile,
           'daemon!'  => \$daemonFlag,
           'debug=i'  => \$debug
           ) or error("type -h for help");

# if config file specified and a directory, prepend to default name otherwise
# use the whole thing as the name.
$configFile.="/$ConfigFile"    if $configFile ne '' && -d $configFile;;
loadConfig();

# Very unlikely but I hate programs that silently exit.  We have to figure out
# where formatit.ph lives, out first choice always being '$BinDir'.
$filename='';
$BinDir=dirname($ExeName);
if (!-e "$BinDir/formatit.ph" && !-e "$ReqDir/formatit.ph")
{
  # Let's not get too carried away for something that probably won't ever happen on a PC,
  # but there's no point displaying $ReqDir since it in unix format and will never exist!
  my $msg=sprintf("can't find 'formatit.ph' in '$BinDir'%s.  Corrupted installation!", !$PcFlag ? " OR '$ReqDir'" : '');
  print "$msg\n";    # can't call logmsg() before formatit.ph not yet loaded
  logsys($msg,1);    # force it because $filename not yet set
  exit(1);
}

# Now that we've loaded collectl.conD and have possibly reset '$ReqDir', it's time to
# load it, changing $ReqDir to $BinDir if we find it there.
$ReqDir=$BinDir    if -e "$BinDir/formatit.ph";
print "BinDir: $BinDir  ReqDir: $ReqDir\n"    if $debug & 1;

# Load include files and optional PMs if there
require "$ReqDir/formatit.ph";
$zlibFlag=     (eval {require "Compress/Zlib.pm" or die}) ? 1 : 0;
$hiResFlag=    (eval {require "Time/HiRes.pm" or die}) ? 1 : 0;
$diskRemapFlag=(eval {require "$ReqDir/diskremap.ph" or die}) ? 1 : 0;
$formatitLoaded=1;

# These can get overridden after loadConfig(). Others can as well but this is 
# a good place to reset those that don't need any further manipulation
$limSVC=$LimSVC;
$limIOS=$LimIOS;
$limBool=$LimBool;
$limLusKBS=$LimLusKBS;
$limLusReints=$LimLusReints;
$termHeight=$TermHeight;

# On LINUX and only if associated with a terminal in the foreground and we can find 'resize',
# use the value of LINES to set the terminal height
if (!$PcFlag && !$daemonFlag && !$backFlag && $Resize ne '' && $termFlag && defined($ENV{TERM}) && $ENV{TERM}=~/xterm/)
{
  # IF the user typed a CR after collectl started but before it started, flush input buffer
  my $selTemp=new IO::Select(STDIN);
  while ($selTemp->can_read(0))
  { my $temp=<STDIN>; }
  $selTemp->remove();

  `$Resize`=~/LINES.*?(\d+)/m;
  $termHeight=$1;
}

# let's also see if there is a terminal attached.  this is currently only 
# an issue for 'brief mode', but we may need to know some day for other
# reasons too.  but PCs can only run on a terminal...
$termFlag=(open TMP, "</dev/tty") ? 1 : 0;
$termFlag=0    if $daemonFlag;
$termFlag=1    if $PcFlag;
close TMP;

$count=-1;
$numTop=0;
$briefFlag=1;
$showColFlag=$showMergedFlag=$showHeaderFlag=$showSlabAliasesFlag=$showRootSlabsFlag=0;
$verboseFlag=$vmstatFlag=$alignFlag=$whatsnewFlag=0;
$quietFlag=$utcFlag=$statsFlag=0;
$address=$flush=$fileRoot=$statOpts='';
$limits=$lustreSvcs=$runTime=$playback=$playbackFile=$rollLog='';
$groupFlag=$tworawFlag=$msgFlag=$niceFlag=$plotFlag=$nohupFlag=$wideFlag=$rawFlag=$ioSizeFlag=0;
$userOptions=$userInterval=$userSubsys='';
$import=$export=$expName=$expOpts=$topOpts=$topType='';
$impNumMods=0;  # also acts as a flag to tell us --import code loaded
$homeFlag=$rawtooFlag=$tworaw=$tworaw=$autoFlush=$allFlag=0;
$procOpts=$procFilt=$procState='';
$slabOpts=$slabFilt='';
$procAnalFlag=$procAnalCounter=$slabAnalFlag=$slabAnalCounter=$lastInt2Secs=0;
$lastLogPrefix=$passwdFile='';
$memOpts=$nfsOpts=$nfsFilt=$lustOpts=$userEnvOpts='';
$grepPattern=$pname='';
$dskFilt=$netFilt=$tcpFilt='';
$cpuOpts=$dskOpts=$netOpts=$xOpts='';
$utimeMask=0;
$comment=$runas='';
$rawDskFilter=$rawDskIgnore=$rawNetFilter=$rawNetIgnore='';
$tcpFiltDefault='ituc';

my ($extract,$extractMode)=('',0);

# Since --top has optionals arguments, we need to see if it was specified without
# one and stick in the defaults noting -1 means to use the window size for size
$topFlag=0;
$plotFlag=0;
for (my $i=0; $i<scalar(@ARGV); $i++)
{
  $plotFlag=1   if $ARGV[$i]=~/-P|--plo/;    # see if -P specified for setting --hr below

  if ($ARGV[$i]=~/--to/)
  {
    $topFlag=1;
    splice(@ARGV, $i+1, 0, 'time,-1')    if $i==(scalar(@ARGV)-1) || $ARGV[$i+1]=~/^-/;
    last;
  }
}

$scrollEnd=0;
$headerRepeat=(!$topFlag) ? $termHeight-2 : 5;
$headerRepeat=0     if $plotFlag;

# now that we've made it through first call fo Getopt, disable pass_through so
# we can catch any errors in parameter names.
Getopt::Long::Configure('no_pass_through');
GetOptions('align!'     => \$alignFlag,
           'A=s'        => \$address,
           'address=s'  => \$address,
	   'c=i'        => \$count,
           'count=i'    => \$count,
	   'f=s'        => \$filename,
   	   'filename=s' => \$filename,
           'F=i'        => \$flush,
           'flush=i'    => \$flush,
           'G!'         => \$groupFlag,
           'group!'     => \$groupFlag,
	   'tworaw!'    => \$tworawFlag,
           'home!'      => \$homeFlag,
           'i=s'        => \$userInterval,
           'interval=s' => \$userInterval,
	   'h!'         => \$hSwitch,
           'help!'      => \$hSwitch,
           'iosize!'    => \$ioSizeFlag,
           'l=s'        => \$limits,
           'limits=s'   => \$limits,
	   'L=s'        => \$lustreSvcs,
	   'lustsvcs=s' => \$lustreSvcs,
	   'm!'         => \$msgFlag,
           'messages!'  => \$msgFlag,
           'o=s'        => \$userOptions,
           'options=s'  => \$userOptions,
	   'N!'         => \$niceFlag,
           'nice!'      => \$niceFlag,
           'nohup!'     => \$nohupFlag,
           'passwd=s'   => \$passwdFile,
	   'p=s'        => \$playback,
           'playback=s' => \$playback,
	   'P!'         => \$plotFlag,
           'quiet!'     => \$quietFlag,
           'plot!'      => \$plotFlag,
	   'r=s'        => \$rollLog,
           'rolllogs=s' => \$rollLog,
	   'R=s'        => \$runTime,
           'runtime=s'  => \$runTime,
           's=s'        => \$userSubsys,
           'sep=s'      => \$SEP,
           'stats!'     => \$statsFlag,
           'statopts=s' => \$statOpts,
           'subsys=s'   => \$userSubsys,
	   'top=s'      => \$topOpts,
           'utc!'       => \$utcFlag,
           'umask=s'    => \$umask,
           'utime=i'    => \$utimeMask,
	   'v!'         => \$vSwitch,
           'version!'   => \$vSwitch,
	   'V!'         => \$VSwitch,
           'showdefs!'  => \$VSwitch,
	   'w!'         => \$wideFlag,
           'x!'         => \$xSwitch,
           'helpextend!'=> \$xSwitch,
           'X!'         => \$XSwitch,
           'helpall!'   => \$XSwitch,
	   'slabfilt=s' => \$slabFilt,
	   'procfilt=s' => \$procFilt,

           'all!'          => \$allFlag,
           'comment=s'     => \$comment,
           'cpuopts=s'     => \$cpuOpts,
           'dskfilt=s'     => \$dskFilt,
           'dskopts=s'     => \$dskOpts,
           'export=s'      => \$export,
	   'from=s'        => \$from,
	   'thru=s'        => \$thru,
	   'headerrepeat=i'=> \$headerRepeat,
           'hr=i'          => \$headerRepeat,
	   'import=s'      => \$import,
           'lustopts=s'    => \$lustOpts,
	   'memopts=s'     => \$memOpts,
           'netfilt=s'     => \$netFilt,
	   'netopts=s'     => \$netOpts,
           'nfsopts=s'     => \$nfsOpts,
           'nfsfilt=s'     => \$nfsFilt,
           'envopts=s'     => \$userEnvOpts,
           'envrules=s'    => \$envRules,
           'envdebug!'     => \$envDebug,
           'envtest=s'     => \$envTestFile,
           'envfilt=s'     => \$envFilt,
           'envremap=s'    => \$envRemap,
           'extract=s'     => \$extract,
           'grep=s'        => \$grepPattern,
           'offsettime=s'  => \$offsetTime,
           'pname=s'       => \$pname,
           'procanalyze!'  => \$procAnalFlag,
	   'procopts=s'    => \$procOpts,
           'procstate=s'   => \$procState,
           'rawtoo!'       => \$rawtooFlag,
           'rawdskfilter=s'=> \$rawDskFilter,
	   'rawdskignore=s'=> \$rawDskIgnore,
           'rawnetfilter=s'=> \$rawNetFilter,
	   'rawnetignore=s'=> \$rawNetIgnore,
           'runas=s'       => \$runas,
           'showsubsys!'   => \$showSubsysFlag,
           'showoptions!'  => \$showOptionsFlag,
           'showsubopts!'  => \$showSuboptsFlag,
           'showtopopts!'  => \$showTopoptsFlag,
	   'showheader!'   => \$showHeaderFlag,
           'showcolheaders!'  =>\$showColFlag,
	   'showslabaliases!' =>\$showSlabAliasesFlag,
	   'showrootslabs!'   =>\$showRootSlabsFlag,
           'slabanalyze!'  => \$slabAnalFlag,
	   'slabopts=s'    => \$slabOpts,
	   'tcpfilt=s'     => \$tcpFilt,
           'verbose!'      => \$verboseFlag,
           'vmstat!'       => \$vmstatFlag,
           'whatsnew!'     => \$whatsnewFlag,
           'xopts=s'       => \$xOpts,
           ) or error("type -h for help");

# This needs to be done BEFORE processing --pname since we end up changing $PidFile
if ($runas ne '')
{
  error("canot use --runas without -D")    if !$daemonFlag;

  # temporariluy disable daemon mode in debug mode so we can see messages on terminal.
  $daemonFlag=0    if $debug;

  my ($runasUser,$runasGroup)=split(/:/, $runas);
  error("--runas must at least specify a user")   if $runasUser eq '';

  if ($runasUser!~/^\d+$/)
  {
    $runasUid=(split(/:/, `grep $runasUser /etc/passwd`))[2];
    error("can't find '$runasUser' in /etc/passwd.  Consider UID.")    if !defined($runasUid);
  }
  if (defined($runasGroup) && $runasGroup!~/^\d+$/)
  {
    $runasGid=(split(/:/, `grep $runasGroup /etc/group`))[2];
    error("can't find '$runasGroup' in /etc/group.  Consider GID.")    if !defined($runasGid);
  }
  $runasUid=$runasUser     if $runasUser=~/^\d+/;
  $runasGid=$runasGroup    if defined($runasGroup) && $runasGroup=~/^\d+/;

  # let's make sure the owner/group of the logging directory match
  my $logdir=dirname("$filename/collectl");
  ($uid,$gid)=(stat($logdir))[4,5];

  error("Ownership of '$logdir' doesn't match '$runas'")
      if ($uid!=$runasUid) || (defined($runasGid) && $gid!=$runasGid);

  # Daemon also means --nohup
  $daemonFlag=$nohupFlag=1;
}

if ($pname ne '')
{
  # We need to include switches because collectl-generic expects to find them in the process name
  $0="collectl-$pname $cmdSwitches";
  $PidFile=~s/collectl\.pid/collectl-$pname.pid/;
  print "Set PName to collectl-$pname\n"    if $debug & 1;
}

#    O p e n    A    S o c k e t  ?

# It's real important we do this as soon as possible because if someone runs
# us in 'client' mode, and an error occurs the server would still be hanging
# around waiting for someone to connect to that socket!  This way we connect,
# report the error and exit and the caller is able to detect it.

$sockFlag=$clientFlag=$serverFlag=0;
if ($address ne '')
{
  if ($address=~/\./)
  {
    ($address,$port,$timeout)=split(/:/, $address);
    $port=$Port    if !defined($port) || $port eq '';
    $Timeout=$timeout    if defined($timeout);

    $socket=new IO::Socket::INET(
        PeerAddr => $address,
        PeerPort => $port,
        Proto    => 'tcp',
        Timeout  => $Timeout) or
              error("Could not create socket to $address:$port.  Reason: $!")
        if !defined($socket);
    print "Socket opened on $address:$port\n"    if $debug & 64;
    push @sockets, $socket;
    $clientFlag=1;
  }
  elsif ($address=~/^server/i)
  {
    ($port, $port, $options)=split(/:/, $address, 3);
    $port=$Port    if !defined($port);

    # Note this socket uses a different variable because when we get
    # a connection we use the SAME one to talk to client as we do in
    # client mode.
    $sockServer = new IO::Socket::INET(
        Type=>SOCK_STREAM,
        Reuse=>1, Listen => 1,
        LocalPort => $port) ||
             error("Could not create local socket on port $port  Reason: $!");
    print "Server socket opened on port $port\n"    if $debug & 64;
    $select=new IO::Select($sockServer);
    $serverFlag=1;
  }
  else
  {
    logmsg('F', 'Invalid -A option');
  }
  $sockFlag=1;
}

# I'm probably the only one who cares, but in -p --top -s, don't default 
# to a --hr of 5, use 20
$headerRepeat=20    if $topFlag && $playback ne '' && $headerRepeat==5;

# If we used to trap these before we opened the socket, but then we couldn't
# send the message back to the called cleanly!
if ($sockFlag)
{
  error("-p not allowed with -A")           if $playback ne '';
  error("-D not allowed with -A address")   if $daemonFlag && !$serverFlag;
}

# Since the output could be intended for a socket (called from colgui/colmux),
# we need to do after we open the socket.
error()            if $hSwitch;
showVersion()      if $vSwitch;
showDefaults()     if $VSwitch;
extendHelp()       if $xSwitch;
showSubsys()       if $showSubsysFlag;
showOptions()      if $showOptionsFlag;
showSubopts()      if $showSuboptsFlag;
showTopopts()      if $showTopoptsFlag;
showSlabAliases($slabFilt)  if $showSlabAliasesFlag || $showRootSlabsFlag;
whatsnew()         if $whatsnewFlag;

if ($XSwitch)
{
  extendHelp(1);
  showSubsys(1);
  showOptions(1);
  showSubopts(1);
  showTopopts(1);
  printText("$Copyright\n");
  printText("$License\n");
  exit(0);
}

# in playback mode all we're really doing is verifying the options
setNFSFlags($nfsFilt);

if ($vmstatFlag)
{
  error("can't mix --vmstat with --export")    if $vmstatFlag && $export ne '';
  error("can't mix --vmstat with --all")       if $vmstatFlag && $allFlag;
  $export='vmstat';
}

error("can't use --export with --verbose")    if $verboseFlag && $export ne '';
error("can't use -P with --verbose")          if $verboseFlag && $plotFlag;
error("can't use -f with --verbose")          if $verboseFlag && $filename ne '';
error("--utime requires HiRes timer")         if $utimeMask && !$hiResFlag;
error("--utime requires -f")                  if $utimeMask && $filename eq '';
error("max value for --utime is 7")           if $utimeMask>7;

# --all is shortcut for all summary data
if ($allFlag)
{
  error("can't mix -s with -all")    if $userSubsys ne '';
  $userSubsys="$SubsysCore$SubsysExcore";
  $userSubsys=~s/y//;
}

# As part of the conversion to getopt::long, we need to know the actual switch
# values as entered by the user.  Those are stored in '$userXXX' and then that
# is treated as one used to handle opt_XXX.
$options= $userOptions;
$interval=($userInterval ne '') ? $userInterval : $Interval;
$subsys=  ($userSubsys ne '')   ? $userSubsys   : $SubsysCore;

error('invalid value for --lustopts')                     if $lustOpts ne '' && $lustOpts!~/^[BDMOR]+$/;
error('invalid value for --nfsopts')                      if $nfsOpts ne '' && $nfsOpts ne 'z';
error('invalid value for --memopts')                      if $memOpts ne '' && $memOpts!~/^[pPsRV]+$/;
error('--memopts R cannot be user with any of [psPV]')    if $memOpts=~/R/  && $memOpts=~/[psPV]/;
error("--tcpfilt only applies to -st or -sT")             if $tcpFilt ne '' && $subsys!~/t/i;
error("only valid --tcpopts values are 'cituIT'")         if $tcpFilt ne '' && $tcpFilt!~/^[cituIT]+$/; 
$tcpFilt=$tcpFiltDefault    if $tcpFilt eq '' && $playback eq '';

# NOTE - technically we could allow fractional polling intervals without
# HiRes, but then we couldn't properly report the times.
if ($interval=~/\./ && !$hiResFlag)
{
  $interval=int($interval+.5);
  $interval=1    if $interval==0;
  print "need to install HiRes to use fractional intervals, so rounding to $interval\n";
}

# ultimately we only use when doing process data
error("password file '$passwdFile' doesn't exist")    if $passwdFile ne '' && !-e $passwdFile;
$passwdFile=$PasswdFile    if $passwdFile eq '';

#    S u b s y s  /  I n t e r v a l    R e s o l u t i o n

# This needs to get done as soon a possible...
# Set default interval and subsystems for interactive mode unless already
# set, noting the default values above are for daemon mode.  To be consistent,
# we also need to reset $Interval and $SubsysDef noting if one sets a
# secondary interval but not the primary, we need to prepend it with 1 and
# keep the secondary
if (!$daemonFlag)
{
  $interval=$Interval=1    if $userInterval eq '' && !$showColFlag;
  if ($showColFlag)
  {
    error('-c conflicts with --showcolheaders')     if $count!=-1;
    error('-i conflicts with --showcolheaders')     if $userInterval ne '';
    $interval=0;
    $interval='0:0'     if $subsys=~/[YZ]/;
    $interval='0:0:0'   if $subsys=~/E/;
    $quietFlag=1;    # suppress 'waiting...' startup message
  }

  if ($userInterval ne '' && $userInterval=~/^(:.*)/)
  {
    $interval="1$userInterval";
    $Interval=1;
  }

  $SubsysDef=$SubsysDefInt;
  $subsys=$SubsysDef       if $userSubsys eq '';
}

# subsystems  - must preceed +
# special option -s-all disables ALL subsystems which is basically the only way to
# disable all subsystems when you want to play back one or more explicit imports
# so we need to to allow if the ONLY thing that follows -s
error("+/- must start -s arguments if used")    if $subsys=~/[+-]/ && $subsys!~/^[+-]/;
error("-s-all only allowed with -p")            if $subsys eq '-all' && $playback eq '';
error("invalid subsystem '$subsys'")            if $userSubsys ne '-all' && $subsys!~/^[-+$SubsysCore$SubsysExcore$SubsysDet]+$/;
$subsys=mergeSubsys($SubsysDef);

# note that -p, --procanalyze, --slabanalyze and --top can change $subsys
# also be sure to note if the user typed --verbose
$userVerbose=$verboseFlag;
setOutputFormat();

# switch validations once we know whether brief or verbose
error("only choose 1 of -oA and --stats")         if $statsFlag>1;
error("statistics not allowed in verbose mode")   if $statsFlag && $verboseFlag;
error("statistics not allowed interactively")     if $statsFlag && $playback eq '';
error("--statopts required --stats")              if $statOpts ne '' && !$statsFlag;
error("valid --statopts are [ais]")               if $statOpts ne '' && $statOpts!~/[ais]/;
$headerRepeat=0    if $statsFlag && $statOpts!~/i/;    # force single header line when not including interval data

#    S p e c i a l    F o r m a t s

if ($procAnalFlag || $slabAnalFlag)
{
  error("--procanalyze/--slabanalyze require -p")              if $playback eq '';
  error("--procanalyze/--slabanalyze require -f")              if $filename eq '';
  error("--procanalyze/--slabanalyze do not support --utc")    if $utcFlag;
  error("sorry, but no + or - with -s and analyze mode")       if $userSubsys=~/[+-]/;

  # No default from playback file in this mode, so go by whatever user 
  # specificed with -s and if no Y/Z, stick one in there and then make
  # user $userSubsys and $subsys agree so initFormat() won't diddle
  # the values.
  $slabAnalOnlyFlag=($slabAnalFlag && $userSubsys!~/Y/) ? 1 : 0;
  $procAnalOnlyFlag=($procAnalFlag && $userSubsys!~/Z/) ? 1 : 0;

  $userSubsys.='Y'    if $slabAnalOnlyFlag;
  $userSubsys.='Z'    if $procAnalOnlyFlag;
  $subsys=$userSubsys;
  $plotFlag=1;
}

# We have to wait for '$subsys' to be defined before handling top and it
# felt right to keep the code together with --procanalyze/--slabanalyze.

# --top forces $homeFlag if not in playback mode.  if no process interval
# specified set it to the monitoring one.
$temp=$SubsysDet;
$temp=~s/YZ//;
$detailFlag=($subsys=~/[$temp]/) ? 1 : 0;
if ($topOpts ne '')
{
  # Don't diddle original setting in '$userSubsys', use a copy!
  # Subtle - the verbose flag wouldn't have been set if ONLY processes or slabs and 
  # it should be.  Similarly, Y/Z should not be considered when looking to see is 
  # same columns in verbose mode.
  my $tempSubsys=$userSubsys;
  $tempSubsys=~s/[YZ]//g;
  $verboseFlag=1     if $tempSubsys eq '';
  $sameColsFlag=1    if $verboseFlag && length($tempSubsys)==1;
  $briefFlag=($verboseFlag) ? 0 : 1;

  my $subsysSize=0;
  if ($tempSubsys ne '' && $playback eq '')
  {
    if (!$verboseFlag || $sameColsFlag)
    {
      # in brief or single-subsys verbose mode the area size if fixed by --hr
      $subsysSize=$headerRepeat+2;
    }
    else
    {
      # multi-subsys verbose mode is driven by the number of subsystems but if 
      # there are any details, it's up to the users choice of --hr
      $subsysSize=length($tempSubsys)*3;
      $subsysSize++                if $tempSubsys=~/m/;
      $subsysSize=$headerRepeat    if $detailFlag;
    }
    $scrollEnd=$subsysSize+1;
  }

  ($topType, $numTop)=split(/,/, $topOpts);
  $topType='time'          if $topType eq '';

  # enough of these to warrant setting a flag
  $topIOFlag=($topType=~/io|kb|sys$|cncl/) ? 1 : 0;

  $termHeight=12    if $playback ne '';
  $numTop=$termHeight-$scrollEnd-2    if !defined($numTop) || $numTop==-1;
  #print "HEIGHT: $termHeight  SUBSIZE: $subsysSize  HR: $headerRepeat NUMTOP: $numTop\n";

  $topProcFlag=(defined($TopProcTypes{$topType})) ? 1 : 0;
  $topSlabFlag=(defined($TopSlabTypes{$topType})) ? 1 : 0;
  error("not enough lines in window for display")
      if $numTop<1;
  error("invalid --top type.  see --showtopopts for list")
      if $topProcFlag==0 && $topSlabFlag==0;
  error("you cannot select process and slab subsystems in --top mode")
      if ($subsys=~/Y/ && $subsys=~/Z/) || 
         ($subsys=~/Y/ && $topProcFlag) || ($subsys=~/Z/ && $topSlabFlag);

  # if sorting by v/n context switches, force --procopts x if not specified
  $procOpts.='x'    if $topType=~/vctx|nctx/ && $procOpts!~/x/;

  if ($playback eq '')
  {
    $homeFlag=1;
    $subsys=(defined($TopProcTypes{$topType})) ? "${tempSubsys}Z" : "${tempSubsys}Y";
    $interval.=":$interval"    if $interval!~/:/;
  }
}

#    I m p o r t

if ($import ne '')
{
  # Default mode for --import is NO user defined subsystem in interactive mode.
  # All must be explicitly defined
  $subsys=''    if !$daemonFlag && $userSubsys eq '';

  foreach my $imp (split(/:/, $import))
  {
    $impString=$imp;
    $impDetFlag[$impNumMods]=0;
    $impNumMods++;

    # The following chunks based somewhat on --export code, except OPTS is a string
    ($impName, $impOpts)=split(/,/, $impString, 2);
    $impName.=".ph"    if $impName!~/\./;

    # If the import file itself doesn't exist in current directory, try $ReqDir 
    my $tempName=$impName;
    $impName="$ReqDir/$impName"    if !-e $impName;
    if (!-e "$impName")
    {
      my $temp="can't find import file '$tempName' in ./";
      $temp.=" OR $ReqDir/"    if $ReqDir ne '.';
      error($temp)             if !-e "$impName";
    }

    require $impName;

    # the basename is the name of the function and also remove extension.
    $impName=basename($impName);
    $impName=(split(/\./, $impName))[0];

    push @impOpts,         $impOpts;
    push @impInit,         "${impName}Init";
    push @impGetData,      "${impName}GetData";
    push @impGetHeader,    "${impName}GetHeader";
    push @impInitInterval, "${impName}InitInterval";
    push @impIntervalEnd,  "${impName}IntervalEnd";
    push @impAnalyze,      "${impName}Analyze";
    push @impUpdateHeader, "${impName}UpdateHeader";
    push @impPrintBrief,   "${impName}PrintBrief";
    push @impPrintVerbose, "${impName}PrintVerbose";
    push @impPrintPlot,    "${impName}PrintPlot";
    push @impPrintExport,  "${impName}PrintExport";
  }

  # Call REQUIRED initialization routines in reverse so if we have to
  # delete anything we won't have to deal with overlap
  $impSummaryFlag=$impDetailFlag=0;
  for (my $i=($impNumMods-1); $i>=0; $i--)
  {
    my $status=&{$impInit[$i]}(\$impOpts[$i], \$impKey[$i]);
    if ($status==-1)
    {
      splice(@impOpts,         $i, 1);
      splice(@impKey,          $i, 1);
      splice(@impInit,         $i, 1);
      splice(@impGetData,      $i, 1);
      splice(@impGetHeader,    $i, 1);
      splice(@impInitInterval, $i, 1);
      splice(@impIntervalEnd,  $i, 1);
      splice(@impAnalyze,      $i, 1);
      splice(@impUpdateHeader, $i, 1);
      splice(@impPrintBrief,   $i, 1);
      splice(@impPrintVerbose, $i, 1);
      splice(@impPrintPlot,    $i, 1);
      splice(@impPrintExport,  $i, 1);
      $impNumMods--;
      next;
    }

    # We need to know if any module has summary or data in case one one else does
    # and we're in plot format so newlog() will know to open tab file.  This also
    # helps optimize some of the print routines.
    $impSummaryFlag++    if $impOpts[$i]=~/s/;
    $impDetailFlag++     if $impOpts[$i]=~/d/;
  }

  # Reset output formatting based on the modules we just loaded
  print "Reset output flags\n"    if $debug & 1;
  setOutputFormat();
}

#    E x p o r t    M o d u l e s

# since we might want to diddle with things like $subsys or fake out other
# switches, we need to load/initialize things early.  We may also need a
# call to a pre-execution init module later...

if ($export ne '')
{
  # By design, if you specify --export and -f and have a socket open, the exported
  # data goes over the socket and we write either a raw or plot file to the dir
  # pointed to by -f.  If not -P, we always write a raw file
  $rawtooFlag=1    if $sockFlag && $filename ne '' && !$plotFlag;

  $verboseFlag=1;
  ($expName, @expOpts)=split(/,/, $export);
  $expName.=".ph"    if $expName!~/\./;

  # If the export file itself doesn't exist in current directory, try $ReqDir
  my $tempName=$expName;
  $expName="$ReqDir/$expName"    if !-e $expName;
  if (!-e "$expName")
  {
    my $temp="can't find export file '$tempName' in ./";
    $temp.=" OR $ReqDir/"    if $ReqDir ne '.';
    error($temp);
  }
  require $expName;

  # the basename is the name of the function and also remove extension.
  $expName=basename($expName);
  $expName=(split(/\./, $expName))[0];
}

#    S i m p l e    S w i t c h    C h e c k s

$utcFlag=1    if $options=~/U/;

# should I migrate a lot of other simple tests here?
error("you cannot specify -f with --top")                  if $topOpts ne '' && $filename ne '';
error("--home does not apply to -p")                       if $homeFlag && $playback ne '';
error("--envopts M does not apply to -P")                  if $userEnvOpts ne '' && $userEnvOpts=~/M/ && $plotFlag;
error("--envopts are only fptCFMT and/or a number")        if $userEnvOpts ne '' && $userEnvOpts!~/^[fptCFMT0-9]+$/;
error("--envrules does not exist")                         if $envRules ne '' && !-e $envRules;
error("--grep only applies to -p")                         if $grepPattern ne '' && $playback eq '';
error('--headerrepeat must be an integer')                 if $headerRepeat!~/^[\-]?\d+$/;
error('--headerrepeat must be >= -1')                      if $headerRepeat<-1;

error("-i not allowed with -p")                            if $userInterval ne '' && $playback ne '';
error("--rawtoo does not work in playback mode")           if $rawtooFlag && $playback ne '';
error("--rawtoo requires -f")                              if $rawtooFlag && $filename eq '';
error("--rawtoo requires -P or --export")                  if $rawtooFlag && !$plotFlag && $export eq '';
error("--rawtoo and -P requires -f")                       if $rawtooFlag && $plotFlag && $filename eq '';
error("--rawtoo cannot be used with -p")                   if $rawtooFlag && $playback ne '';
error("-ou/--utc only apply to -P format")                 if $utcFlag && !$plotFlag;
error("can't mix UTC time with other time formats")        if $utcFlag && $options=~/[dDT]/;
error("-oz only applies to -P files")                      if $options=~/z/ && !$plotFlag;
error("--sep cannot be a '%'")                             if defined($SEP) && $SEP eq '%';
error("--sep only applies to plot format")                 if defined($SEP) && !$plotFlag;
error("--sep much be 1 character or a number")             if defined($SEP) && length($SEP)>1 && $SEP!~/^\d+$/;

error('--showheader not allowed with -f')                  if $filename ne '' && $showHeaderFlag;
error("--showheader in collection mode only supported on linux")
                                                           if $PcFlag && $playback eq '' && $showHeaderFlag;
error('--showmergedheader not allowed with -f')            if $filename ne '' && $showMergedFlag;
error('--showcolheaders not allowed with -f')              if $filename ne '' && $showColFlag;
error('--showcolheaders -sE can only be run by root')      if $showColFlag && $subsys=~/E/ && !$rootFlag;

error("--align require HiRes time module")                 if $alignFlag && !$hiResFlag;
error('--umask can only be set by root')                   if $umask ne '' && !$rootFlag;

error('-sT can only be used with -f or -P')                if $subsys=~/T/ && !$plotFlag && $filename eq '';

# if user enters --envOpts
if ($userEnvOpts ne '')
{
  # remove ALL ipmi data types if user specified any, then add in ALL user options
  # which could include formatting options
  $envOpts=~s/[fpt]+//g    if $userEnvOpts=~/[fpt]/;
  $envOpts.=$userEnvOpts;
}
$allThreadFlag=($procOpts=~/t/) ? 1 : 0;

# The separator is either a space if not defined or the character supplied if 
# non-numeric.  If it is numeric assume decimal and convert to the associated 
# char code (eg 9=tab).
$SEP=' '                    if !defined($SEP);
$SEP=sprintf("%c", $SEP)    if $SEP=~/\d+/;

# Both kinds of DISK and NETWORK filtering
# Remember, this filter overrides the one in collectl.conf
if ($rawDskFilter ne '')
{
  $DiskFilter=$rawDskFilter;
  $DiskFilterFlag=1;
}

# This is applied AFTER the raw disk records are read and possibly filtered
$dskFiltKeep='';
$dskFiltIgnore='';
my $ignoreFlag=($dskFilt=~s/^\^//) ? 1 : 0;
foreach my $disk (split(/,/, $dskFilt))
{
  $dskFiltIgnore.="|$disk"    if $ignoreFlag;
  $dskFiltKeep.=  "|$disk"    if !$ignoreFlag;
}
$dskFiltKeep=~s/^\|//;
$dskFiltIgnore=~s/^\|//;
print "DskFilt - Ignore: $dskFiltIgnore  Keep: $dskFiltKeep\n"    if $debug & 1;

# Unlike the raw disk filter which uses a flag to decided whether or not to use
# if, if the raw net filter is non-blank its very presence is the flag so nothing
# to set
$netFiltKeep='';
$netFiltIgnore='';
$ignoreFlag=($netFilt=~s/^\^//) ? 1 : 0;
foreach my $net (split(/,/, $netFilt))
{
  $netFiltIgnore.="|$net"    if $ignoreFlag;
  $netFiltKeep.=  "|$net"    if !$ignoreFlag;
}
$netFiltKeep=~s/^\|//;
$netFiltIgnore=~s/^\|//;
print "NetFilt - Ignore: $netFiltIgnore  Keep: $netFiltKeep\n"    if $debug & 1;

error("--dskopts f only applies to -sD")              if $dskOpts=~/f/  && $subsys!~/D/;
error("--dskopts z only applies to -sD")              if $dskOpts=~/z/  && $subsys!~/D/;
error("only valid value for --cpuopts is 'z'")        if $cpuOpts ne '' && $cpuOpts!~/^[z]+$/;
error("only valid values for --dskopts are 'fiz'")    if $dskOpts ne '' && $dskOpts!~/^[fiz]+$/;
error("only valid value for --xopts is 'i'")          if $xOpts ne '' && $xOpts!~/^[i]+$/;

$netOptsW=5;    # minumum width
if ($netOpts ne '')
{
  error("--netopts only applies to -sn or -sN")       if $subsys!~/n/i;
  error("only valid --netopts values are 'eEiw'")     if $netOpts ne '' && $netOpts!~/^[eEiw0-9]+$/;
  if ($netOpts=~/w/)
  {
    error("--netopts -w only applies to -sN")         if $subsys!~/N/;
    error("--netopts w must be followed by width")    if $netOpts!~/w(\d+)/;
    $netOptsW=$1;
    error("--netopts width must be at least 5")       if $netOptsW<5;
  }
}

#    L i n u x    S p e c i f i c

if (!$PcFlag)
{
  # This matches THIS host, but in playback mode will be reset to the target
  $Kernel=`uname -r`;
  chomp $Kernel;
  error("collectl no longer supports 2.4 kernels")    if $Kernel=~/^2\.4/;

  $LocalTimeZone=`date +%z`;
  chomp $LocalTimeZone;

  # Some distros put lspci in /usr/sbin and others in /usr/bin, so take one last look in
  # those before complaining, but only if in record mode AND only if looking at interconnects
  if (!-e $Lspci && $playback eq '' && $subsys=~/x/i)
  {
    $Lspci=(-e '/usr/sbin/lspci') ? '/usr/sbin/lspci' : '/usr/bin/lspci';
    if (!-e "/usr/sbin/lspci" && !-e "/usr/bin/lspci")
    {
      pushmsg('W', "-sx disabled because 'lspci' not in $Lspci or '/usr/sbin' or '/usr/bin'");
      pushmsg('W', "If somewhere else, move it or define in collectl.conf");
      $xFlag=$XFlag=0;
      $subsys=~s/x//ig;
    }
  }

  if (!-e $Dmidecode && $playback eq '')
  {
    # we really only care about the message is doing -sE
    pushmsg('W', "cannot find '$Dmidecode' so can't determine hardware Product Name")    if $subsys=~/E/;
    $Dmidecode='';
    $ProductName='Unknown';
  }

  # Set protections for output files
  umask oct($umask) or error("Couldn't set umask to $umask")    if $umask ne '' && $rootFlag;
}

#    C o m m o n    I n i t i a l i z a t i o n

# We always want to flush terminal buffer in case we're using pipes.
$|=1;

# We need to know where we're logging to so set a couple of flags
$logToFileFlag=0;
$rawFlag=$rawtooFlag;
if ($filename ne '')
{
  $rawFlag=1          if !$plotFlag && $export eq '';
  $logToFileFlag=1    if $rawFlag || $plotFlag;
}
printf "RawFlag: %d PlotFlag: %d Repeat: %d Log2Flag: %d Export: %s\n", 
    $rawFlag, $plotFlag, $headerRepeat, $logToFileFlag, $export    if $debug & 1;

($lustreSvcs, $lustreConfigInt)=split(/:/, $lustreSvcs);
$lustreSvcs=""                      if !defined($lustreSvcs);
$lustreConfigInt=$LustreConfigInt   if !defined($lustreConfigInt);
error("Valid values for --lustsvcs are any combinations of cmoCMO")    
    if $lustreSvcs!~/^[cmo]*$/i;
error("lustre config check interval must be numeric")
    if $lustreConfigInt!~/^\d+$/;

# some restrictions of plot format -- can't send to terminal for slabs or
# processes unless only 1 subsystem selected.  quite frankly I see no reason
# to ever do it but there are so damn many other odd switch combos we might
# as well catch these too.
error("to display on terminal using -sY with -P requires only -sY")
    if $plotFlag && $filename eq '' && $subsys=~/Y/ && length($subsys)>1;
error("to display on terminal using -sZ with -P requires only -sZ")
    if $plotFlag && $filename eq '' && $subsys=~/Z/ && length($subsys)>1;

# No great place to put this, but at least here it's in you face!  There are times 
# when someone may want to automate the running of collectl to playback/convert 
# logs from crontab for the day before and this is the easiest way to do that.
# While we're at it, there may be some other 'early' checks that need to be make
# in playback mode.
if ($playback ne "")
{
  ($day, $mon, $year)=(localtime(time))[3..5];
  $today=sprintf("%d%02d%02d", $year+1900, $mon+1, $day);
  $playback=~s/TODAY/$today/;

  ($day, $mon, $year)=(localtime(time-86400))[3..5];
  $yesterday=sprintf("%d%02d%02d", $year+1900, $mon+1, $day);
  $playback=~s/YESTERDAY/$yesterday/;

  error("sorry, but --procfilt not allowed in -p mode.  consider grep")
      if $procFilt ne '';
  error("sorry, but --slabfilt not allowed in -p mode.  consider grep")
      if $slabFilt ne '';
}

# linux box?
if ($SrcArch!~/linux/)
{
  error("record mode only runs on linux")    if $playback eq "";
  error("-N only works on linux")            if $niceFlag;
}

# daemon mode
if ($daemonFlag)
{
  error("no debugging allowed with -D")      if $debug;
  error("-D requires -f OR -A server")       if $filename eq '' && !$serverFlag;
  error("-p not allowed with -D")            if $playback ne "";

  if (-e $PidFile)
  {
    # see if this pid matches a version of collectl.  If not, we'll overwrite
    # it further on so not to worry, but at least record a warning.
    $pid=`$Cat $PidFile`;
    $command="ps -eo pid,command | $Grep -v grep | $Grep collectl | $Grep $pid";
    $ps=`$command`;
    error("a daemonized collectl already running")    if $ps!~/^\s*$/;
  }
}

# count
if ($count!=-1)
{
  error("-c must be numeric")             if $count!~/^\d+$/;
  error("-c conflicts with -r and -R")    if $rollLog ne "" || $runTime ne "";
  $count++    # since we actually need 1 extra interval
}

if ($limits ne '')
{
  error("-l only makes sense for -s D/L/l")    if $subsys!~/[DLl]/;
  @limits=split(/-/, $limits);
  foreach $limit (@limits)
  {
    error("invalid value for -l: $limit")    
	if $limit!~/^SVC:|^IOS:|^LusKBS:|^LusReints:|^OR|^AND/;
    ($name,$value)=split(/:/, $limit);
    $limBool=0    if $name=~/OR/;
    $limBool=1    if $name=~/AND/;
    next          if $name=~/AND|OR/;
    
    error("-l SVC and IOS only apply to -sD")            if $name!~/^Lus/ && $subsys=~/L/;
    error("-l LusKBS and LusReint only apply to -sL")    if $name=~/^Lus/ && $subsys=~/D/;
    error("limit for $limit not numeric")    if $value!~/^\d+$/;
    $limSVC=$value          if $name=~/SVC/;
    $limIOS=$value          if $name=~/IOS/;
    $limLusKBS=$value       if $name=~/LusKBS/;
    $limLusReints=$value    if $name=~/LusReints/;
  }
}

# options
error("invalid option")    if $options ne "" && $options!~/^[\^12acdDGgimnTuUxXz]+$/g;
error("-oi only supported interactively with -P to terminal")    
    if $options=~/i/ && ($playback ne '' || !$plotFlag || $filename ne '');
$miniDateFlag=($options=~/d/i) ? 1 : 0;
$miniTimeFlag=($options=~/T/)  ? 1 : 0;
error("use only 1 of -o dDT") 
    if ($miniDateFlag && $miniTimeFlag) || ($options=~/d/ && $options=~/D/);
error("--home only applies to terminal output")
                             if $homeFlag && $filename ne "";
error("--home cannot be used with -A")
                             if $homeFlag && $sockFlag;
error("option $1 only apply to -P")
                             if !$plotFlag && $options=~/([12ac])/;
error("-oa conflicts with -oc") 
                             if $options=~/a/ && $options=~/c/;
error("-oa conflicts with -ou") 
                             if $options=~/a/ && $options=~/u/;

if (!$hiResFlag && $options=~/m/)
{
  print "need to install HiRes to report fractional time with -om, so ignoring\n";
  $options=~s/m//;
}

$pidOnlyFlag=($procOpts=~/p/) ? 1 : 0;

# We always compress files unless zlib not there or explicity turned off
$zFlag=($options=~/z/ || $filename eq "") ? 0 : 1;
if (!$zlibFlag && $zFlag)
{
  $options.="z";
  $zFlag=0;
  pushmsg("W", "Zlib not installed so can't compress raw file(s).  Use --quiet to disable this warning.")    if $rawFlag;
  pushmsg("W", "Zlib not installed so can't compress plot file(s).  Use -oz to get rid of this warning.")   if $plotFlag;
}

$precision=($options=~/(\d+)/) ? $1 : 0;
$FS=".${precision}f";

# playback mode specific
error('--showmerged only applies to playback mode')    if $playback eq '' && $showMergedFlag;
error('--extract only applies to playback mode')       if $playback eq '' && $extract ne '';

if ($playback ne "")
{
  error("-p not allowed with -F")         if $flush ne '';

  error("--offsettime must be in seconds with optional leading '-'")
      if defined($offsetTime) && $offsetTime!~/^-?\d+/;

  $playback=~s/['"]//g;    # in case quotes passed through from script
  $playback=~s/,/ /g;      # so glob below will work
  error("--align only applies to record mode")    if $alignFlag;
  error("-p filename must end in '*', 'raw' or 'gz'") 
      if $playback!~/\*$|raw$|gz$/;
  error("MUST specify -P if -p and -f")      if $filename ne "" and !$plotFlag;

  if ($extract ne '')
  {
    $extractMode=1;
    error("-s not allowed in 'extract' mode")               if $userSubsys ne '';
    error("--from OR --thru required in 'extract' mode")    if !defined($from) && !defined($thru);
  }

  # Quick check to make sure at least one file matches playback string
  my $foundFlag=0;
  foreach $file (glob($playback))
  {
    $foundFlag=1;

    # this is a great place to print headers since we're already looping through glob
    if ($showHeaderFlag)
    {
      next    if $file!~/raw/;

      # remember, this has to work on a pc as well, so can't use linux commands
      print "$file\n";
      my $return;
      $return=open TMP, "<$file"                              if $file!~/gz$/;
      $return=($ZTMP=Compress::Zlib::gzopen($file, 'rb'))     if $file=~/gz$/;
      logmsg("F", "Couldn't open '$file' for reading")  if !defined($return) || $return<1;

      while (1)
      {
	$line=<TMP>                 if $file!~/gz$/;
	$ZTMP->gzreadline($line)    if $file=~/gz$/;
	last    if $line!~/^#/;
	print $line;
      }
      print "\n";
      close TMP           if $file!~/gz$/;
      $ZTMP->gzclose()    if $file=~/gz$/;
    }
  }
  error("can't find any files matching '$playback'")    if !$foundFlag;
  exit(0)    if $showHeaderFlag;
}

# end time
$purgeDays=0;

if (defined($from) || defined($thru))
{
  error("--from/--thru only apply to -p")
      if $playback eq '';
  error("do not specify 2 times with --thru")
      if defined($thru) && index($thru, '-')!=-1;
  error("do not specify 2 times with --from and also use --thru")
      if defined($from) && defined($thru) && index($from, '-')!=-1;

  # Parse switches and handle those that only specify a date

  ($from, $thru)=split(/-/, $from)                    if !defined($thru);
  ($fromDate,$fromTime)=checkTime('--from', $from)    if defined($from);
  ($thruDate,$thruTime)=checkTime('--thru', $thru)    if defined($thru);
}
$fromDate=0           if !defined($fromDate);    # 0 means all dates
$thruDate=0           if !defined($thruDate);
$fromTime='000000'    if !defined($fromTime);
$thruTime='235959'    if !defined($thruTime);
print "From: $fromDate $fromTime  Thru: $thruDate $thruTime\n"    if $debug & 1;

$endSecs=0;
if ($runTime ne "")
{
  error("pick either -r or -R")   if $rollLog ne "";
  error("invalid -R format")      if $runTime!~/^(\d+)[wdhms]{1}$/;
  $endSecs=$1;
  $endSecs*=60        if $runTime=~/m/;
  $endSecs*=3600      if $runTime=~/h/;
  $endSecs*=86400     if $runTime=~/d/;
  $endSecs*=604800    if $runTime=~/w/;
  $endSecs+=time;
}

# log file rollover
my $rollSecs=0;
my $expectedHour;
if ($rollLog ne '')
{
  error("-r requires -f")                        if $filename eq "";
  ($rollTime,$purgeDays,$rollIncr)=split(/,/, $rollLog);
  ($purgeDays, $purgeMons)=split(/:/, $purgeDays);
  $rollIncr=60*24    if !defined($rollIncr)  || $rollIncr eq '';

  # default is 7 days for data and 12 months for logs
  $purgeDays=7       if !defined($purgeDays) || $purgeDays eq '';
  $purgeMons=12      if !defined($purgeMons);

  error("-r time must be in HH:MM format")       if $rollTime!~/^\d{2}:\d{2}$/;
  ($rollHour, $rollMin)=split(/:/, $rollTime);
  error("-r purge days must be an integer")      if $purgeDays!~/^\d+$/;
  error("-r purge months must be an integer")    if $purgeMons!~/^\d+$/;
  error("-r increment must be an integer")       if $rollIncr!~/^\d+$/;
  error("-r time invalid")                       if $rollHour>23 || $rollMin>59;
  error("-r increment must be a factor of 24 hours")
      if int(1440/$rollIncr)*$rollIncr!=1440;
  error("if -r increment>1 hour, must be multiple of 1 hour")
      if $rollIncr>60 && int($rollIncr/60)*60!=$rollIncr;
  error("roll time must be specified in 1st interval")
      if ($rollHour*60+$rollMin)>$rollIncr;

  # Getting the time to the next interval can be tricky because we have to
  # worry about daylight savings time.  This IS further complicated by
  # having to deal with intervals.  The safest thing to do is using brute-force.
  # I also have to write the following down because I know I'll forget it and
  # think it's a bug!  Assume you're going to roll every two hours (or more) and it's
  # midnite of the day to move clocks forward (probably never going happen but...).
  # 2 hours from midnight is 3AM! so we subtract an hour and now since we're before the
  # time change we create a logfile with a time of 1AM.  BUT the next log gets created
  # at AM and everyone is happy!

  # We start at the first interval of the day and then step forward until we 
  # pass our current time.  Then we see if DST is involved and then we're done!
  # Note however, if the interval is an hour or less, DST takes care of itself!
  # Step 1 - Get current date/time
  my ($sec, $min, $hour, $day, $mon, $year)=localtime(time);
  my $timeNow=sprintf "%d%02d%02d %02d:%02d:%02d", 
                       $year+1900, $mon+1, $day, $hour, $min, $sec;
  $rollToday=timelocal(0, $rollMin, $rollHour, $day, $mon, $year);

  # Step 2 - step through each increment (note in most cases there is only 1!)
  #          looking for each one > now
  my ($timeToRoll, $lastHour);
  $expectedHour=$rollHour;
  foreach ($rollSecs=$rollToday;; $rollSecs+=$rollIncr*60)
  {
    # Get the corresponding time and if not the first one see if the
    # time was changed
    my ($sec, $min, $hour, $day, $mon, $year)=localtime($rollSecs);
    $timeToRoll=sprintf "%d%02d%02d %02d:%02d:%02d", $year+1900, $mon+1, $day, $hour, $min, $sec;
    #print "CurTime: $timeToRoll  CurHour: $hour  ExpectedHour: $expectedHour\n";

    if ($rollIncr>60)
    {
      # Tricky...  We can have expected hour differ from the current one by
      # exactly 1 hour when we hit a DST time change.  However, while a 
      # simple subtraction will yield +/- 1, the one special case is when 
      # we're rolling logs at 00:00 and get an hour of 23, which generates a
      # diff of -23 when we really want +1.
      my $diff=($expectedHour-$hour);
      $specialFlag=($diff==-23) ? 1 : 0;
      $diff=1    if $specialFlag;
      $rollSecs+=$diff*3600;     # diff is USUALLY 0

      # When in this 'special' situation, '$timeToRoll' is pointing to the previous
      # day so we need to reset $timeToRoll, but only AFTER we updated rollSecs.
      if ($specialFlag)
      {
        ($sec, $min, $hour, $day, $mon, $year)=localtime($rollSecs);
        $timeToRoll=sprintf "%d%02d%02d %02d:%02d:%02d", $year+1900, $mon+1, $day, $hour, $min, $sec;
      }
      $expectedHour+=$rollIncr/60;
      $expectedHour%=24;
    }
    last    if $timeToRoll gt $timeNow;
    $lastHour=$hour;
  }
  ($sec, $min, $hour, $day, $mon, $year)=localtime($rollSecs);
  $rollFirst=sprintf "%d%02d%02d %02d:%02d:%02d", $year+1900, $mon+1, $day, $hour, $min, $sec;
  pushmsg("I", "First log rollover will be: $rollFirst");
}

# for --home we do some vt100 cursor control
if ($homeFlag)
{
  $home=sprintf("%c[H", 27);     # top of display
  $clr=sprintf("%c[J", 27);      # clear to end of display
  $clscr="$home$clr";            # clear screen
  $cleol=sprintf("%c[K", 27);    # clear to end of line
}

# if -N, set priority to 20
`renice 20 $$`    if $niceFlag;

# Couldn't find anywhere else to put this one...
error("-sT only works with -P for now (too much data)")
    if $TFlag && !$plotFlag;

# get parent pid so we can check later to see it still there
$stat=`cat /proc/$$/stat`;
$myPpid=(split(/\s+/, $stat))[3];

###############################
#    P l a y b a c k    M o d e
###############################

if ($playback ne '')
{
  # Select all files that need to be processed based on dates
  my $numSelected=0;
  my ($firstFileDate, $lastFileDate, $lastPrefix)=(0,0,'');

  my $pushed='';
  while (my $file=glob($playback))
  {
    next    if $file!~/(.*)-(\d{8})-(\d{6})\.(raw[p]*)/;
    my $prefix=  $1;
    my $fileDate=$2;
    my $fileTime=$3;

    # we never look at rawp files when doing stats
    next    if $file=~/rawp/ && $statsFlag;

    $firstFileDate=$fileDate    if $firstFileDate==0;
    $numSelected++;

    #    F i l t e r    O u t    F i l e s    N e w e r    T h a n    t h r u D a t e

    # If there IS a thru date, ignore any files start were beyond it.
    next    if ($thruDate ne 0) && (($fileDate > $thruDate) || (($fileDate == $thruDate) && ($fileTime > $thruTime)));

    # and finally, if no from OR thru dates, the thru time is applied against all files
    # so skip any files created after the from time
    next    if ($fromDate eq 0) && ($thruDate eq 0) && ($fileTime>$thruTime);

    # New functionality for V3.5.1: only apply other filters if wildcards NOT in filename
    # since files CAN contain data beyond their date stamp.
    if ($playback!~/\*/)
    {
      push @playbackList, $file;
      next;
    }

    #    A p p l y    F i l t e r s    T o    W i l d c a r d e d    F i l e n a m e s

    # We only get here is a wildcard in the file list.  If it's from date is early than specified
    # ignore it, remembering if it did have data that crossed midnight we'll never know.  Those
    # MUST be processes w/o wild cards in their names.  If this ever becomes an issue we could always
    # look inside the header here, but that's more work than currently deemed worth it.
    next    if ($fromDate ne 0) && ($fileDate < $fromDate); 

    # This is the magic AND there are 3 cases all of which have the common test of
    # there needs to be a file with a different basename (in case we're doing a rawp
    # file and there is alreay a raw file there) on the stack and the current file 
    # is < $fromTime, in which case we might NOT want to process the file(s) on the
    # top of the stack under the the following cases:
    # - if we have a from date this only applies to files for the from date
    # - if no from date but a thru date, apply time to files of first date
    # - if no from AND thru dates this test applies to ALL dates but only
    #   pop files for the same date which are by definition too 'young'

    if ($file!~/$pushed/ && ($lastFileDate!=0) && ($fileTime<$fromTime) && ($prefix eq $lastPrefix))
    {
      if (($fromDate!=0 && $fileDate==$fromDate) ||
          ($fromDate==0 && $thruDate!=0 && $fileDate==$firstFileDate) ||
	  ($fromDate==0 && $thruDate==0 && $fileDate==$lastFileDate))
      {
	my $popped=pop(@playbackList);
	$popped=quotemeta((split(/\./, $popped))[0]);

        # get rid of companion file if there is one.
        pop(@playbackList)    if scalar(@playbackList) && $playbackList[0]=~/$popped/;
      }
    }

    push @playbackList, $file;
    $pushed=quotemeta((split(/\./, $file))[0]);    # filename less extension, ready for regx

    $lastPrefix=$prefix;
    $lastFileDate=$fileDate;
  }

  $numProcessed=0;
  $elapsedSecs=0;
  preprocessPlayback(\@playbackList);

  $doneFlag=0;
  $lastPrefix=$lastHost=$prefixPrinted=$lastSubsys='';
  foreach $file (@playbackList)
  {
    # Unfortunately we need a more unique global name for the file we're doing
    $playbackFile=$file;
    $rawPFlag=($file=~/\.rawp/) ? 1 : 0;

    # For now, we're going to skip files in error and process the rest.
    # Some day we may just want to exit on errors (or have another switch!)
    $ignoreFlag=0;
    foreach $key (keys %preprocErrors)
    {
      # some are file names and some just prefixes.
      if ($file=~/$key/)
      {
        ($type, $text)=split(/:/, $preprocErrors{$key}, 2);
	$modifier=($type eq 'E') ? 'due to error:' : 'because';
        logmsg($type, "*** Skipping '$file' $modifier $text ***");
	$ignoreFlag=1;
	next;
      }
    }
    next    if $ignoreFlag;

    print "\nPlaying back $file\n"    if $msgFlag || $debug & 1;

    $file=~/(.*)-(\d{8})-\d{6}\.raw[p]*/;
    $prefix="$1-$2";
    $fileHost=$1;
    $fileRoot=basename($prefix);

    # if the prefix didn't change, we can't have a new host
    $newPrefixFlag=$newHostFlag=0;
    if ($prefix ne $lastPrefix)
    {
      # Remember that the prefix includes the date so the host could still be the same!
      $newPrefixFlag=1;
      $newHostFlag=($fileHost ne $lastHost) ? 1 : 0;
      $lastHost=$fileHost;
      print "NewPrefix: $newPrefixFlag  NewHost: $newHostFlag\n"    if $debug & 1;

      undef $newSeconds[$rawPFlag]    if $newHostFlag;    # indicates we start anew

      # For each day's set of files, we need to reset this variable so interval
      # lengths are calculared correctly.  Since int3 doesn't contain any rate
      # data we don't care about that one.
      $lastInt2Secs=0;

      if ($msgFlag && defined($preprocMessages{$prefix}))
      {
        # Whatever the messages may be, we only want to display them once for
        # each set of files, that is files with the same prefix
	my $preamblePrinted=0;
        for ($i=0; $i<$preprocMessages{$prefix}; $i++)
        {
          $key="$prefix|$i";
          if ($file=~/$prefix/)
          {
            # messy but makes it easier on the user to only see this message when a -s change
            # didn't happen because of a raw/rawp adjustment.  Since changes are appended, just
            # subtract first string from final one and don't report if only [YZ] remains
            if ($preprocMessages{$key}=~/-s overridden/ && ($playback{$prefix}->{flags} & 1))
            {
                my $first=$playback{$prefix}->{subsysFirst};
                my $final=$playback{$prefix}->{subsys};
                $final=~s/$first//;
                next    if $final=~/^[YZ]*$/; 
            }

            print "  >>> Forcing configuration change(s) for '$prefix-*'\n"
		if !$preamblePrinted;
	    print "  >>> $preprocMessages{$key}\n";
            $preamblePrinted=1;
	  }
        }
      }

      # When we start a new prefix, that's the time to reset any variables that
      # span the set of common files.
      $lustreCltInfo='';

      $headersPrinted=$totalCounter=$separatorCounter=0;

      # Finally save the merged set of subsystems associated with all the files for
      # for this prefix.
      $subsysAll=$playback{$prefix}->{subsys};
    }
    $lastPrefix=$prefix;
    print "NewPrefix: $newPrefixFlag  NewHost: $newHostFlag\n"    if $debug & 1;

    # we need to initialize a bunch of stuff including these variables and the
    # starting time for the file as well as the corresponding UTC seconds.
    ($recVersion, $recDate, $recTime, $recSecs, $recTZ, $recInterval, $recSubsys, $recNfsFilt, $recHeader)=initFormat($file);
    error("$file was created before collectl V2.0 and so cannot be played back")    if $recVersion lt '2.0';
    printf "RECORDED -- Host: $Host  Version: %s  Date: %s  Time: %s  Interval: %s Subsys: $recSubsys\n",
              $recVersion, $recDate, $recTime, $recInterval
		  if $debug & 1;

    # we can't do this until we know what version of collectl recorded the file
    if ($tcpFilt ne '' && $recVersion ne '' && $recVersion lt '3.6.4-1')
    {
      print "$file recorded with collectl V$recVersion which does not support --tcpfilt, so skipping...\n";
      next;
    }
    $tcpFilt='T'    if $subsys=~/t/i && $recVersion lt '3.6.4-1';    # only subsystem reported earlier

    # Make sure at least 1 requested subsys is actually recorded OR if -s-all clear them all
    # also note an empty $subsys had been set to ' ' so regx below will work.  Now set it back!
    $subsys=''    if $userSubsys eq '-all';
    my $tempSys=$subsys;           # this is what we want to report
    $tempSys=~s/[$recSubsys]//gi;  # remove ANY that are recorded, whether summary OR detail
    $subsys=''    if $subsys eq ' ';
    print "recSubsys: $recSubsys subsys: $subsys  tempSys: $tempSys\n"    if $debug & 1;

    # When processing a batch of files, it's possible none of them have any of the selected subsystems,
    # the best example being playing back  *.gz files which have been collected with --tworaw and only
    # requestion data in one typw.  In those cases both files will be processed and we need to skip
    # the ones w/o data.  The logmsg() below only reports the message when -m included.
    if (!$numProcessed && !$impNumMods && $subsys eq $tempSys)
    {
      logmsg("w", "none of the requested subsystems are recorded in selected file");
      next;
    }

    loadUids($passwdFile)      if $recSubsys=~/Z/;
    #print "SUBSYS: $subsys  RECSUBSYS: $recSubsys  FLAGS: $playback{$prefix}->{flags}\n";

    # if --top but user didn't specify -s too, ignore anything in header(s)
    $subsys=~s/[^YZ]*//g       if $topFlag && $userSubsys eq '';
    $subsysAll=~s/[^YZ]*//g    if $topFlag && $userSubsys eq '';

    # Now that we know the subsystem it's safe to initialize a custom --export module if using one.
    if ($expName ne '')
    {
      my $initName="${expName}Init";
      &$initName(@expOpts);
    }

    # I wanted these 'in your face' rather than buried in 'initFormat()'.
    if ($playback{$prefix}->{flags} & 1)
    {
      # when playing back data from BOTH files, we need to reset these if in fact something to
      # print from rawp so that we'll repeat brief headers.
      $headersPrinted=$totalCounter=0       if $subsys=~/[YZ]/i;

      # When playing back files generated with -G and user specified -s, make sure that subsys
      # only contains file-related subsystems so $subsys is consistent with the file we're processing
      $subsys=~s/[YZ]//gi     if $file!~/rawp/;
      $subsys=~s/[^YZ]//gi    if $file=~/rawp/;
      next    if $subsys eq '';    # in case $subsys now '' for this file
    }
    else
    {
      # no 'rawp' files associated with this prefix so if user chose 'y' in playback and no slab
      # data has been recorded, ignore it so we won't put ourselves into --verbose because of it.
      # NOTE - this is an exception to the rule that if the user requests a subsystem for which
      #        we have no data we report it as zeros.
      $subsys=~s/y//gi    if $recSubsys!~/y/i;
    }

    # the only way nfsfilt can come back null is when there is a blank nfsfilt in header
    my $tempFilt=($recNfsFilt ne '' ? $recNfsFilt : 'c2,s2,c3,s3,c4,s4');
    if ($nfsFilt ne '')
    {
      foreach my $filt (split(/,/, $nfsFilt))
      {
        error("'$filt' data not recorded in $file and so cannot be selected")
	    if $tempFilt!~/$filt/;
      }
      $tempFilt=$nfsFilt;
    }
    setNFSFlags($tempFilt);

    # We can only do this test after figuring out what's in the header.  NOTE that since the number
    # of enabled CPUs can change dynamically when doing -sC and we've already skipped the code in 
    # formatit that sets the number to 0, we have to do it here too.
    if ($subsys=~/j/i && $subsys!~/C/i && $plotFlag)
    {
      logmsg('I', "-sj or -sJ with -P also requires CPU details so adding -sC.  See FAQ for details.");
      $subsys.='C';
      $subsysAll.='C';
      $noCpusFlag=1;    # we need to know elsewhere when this was done
      $cpusEnabled=0    if $recSubsys=~/c/i;    # if recorded, WILL be dynamically reset
    }

    # the way the process/slab tests work is if raw file not built with -G, look at all files.
    # but IF a -G only look at rawp files.
    if (($playback{$prefix}->{flags} & 1)==0 || $rawPFlag)
    {
      # no rawp files so these tests are pretty easy
      my $skipmsg='';
      $skipmsg="io"         if $topIOFlag && !$processIOFlag;
      $skipmsg="process"    if $procAnalFlag && $recSubsys!~/Z/;
      $skipmsg="slab"       if $slabAnalFlag && $recSubsys!~/Y/;
      if ($skipmsg ne '')
      {
        print "  >>> Skipping file because it does not contain $skipmsg data <<<\n";
        next;
      }
    }

    # Need to reset the globals for the intervals that gets recorded in the header.
    # Note the conditional on the assignments for i2 and i3.  This is because they SHOULD be
    # in the header as of V2.1.0 and I don't want to mask any problems if they're not.
    ($interval, $interval2, $interval3)=split(/:/, $recInterval);
    $interval2=$Interval2    if !defined($interval2) && $recVersion lt '2.1.0';
    $interval3=$Interval3    if !defined($interval2) && $recVersion lt '2.1.0';

    # At this point we've initialized all the variables that will get written to the common
    # header for one set of files for one day, so if the user had specified --showmerged, now
    # is the best/easiest time to do it.  We also need to set a flag so we only print the
    # header once for each set of merged files
    if ($showMergedFlag)
    {
      # I'm bummed I can't use '$lastPrefix', but we don't always execute the
      # outer loop and can't rest it in one place common to everyone...
      if ($prefix ne $prefixPrinted)
      {
        $commonHeader=buildCommonHeader(0);
      }
      $prefixPrinted=$prefix;
      next;
    }

    # on the off chance that lustre data was collected with --lustopts but not
    # played back, clear the lustre settings or else we're screw up the default
    # playback mode.
    $lustOpts=''    if $subsys!~/l/i;

    # conversely, if data was collected using --lustOpts but lustre
    # wasn't active during the time this file was collected, the header will
    # indicate this log does NOT contain any lustre data but the -s will and 
    # so we need to turn off any -lustOpts or else 'checkSubsysOpts()' 
    # will report a conflict.
    $lustOpts=~s/B//g       if $lustOpts=~/B/    && $CltFlag==0 && $OstFlag==0;
    $lustOpts=~s/D//g       if $lustOpts=~/D/    && $MdsFlag==0 && $OstFlag==0;
    $lustOpts=~s/[MR]//g    if $lustOpts=~/[MR]/ && $CltFlag==0;

    # Now we can check for valid/consistent sub-options (not sure this is still
    # necessary, but it shouldn't hurt).  Since we can swap back and forth between
    # raw and rawp, with the latter requiring verbose, always reset to the default
    # of brief, unless if course user specified --verbose.
    checkSubsysOpts();       # Make sure valid
    $verboseFlag=1    if $userVerbose;
    setOutputFormat();

    # We need to set the 'coreFlag' based on whether or not any core 
    # subsystems will be processed.
    $coreFlag=($subsys=~/[a-z]/) ? 1 : 0;

    # if a specific time offset wasn't selected, find difference between 
    # time collectl wrote out the log and the time of the first timestamp.
    if (!defined($offsetTime) && $recSecs ne '')
    {
      $year=substr($recDate, 0, 4);
      $mon= substr($recDate, 4, 2);
      $day= substr($recDate, 6, 2);
      $hour=substr($recTime, 0, 2);
      $min= substr($recTime, 2, 2);
      $sec= substr($recTime, 4, 2);
      $locSecs=timelocal($sec, $min, $hour, $day, $mon-1, $year-1900);
      $timeAdjust=$locSecs-$recSecs;
    }
    elsif (defined($offsetTime))
    {
      $timeAdjust=$offsetTime;    # user override of default
    }

    # Header already successfully read one, but what the heck...
    if (!defined($recVersion))
    {
      logmsg("E", "Couldn't read header for $file");
      next;
    }

    # Note - the prefix includes full path
    $zInFlag=($file=~/gz$/) ? 1 : 0;
    $file=~/(.*-\d{8})-\d{6}\.raw[p]*/;
    $prefix=$1;

    if ($prefix!~/$Host/)
    {
      print "ignoring $file whose header says recorded for $Host but whose name says otherwise!\n";
      next;
    }

    # we get new output files (if writing to a file) for each prefix-date combo noting if reading
    # a rawp file we might get 2, also noting that $Host is a global pointing to the current host
    # being processed both in record as well as playback mode.  We also need to track for terminal
    # processing as well, so use a different flag for that
    $key="$prefix:$recDate";
    $newPrefixDate=(!defined($playback{$key})) ? 1 : 0;
    if ($newPrefixDate)
    {
      print "Prefix: $prefix  Host: $Host\n"    if ($debug & 1) && !$logToFileFlag;

      $headersPrintedProc=$headersPrintedSlab=$prcFileCount=0;
      $newOutputFile=($filename ne '') ? 1 : 0;
      $playback{$key}=1;
    }
    $prcFileCount++    if $subsys=~/Z/;
    #print "NEW PREFIX: $newPrefixDate  NEW FILE: $newOutputFile\n";

    # set playback timeframe for the file we're about to playback, using the date of the file
    # if not specified or that from the from if it is.  The start time has already been set
    # earlier but when not starting at the beginning, we need to back up 1 interval since the
    # first one is never reported.
    my $tempDate=($fromDate eq '0') ? $recDate : $fromDate;
    $fromSecs=getSeconds($tempDate, $fromTime);
    $fromSecs-=$interval    if $fromTime!=0;

    # The ending time is either the same date as the starting one (unless overriden by the user
    # for files that cross midnight) and we need to add a fraction to the ending time in case
    # fractional timestamps in file.  Max time is Jan 19, 2038 but we'll use Jan 1 if needed.
    $tempDate=$thruDate    if defined($thruDate) && $thruDate ne'0';
    $thruSecs=(!defined($thru)) ? 2145934800 : getSeconds($tempDate, $thruTime).'.999';

    # this is just to make debugging time frames easier especially if user gets odd results.
    if ($debug & 1)
    {
      my $fromstamp=getDateTime($fromSecs);
      my $thrustamp=getDateTime($thruSecs);
      print "PlayBack From: $fromstamp  Thru: $thrustamp\n";
    }

    if ($zInFlag)
    {
      $ZPLAY=Compress::Zlib::gzopen($file, "rb") or logmsg("F", "Couldn't open '$file'");
    }
    else
    {
      open PLAY, "<$file" or logmsg("F", "Couldn't open '$file'");
    }

    if ($extractMode)
    {
      my $base=basename($file);
      $outfile=(-d $extract) ? "$extract$Sep$base" : "$extract-$base";
      #print "BASE: $base  PREFIX: $prefix OUT: $outfile\n";
      error("--extract specifies an output file with the same name as original!")    if $outfile eq $file;
      logmsg('I', "Extracting to '$outfile'");

      # compress the output file, but only if the input one was compressed.
      $ZRAW=Compress::Zlib::gzopen($outfile, 'wc') or logmsg("F", "Couldn't create '$outfile'")    if $outfile=~/gz$/;
      open RAW, ">$outfile"                        or logmsg("F", "Couldn't create '$outfile'")    if $outfile!~/gz$/;
    }

    # only call this if generating plot data either in file or on terminal AND
    # only one time per output file
    if ($plotFlag && ($newOutputFile || $options=~/u/))
    {
      # Before we do anything else, close any files that were opened last pass
      # noting 'closeLogs()' also calls setFlags($subsys)
      closeLogs($lastSubsys)    if $lastSubsys ne '';

      # Open all output files here based on what was in merged subsystems.
      setFlags($subsysAll);
      print "SetFlags: $subsysAll\n"    if $debug & 1;

      # If playback file has a prefix before its hostname things get more complicated
      # as we want to preserve that prefix and at the same time honor -f.
      $filespec=$filename;
      if ($prefix=~/(.+)-$Host/)
      {
        my $temp=$1;
        $temp=~s/.*$Sep//;
        $filespec.=(-d $filespec) ? "$Sep$temp" : "-$temp";
      }

      # note we're only passing '$file' along in case we need diagnostics and we're also
      # resetting '$subsys' to match ALL the subsystems selected for this set of file(s)
      my $saveSubsys=$subsys;
      $subsys=$subsysAll;
      $newfile=newLog($filespec, $recDate, $recTime, $recSecs, $recTZ, $file);
      if ($newfile ne '1')
      {
        # This is the most common failure mode since people rarely use -ou
        # and having 2 separate conditions gives us more flexibility in messages
        if ($options!~/u/)
        {
  	  print "  Plotfile '$newfile' already exists and will not be touched\n";
          print "  '-oc' to create a new one OR '-oa' to append to it\n";
        }
        else
	{
  	  print "  Plotfile '$newfile' exists and is newer than $file\n";
          print "  You must specify '-ocu' to force creation of a new one\n";
	}
        next;
      } 
      $subsys=$saveSubsys;
      $newOutputFile=0;
      $lastSubsys=$subsysAll;    # used to track which files were actually opened
    }

    # when processing data for a new prefix/date and printing on a terminal
    # we need to print totals from previous file(s) if there were any and 
    # reset total.  However is --statopts s (as opposed to S), we do subtotals
    # for each file
    if ($filename eq '' && ($newPrefixDate || $statOpts=~/s/))
    {
      if ($statsFlag && $numProcessed)
      {
        printBriefCounters('A')    if $statOpts=~/a/;
        printBriefCounters('T');
      }
      $elapsedSecs=0;
      resetBriefCounters();
    }
    
    # Whenever a from time specified AND we're doing a new prefix, we need to start out in
    # skip mode.  In all other cases we read ALL the records.  Since --from with no date
    # applies to all files, that will also trigger starting out in 'skip' mode.
    $skip=($fromSecs && ($fromDate==0 || $newPrefixFlag)) ? 1 : 0;

    undef($fileFrom);
    $firstTime=$firstTime2=1;  # tracks int1 and int2 first time processing
    $fileThru=$newMarkerWritten=$timestampFlag=$timestampCounter[$rawPFlag]=0;
    $fullTime=0;        # so we don't get uninit first time we do $microInterval calculation
    $bytes=1;           # so no compression error on non-zipped files
    $numProcessed++;    # it's not until we get here that we can say this

    while (1)
    {
      # read a line from either zip file or plain ol' one
      last    if ( $zInFlag && ($bytes=$ZPLAY->gzreadline($line))<1) ||
	         (!$zInFlag && !($line=<PLAY>)); 

      # we always skip comments, but in extract mode we need to echo them to output file
      if ($line=~/^#/)
      {
        if ($extractMode)
        {
          $ZRAW->gzwrite($line)    if $outfile=~/gz$/;
	  print RAW $line          if $outfile!~/gz$/; 
        }
	next;
      }

      # Doncha love special cases?  Turns out when reading back process data
      # from a PRC file which was created from multiple logs, if a process from
      # one log comes up with the same pid as that of an earlier log, there's
      # no easy way to tell.  Now there is!
      writeInterFileMarker()
	  if $filename ne '' && $prcFileCount>1 && !$newMarkerWritten;
      $newMarkerWritten=1;
  
      # if new interval, it really indicates the end of the last one but its
      # time is that of the new one so process last interval before saving.
      # if this isn't a valid interval marker the file somehow got corrupted
      # which was seen one time before flush error handling was put in.  Don't
      # know if that was the problem or not so we'll keep this extra test.
      $timestampFlag=0;
      $timestampCount=0;
      if ($line=~/^>>>/)
      {
        # we need to make sure both $lastSeconds and $newSeconds track BOTH the
        # raw and rawp files, if both exist.

	# we need to know later on if we're processing a timestamp AND how many we've seen
        # because if we hit EOF and only 1 seen, we have not processed a single, full interval.
        $timestampFlag=1;
	$timestampCount++;
        if ($line!~/^>>> (\d+\.\d+) <<</)
        {
 	  logmsg("E", "Corrupted file do to invalid time marker in '$file'\n".
  		      "Ignoring the rest of file.  Last valid marker: $newSeconds[$rawPFlag]");
	  next;
        }
        #printf ">>> $1 <<<  Count: $timestampCount From: %s Stamp: %s\n", getDateTime($fromSecs), getDateTime($1);

        # At this point and if defined $newSeconds is actually pointing to the last interval
        # and be sure to convert to local time so --from/--thru checks work.
	my $thisSeconds=$1+$timeAdjust;
        $lastSeconds[$rawPFlag]=(defined($newSeconds[$rawPFlag])) ? $newSeconds[$rawPFlag] : 0;
  	$skip=0    if $fromSecs && $thisSeconds>=$fromSecs;

        # since we're in an inner loop we need a flag
        if ($thruSecs && $lastSeconds[$rawPFlag]>$thruSecs)
        {
	  $doneFlag=1;
          last;
        }

        # Always echo timestamp in extract mode when we're processing this interval
        if ($extractMode && !$skip)
        {
          $ZRAW->gzwrite($line)    if $outfile=~/gz$/;
          print RAW $line          if $outfile!~/gz$/; 
        }

        $timestampCounter[$rawPFlag]++    if !$skip;
        if ($timestampCounter[$rawPFlag]==1)
        {
          # If a second (or more) file for same host, are their timstamps consecutive?
          # Since we could have a raw/rawp file the way to tell a new file is that
          # $newSeconds will be defined.
          # If NOT consecutive (or first file for a host), init 'last' variables, noting
          # we also need to init if there was a disk configuration change.
          $consecutiveFlag=(!$newHostFlag && defined($newSeconds[$rawPFlag]) && 
                             $thisSeconds==$newSeconds[$rawPFlag] && !$diskChangeFlag) ? 1 : 0;
          $newSeconds[$rawPFlag]=$thisSeconds;
          if (!$consecutiveFlag)
          {
	    # if not doing raw/rawp files, init everything, otherwise just init the type we're doing
	    initLast()             if ($playback{$prefix}->{flags} & 1)==0;
	    initLast($rawPFlag)    if  $playback{$prefix}->{flags} & 1;
            $lastSecs[$rawPFlag]=$thisSeconds;
	  }
	  print "ConsecFlag: $consecutiveFlag\n"    if $debug & 1;
          next;
	}
        $newSeconds[$rawPFlag]=$fullTime=$thisSeconds;    # we use '$fullTime' for $microInterval re-calculation

        # track from/thru times for each file to be used for -oA in terminal mode
        if (!$skip && !$rawPFlag)
        {
          $fileFrom=$newSeconds[$rawPFlag]    if !defined($fileFrom);
          $fileThru=$newSeconds[$rawPFlag];
        }

        # Normally we fall through on a timestamp marker so we can process the interval results
        # but in extract we don't want to generate any output, just record data.
	next    if $extractMode;
      }
      next    if $skip;
      print $line    if $debug & 4;

      if ($grepPattern ne '')
      {
        if ($line=~/$grepPattern/)
        {
  	  $firstTime=0;    # to indicate something found
          my $msec=(split(/\./, $newSeconds[$rawPFlag]))[1];
          my ($ss, $mm, $hh, $mday, $mon, $year)=localtime($newSeconds[$rawPFlag]);
	  $datetime=sprintf("%02d:%02d:%02d", $hh, $mm, $ss);
	  $datetime=sprintf("%02d/%02d %s", $mon+1, $mday, $datetime)                   if $options=~/d/;
	  $datetime=sprintf("%04d%02d%02d %s", $year+1900, $mon+1, $mday, $datetime)    if $options=~/D/;
	  $datetime.=".$msec"                                                           if ($options=~/m/);
	  print "$datetime $line";
        }
	next;
      }

      if ($extractMode)
      {
        # clear flag to prevent error message later.
	$firstTime=0;
        $ZRAW->gzwrite($line)    if $outfile=~/gz$/;
	print RAW $line          if $outfile!~/gz$/; 
	next;
      }

      # Either we're processing a timestamp marker OR data entries
      # When using a single raw file that has interval markers for all record and newer rawp
      # files that only have them for interval2 only we need to force the 'print' flag each time
      $interval2Print=1    if $rawPFlag && $recVersion ge '3.3.5';
      if ($timestampFlag)
      {
        # We already skipped first interval marker.  As for the second one, which indicates the end of
        # a complete set of data, we only process that if we have consecutive files in which case
        # we get to use the last file's data for the previous interval's data.  BUT we have to make
        # sure 'initInterval' called for second interval which may have been skipped.
        my $saveI2P=$interval2Print;    # gets reset to 0 during intervalEnd()
        intervalEnd($lastSeconds[$rawPFlag])    if $consecutiveFlag || $timestampCounter[$rawPFlag]>2;
        initInterval()    if $timestampCounter[$rawPFlag]==2;
        $firstTime2=0     if $saveI2P;
      }
      else
      {
        dataAnalyze($subsys, $line);
      }
      $firstTime=0;
    }

    # Write 'next' timestamp at end of file.
    if ($extractMode)
    {
      $ZRAW->gzwrite($line)    if $outfile=~/gz$/;
      print RAW $line          if $outfile!~/gz$/; 
    }

    # We really only need message when -p specifies single file
    if ($firstTime && $numSelected==1)
    {
      print "No records selected for playback!  Are --from/--thru` wrong?\n";
      next;
    }

    # normally samples will end on timestamp marker (even if last interval) and therefore
    # processed above.  However in pre-3.1.2 releases timestamps weren't written when 
    # logs rolled and so we need to process the last interval in those cases as well.
    intervalEnd($newSeconds[$rawPFlag])     if !$timestampFlag && $recVersion lt '3.1.2';

    my $tmpsys=$subsys;
    $tmpsys=~s/[YZ]//g;
    $ZPLAY->gzclose()    if  $zInFlag;
    close PLAY           if !$zInFlag;

    # if we reported data from this file (we may have skipped it entirely if --from
    # used with multiple files), calculate how many seconds reported on in for 
    # stats reporting with -oA, but only if at least 1 full interval processed
    if (!$skip && !$rawPFlag && !$extractMode && $timestampCount>1)
    {
      # Note that by default we never include first interval data, but if this was a
      # consecitive file we need to include that interval to so add it back in
      $playbackSecs=$fileThru-$fileFrom;
      $playbackSecs+=$interval    if $consecutiveFlag;
      $elapsedSecs+=$playbackSecs;
    }

    # for easier reading...
    print "\n"    if $debug & 1;

    # This should be pretty rare..
    logmsg("E", "Error reading '$file'\n")    if $bytes==-1;

      last    if $doneFlag;
  }

  # Close logs that are open from last pass
  closeLogs($lastSubsys)    if $numProcessed;

  # Always print last set of summary data...
  printProcAnalyze()    if $procAnalCounter;
  printSlabAnalyze()    if $slabAnalCounter;

  # if printing to terminal, be sure to print averages & totals for last file processed
  if (!$rawPFlag && $statsFlag && $filename eq '')
  {
    $subsys=$subsysAll;    # in case mixed raw/rawp we need to reset
    $subsys=~s/y//;
    printBriefCounters('A')    if $statOpts=~/a/;
    printBriefCounters('T');
  }

  `stty echo`    if !$PcFlag && $termFlag && !$backFlag;   # in brief mode, we turned it off
  my $temp=(!$msgFlag) ? '  Try again with -m.' : '';
  print "No files selected contain the selected data.$temp\n"    if !$numProcessed;
  exit(0);
}

###########################
#    R e c o r d    M o d e
###########################

# Would be nice someday to migrate all record-specific checks here
error("-offsettime only applies to playback mode")    if defined($offsetTime);

# need to load even if interval is 0, but don't allow for -p mode
loadPids($procFilt)     if $subsys=~/Z/;
loadUids($passwdFile)   if $subsys=~/Z/;

# In case running on a cluster, record the name of the host we're running on.
# Track in collecl's log as well as syslog
my $nohup=($nohupFlag && !$daemonFlag) ? '[--nohup]' : '';    # only announce --nohup if not daemon
my $temp=($runas ne '') ? "as user '$runas' " : '';
$temp.=($pname ne '') ? "(running as '$pname') " : '';
$message="V$Version Beginning execution$nohup ${temp}on $myHost...";
logmsg("I", $message);
logsys($message);
checkHiRes()        if $daemonFlag;      # check for possible HiRes/glibc incompatibility

# now let's report any messages that occurred earlier
foreach my $message (@messages)
{
  my ($severity, $text)=split(/-/, $message, 2);
  logmsg($severity, $text);
}

# initialize. noting if the user had only selected subsystems not supported
# on this platform, initRecord() will have deselected them!
initRecord();
error("no subsystems selected")    if $subsys eq '' && $import eq '';  # ok in --import mode

# Process I/O stats are a little tricky.  initRecord() sets $processIOFlag based on kernel's
# capabilities, but if user has disabled them, we then need to clear that flag.
error("process I/O features not enabled in this kernel")       if $procOpts=~/i/i && !$processIOFlag;
error("process options i and I are mutually exclusive")        if $procOpts=~/i/ && $procOpts=~/I/;
error("you cannot use --top and IO options with this kernel")  if $topIOFlag && !$processIOFlag;
error("you cannot use --top and IO options with --procopt I")  if $topIOFlag && $procOpts=~/I/;
$processIOFlag=0    if $procOpts=~/I/;

if ($subsys=~/y/i && !$slabinfoFlag && !$slubinfoFlag)
{
  logmsg("W", "Slab monitoring disabled because neither /proc/slabinfo nor /sys/slab exists");
  $yFlag=$YFlag=0;
  $subsys=~s/y//ig;
}

# We can't do this until we know if the data structures exist.
loadSlabs($slabFilt)    if $subsys=~/y/i;

# now that subsys accurately reflects the systems we're collectling data on we
# can safely initialize out export if one is defined.
if ($expName ne '')
{
  my $initName="${expName}Init";
  &$initName(@expOpts);
}

# this sets all the xFlags as specified by -s.  At least one must be set to
# write to the 'tab' file.
setFlags($subsys);

# In case displaying output.  We also need the recorded version to match ours.
initFormat();
initLast();
$recVersion=$Version;

# This has to go after initFormat() since it loads '$envRules' and may init
# stuff needed by printTerm()
if ($envTestFile ne '')
{
  envTest();
  exit(0);
}

# Since we have to check subsystem specific options against data in recorded 
# file, let's not do it twice, but we have to do it AFTER initFormat()
checkSubsysOpts();

#    L a s t    M i n u t e    V a l i d a t i o n

# This needs to be done after loadConfig and only in record mode
logmsg('W', "Couldn't find 'ipmitool' in '$ipmitoolPath'")
      if $subsys=~/E/ && $Ipmitool eq '';

# These can only be done after initRecord()
# Since it IS possible for a server to be running as an MDS and a client, we need the following
error("-sL applies to a server only running as an MDS when used with --lustopts D")
    if $subsys=~/L/ && $NumMds && !$CltFlag && $lustOpts!~/D/;
error("--lustopts D only applies to HP-SFS")
    if $lustOpts=~/D/ && $sfsVersion eq '';

if ($options=~/x/i)
{
  error("exception reporting requires --verbose")
           if !$verboseFlag;
  error("exception reporting only applies to -sD and lustre OST details or MDS/Client summary")
           if ($subsys!~/[DLl]/ || ($subsys=~/L/ && $NumOst==0) || 
	      ($subsys=~/l/ && $NumMds+$CltFlag==0));
  error("exception reporting must be to a terminal OR a file in -P format")
           if ($filename ne "" && !$plotFlag) || ($filename eq "" &&  $plotFlag);
}

#    L a s t    M i n u t e    C h a n g e s    T o    F o r m a t t i n g

# OK, so it's getting messy.  The decision to use brief/verbose is made in setOutputFormat()
# but it's called much earlier, certainly before if we know what types of lustre node that
# gets determined in initFormat() which gets called up above.  Perhaps over time other 
# last minute tests will need a home and this may prove to be it.

# The purpose of this is that in verbose mode when a single type of data is being displayed
# we'll have set $sameColsFlag, but now that we know more about the lusre configuration 
# we may have to clear that setting.
if ($subsys=~/l/i && $verboseFlag)
{
  $sameColsFlag=0    if $CltFlag+$OstFlag+$MdsFlag>1;
}

# daemonize if necessary
if ($daemonFlag)
{
  # We need to make sure no terminal I/O
  open STDIN,  '/dev/null'   or logmsg("F", "Can't read /dev/null: $!");
  open STDOUT, '>/dev/null'  or logmsg("F", "Can't write to /dev/null: $!");
  open STDERR, '>/dev/null'  or logmsg("F", "Can't write to /dev/null: $!");

  # fork a child and exit parent, but make sure fork really works
  defined(my $pid=fork())     or logmsg("F", "Can't fork: $!");
  exit(0)    if $pid;

  # Make REALLY sure we're disassociated
  setsid()                   or logmsg("F", "Couldn't setsid: $!");
  open STDIN,  '/dev/null'   or logmsg("F", "Can't read /dev/null: $!");
  open STDOUT, '>/dev/null'  or logmsg("F", "Can't write to /dev/null: $!");
  open STDERR, '>/dev/null'  or logmsg("F", "Can't write to /dev/null: $!");
  `echo $$ > $PidFile`;

  # Now that we're set up to start, if '--runas' has been sprecified we need to do a
  # few things that require privs before actually changing our UID.  Also note the
  # GID is optional.
  if ($runas ne '')
  {
    # we have to make sure the owner ship of the message log is correct.
    # This is only an issue for the msglog when a new file gets created to log the first 
    # messge of the month and we've restarted as root.  Steal the code from logmsg() to
    # build its name.
    ($ss, $mm, $hh, $day, $mon, $year)=localtime(time);
    $yymm=sprintf("%d%02d", 1900+$year, $mon+1);
    $logname=(-d $filename) ? $filename : dirname($filename);
    $logname.="/$myHost-collectl-$yymm.log";

    `chown $runasUid $logname`;
    `chgrp $runasGid $logname`    if defined($runasGid);

    # now we can change our process's ownership taking care to do the group first
    # since we won't be able to change anything once we change our UID.
    $EGID=$runasGid    if defined($runasGid);
    $EUID=$runasUid;

  }
}

######################################################
#
# ===>   WARNING: No Writing to STDOUT beyond   <=====
#                 since we may be daemonized!
#
######################################################

$SIG{"INT"}=\&sigInt;      # for ^C
$SIG{"TERM"}=\&sigTerm;    # default kill command
$SIG{"USR1"}=\&sigUsr1;    # for flushing gz I/O buffers

# to catch collectl's socket I/O errors, noting graphite.ph sets its own handler
$SIG{"PIPE"}=\&sigPipe     if $address ne '';

$flushTime=($flush ne '') ? time+$flush : 0;

# intervals...  note that if no main interval specified, we use
# interval2 (if defined OR if only doing slabs/procs) and if not 
# that, interval3. Also, if there is an interval3, interval3 IS defined, so we
# have to compare it to ''.  Also note that since newlog() can change subsys
# we need to wait until after we call it to do interval/limit validation.
# be sure to ignore interval error checks for --showcolheader
$origInterval=$interval;
($interval, $interval2, $interval3)=split(/:/, $interval);
if (!$showColFlag)
{
  error("interval2 only applies to -s y,Y or Z")
    if defined($interval2) && $interval2 ne '' && $subsys!~/[yYZ]/;
  error("interval2 must be >= interval1")
      if defined($interval) && defined($interval2) && $interval2 ne '' && $interval>$interval2;
}
$interval2=$Interval2   if !defined($interval2);
$interval3=$Interval3   if !defined($interval3);
$interval=$interval2    if $origInterval=~/^:/ || ($subsys=~/^[yz]+$/i && $interval!=0);
$interval=$interval3    if $origInterval=~/^::/;

if ($interval!=0)
{
  if ($subsys=~/[yYZ]/)
  {
    error("interval2 must be >= main interval")
	if $interval2<$interval;
    error("interval2 must be the same as interval1 in --top mode")
        if $numTop && $interval!=$interval2;
    $limit2=$interval2/$interval;
    error("interval2 must be a multiple of main interval")
	if $limit2!=int($interval2/$interval);
  }
  if ($subsys=~/E/)
  {
    error("interval3 must be >= main interval")
	if $interval3<$interval;
    $limit3=$interval3/$interval;
    error("interval3 must be a multiple of main interval")
	if $limit3!=int($interval3/$interval);
  }
}
else
{
  # While we don't want any pauses, we also want to limit the number of collections
  # to the same number as would be taken during normal activities.  The magic here 
  # is we can only get here is if $userInterval is not null.  By default we assume
  # the ratios between ints 1/2/3 to be 1/6/30, but if i2 or i3 specified use those
  # as the ratios, not actual intervals.  eg  for -i5:20, use -i0:4
  my ($ui, $ui2, $ui3)=split(/:/, $userInterval);
  $ui2=''    if !defined($ui2);
  $ui3=''    if !defined($ui3);

  $limit2=($ui2 eq '') ?  6 : $ui2;
  $limit3=($ui3 eq '') ? 30 : $ui3;
  $interval2=$interval3=0;
  print "Interval Lim2: $limit2  Lim3: $limit3\n"    if $debug & 1;

  # make sure no 'bogus network speed' errors
  $DefNetSpeed=0;
}

if ($tworawFlag || $groupFlag)
{
  error("-G/--group has been replaced with --tworaw")           if $groupFlag;
  error("--tworaw require BOTH process and non-procss data")    if !$recFlag0 || !$recFlag1;
  error("--tworaw requires data collection to a file")          if  $filename eq '';

  # DUE to what seems to be a bug in zlib 2.02 (and maybe others), you cannot flush a buffer
  # twice in a row w/o writing to it.  A shorter interval causes that to happen to rawp.gz.
  error("cannot use -F0 with --tworaw when interval1 not equal interval2")             if !$flush && $interval!=$interval2;
  error("flush time cannot be < process collection interval, when using --tworaw")     if  $flush && $flush<$interval2;
}

# Note that even if printing in plotting mode to terminal we STILL call newlog
# because that points the LOG, DSK, etc filehandles at STDOUT
# Also, note that in somecase we set non-compressed files to autoflush
$autoFlush=1    if $flush ne '' && $flush<=$interval && !$zFlag;
newLog($filename, "", "", "", "", "")    if ($filename ne '' || $plotFlag);

# We want all final runtime parameters defined before doing this
if ($showHeaderFlag && $playback eq '')
{
  initRecord();
  my $temp=buildCommonHeader(0, undef);
  printText($temp);
  exit(0);
}

# If HiRes had been loaded and we're NOT doing 'time' tests, we want to 
# align each interval via sigalrm.  We HAVE to clear doneFlag here rather
# than at loop top because when collectl receives a sigterm it sets the flag
# and we don't want to set it back to 0. 
$doneFlag=0;
if ($hiResFlag && $interval!=0)
{
  # Default for deamons is to always align to the primary interval
  $alignFlag=1    if $daemonFlag;

  # sampling is calculated as multiples of a base time and we set that
  # time such that our next sample will occur on the next whole second,
  # just to make integer sampling align on second boundaries
  $AlignInt=$interval;
  $BaseTime=(time-$AlignInt+1)*1000000;

  # For aligned time we want to align on either the primary interval OR if
  # we're monitoring for processes or slabs, on the secondary one.  To make
  # all sample times align no matter when they were started, we align based
  # on a time of 0 which is 00:00:00 on Jan 1, 1970 GMT
  if ($alignFlag)
  {
    $AlignInt=($subsys=~/[yz]/i) ? $interval2 : $interval;
    $BaseTime=0;
  }

  # Point to our alarm handler and set up some u-constants
  $SIG{"ALRM"}=\&sigAlrm;
  $uInterval=$interval*1000000;

  # Now we can enable our alarm and sleep for at least a full interval, from
  # which we'll awake by a 'sigalrm'.  The first time thought is based on our
  # alignment, which may be '$interval2', but after that it's always '$interval'
  # Also note use of arg2 to note first call since arg1 always set to 'ALRM'
  # when it fires normally.
  $uAlignInt=$AlignInt*1000000;
  sigAlrm(undef, 1);
  sleep $AlignInt+1;
  $uAlignInt=$uInterval;
  sigAlrm();    # we're now aligned so reset timer
}

if ($debug & 1 && $options=~/x/i)
{
  $temp=$limBool ? "AND" : "OR";
  print "Exception Processing In Effect -- SVC: $limSVC $temp IOS: $limIOS ".
        "LusKBS: $LimLusKBS LusReints: $LimLusReints\n"
}

# remind user we always wait until second sample before producing results
# if only yY, Z or E or both, we don't wait for the standard interval
$temp=$interval;
$temp=$interval2    if $subsys=~/^[EyYZ]+$/;
$temp=$interval3    if $subsys eq 'E';
print "waiting for $temp second sample...\n"    if $filename eq "" && !$quietFlag;

# Need to make sure proc's and env's align with printing of other vars first 
# time.  In other words, do the first read immediately.
$counted2=($subsys=~/[yYZ]/) ? $limit2-1 : 0;
$counted3=($subsys=~/E/)     ? $limit3-1 : 0;

# Figure out how many intervals we want to check for lustre config changes,
# noting that in the debugging case where the interval is 0, we calculate it
# based on a day's worth of seconds.
$lustreCheckCounter=0;
$lustreCheckIntervals=($interval!=0) ? 
    int($lustreConfigInt/$interval) : int($count/(86400/$lustreConfigInt));
$lustreCheckIntervals=1    if $lustreCheckIntervals==0;
print "Lustre Check Intervals: $lustreCheckIntervals\n"    if $debug & 8;

# Looks like only HP-SFS should skip leading 7 fields of client OST data
my $lustreCltOstSkip=($sfsVersion ne '') ? 7 : 0;

# Same thing (sort of) for interconnect interval
$interConnectCounter=0;
$interConnectIntervals=($interval!=0) ? 
    int($InterConnectInt/$interval) : int($count/(86400/$InterConnectInt));
$interConnectIntervals=1    if $interConnectIntervals==0;
print "InterConnect Interval: $interConnectIntervals\n"    if $debug & 2;

if ($options=~/i/)
{
  my $temp=buildCommonHeader(0, undef);
  printText($temp);
}

# Wait until the last minute to set up the scrolling region so if we crap out
# earlier we haven't screwed up the terminal.
printf "%c[3;%dr", 27, $scrollEnd    if $scrollEnd;

#    M a i n    P r o c e s s i n g    L o o p

# This is where efficiency really counts
my $lastFirstPid=0;
for (; $count!=0 && !$doneFlag; $count--)
{
  # When in server mode we always need to check for readable socket
  # but be sure to do without any timeout
  if ($serverFlag)
  {
    print "Looking for connection...\n"    if $debug & 64;
    if ($newHandle=($select->can_read(0))[0])
    {
      print "Socket 'can read'\n"    if $debug & 64;
      if ($newHandle==$sockServer)
      {
        $socket=$sockServer->accept() || logmsg('F', "Couldn't accept socket request.  Reason: $!");
	$select->add($socket);
        push @sockets, $socket;
        my $client=inet_ntoa((sockaddr_in(getpeername($socket)))[1]);
	logmsg('I', "New socket connection from $client");
      }
      else
      {
        $socket=$newHandle;
        my $message=<$socket>;
        if (!defined($message))
        {
          logmsg('W', "Client closed socket");
 	  for (my $i=0; $i<scalar(@sockets); $i++)
	  {
	    splice @sockets, $i, 1    if $sockets[$i]==$socket;
	  }
          $select->remove($socket);
          $socket->close();
        }
        else
        {
  	  print "Received: $message"    if $debug & 64;
        }
      }
    }
  }

  # Use the same value for seconds for the entire cycle
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

  #    T i m e    F o r    a    N e w    L o g ?

  if ($logToFileFlag && $rollSecs)
  {
    # if time to roll, do so and recalculate next roll time.
    if ($intSeconds ge $rollSecs)
    {
      # We need to make sure each logfile has headers.  Since this flag is used interactively
      # as well we can't just clear it here.
      $zlibErrors=$headersPrinted=0;
      newLog($filename, "", "", "", "", "");
      $rollSecs+=$rollIncr*60;

      # Just like the logic above to calculate the time of our first roll, we
      # need to see if we're going to cross a time change boundary
      if ($rollIncr>60)
      {
        ($sec, $min, $hour, $day, $mon, $year)=localtime($rollSecs);

	#print "EXP: $expectedHour  HOUR: $hour\n";
        my $diff=($expectedHour-$hour);
        $diff=1    if $diff==-23;
        $rollSecs+=$diff*3600;
        $expectedHour+=$rollIncr/60;
        $expectedHour%=24;
        logmsg("I", "Time change!  Did you remember to change your watch?")    if $diff!=0;
      }
      logmsg("I", "Logs rolled");
      initDay();
    }
  }

  #    G a t h e r    S T A T S

  # This is the section of code that needs to be reasonably efficient.  but first, start  
  # the interval with a time marker noting we have to first make sure we're padding with
  # 0's, then truncate to 2 digit precision noting is a rawp file we only write a marker
  # during interval2
  $counted2++;
  $fullTime=sprintf("%d.%06d", $intSeconds, $intUsecs);
  record(1, sprintf(">>> %.3f <<<\n", $fullTime))               if $recFlag0;
  record(1, sprintf(">>> %.3f <<<\n", $fullTime), undef, 1)     if $recFlag1 && $counted2==$limit2;

  ##############################################################
  #    S t a n d a r d    I n t e r v a l    P r o c e s s i n g
  ##############################################################

  if ($bFlag || $BFlag)
  {
    getProc(0, "/proc/buddyinfo", "buddy");
  }

  if ($cFlag || $CFlag || $dFlag || $DFlag)
  {
    # Too crazy to do in getProc() though maybe someday should be moved there
    open PROC, "</proc/stat" or logmsg("F", "Couldn't open '/proc/stat'");
    while ($line=<PROC>)
    {
      last             if $line=~/^kstat/;
      record(2, $line)
	  if (( ($cFlag || $CFlag) && $line=~/^cpu|^ctx|^proc/) ||
	      ( $DFlag && !$hiResFlag && $line=~/^cpu /));
      record(2, "$1\n")
          if ($cFlag || $CFlag) && $line=~/(^intr \d+)/;
    }
    close PROC;
  }

  if ($jFlag || $JFlag)
  {
    getProc(0, '/proc/interrupts', 'int', 1);
  }

  if ($dFlag || $DFlag)
  {
    getProc(9, "/proc/diskstats", "disk");
  }

  if ($cFlag || $CFlag)
  {
    getProc(0, "/proc/loadavg", "load");
  }

  if ($tFlag || $TFlag)
  {
    getProc(20, "/proc/net/netstat", 'tcp')    if $tcpFilt=~/[IT]/;
    getProc(21, "/proc/net/snmp", 'tcp')       if $tcpFilt=~/[cimtu]/;
  }

  if ($iFlag)
  {
    getProc(0, "/proc/sys/fs/dentry-state", "fs-ds")    if $dentryFlag;
    getProc(0, "/proc/sys/fs/inode-nr", "fs-is")        if $inodeFlag;
    getProc(0, "/proc/sys/fs/file-nr", "fs-fnr")        if $filenrFlag;
  }

  if ($lFlag || $LFlag || $lustOpts=~/O/)
  {
    # Check to see if any services changed and if they did, we may need
    # a new logfile as well.
    if (++$lustreCheckCounter==$lustreCheckIntervals)
    {
      newLog($filename, "", "", "", "", "")
	  if lustreCheckClt()+lustreCheckOst()+lustreCheckMds()>0 && $filename ne '';
      $lustreCheckCounter=0;
    }
    # This data actually applies to both MDS and OSS servers and if
    # both services are running on the same node we're only going to
    # want to collect it once.
    if ($lustOpts=~/D/ && ($NumMds || $OstFlag))
    {
      my $diskNum=0;
      foreach my $diskname (@LusDiskNames)
      {
        # Note that for scsi, we read the whole thing and for cciss
        # quit when we see the line with 'index' in it.  Also note that
        # for sfs V2.2 we need to skip more for cciss than sd disks
        $diskSkip=($sfsVersion lt '2.2' || $LusDiskDir=~/sd_iostats/) ? 2 : 14;
        $statfile="$LusDiskDir/$diskname";
        getProc(2, $statfile, "LUS-d_$diskNum", $diskSkip, undef, 'index');
        $diskNum++;
      }
    }

    # OST Processing
    if ($OstFlag)
    {
      # Note we ALWAYS read the base ost data
      for ($ostNum=0; $ostNum<$NumOst; $ostNum++)
      {
        $dirspec="/proc/fs/lustre/obdfilter/$lustreOstSubdirs[$ostNum]";
        getProc(1, "$dirspec/stats", "OST_$ostNum", undef, undef, "^io");

        # for versions of SFS prior to 2.2, there are only 9 buckets of BRW data.
        getProc(2, "$dirspec/brw_stats", "OST-b_$ostNum", 4, $numBrwBuckets)
	  if $lustOpts=~/B/;
      }
    }

    # MDS Processing
    if ($NumMds)
    {
      my $type=($cfsVersion lt '1.6.0') ? 'MDT' : 'MDS';
      getProc(3, "/proc/fs/lustre/mdt/$type/mds/stats", "MDS");
    }

    # CLIENT Processing
    if ($CltFlag)
    {
      $fsNum=0;
      foreach $subdir (@lustreCltDirs)
      {
	# For vanilla -sl we only need read/write info, but lets grab metadata file 
        # we're at it.  In the case of --lustopts R, we also want readahead stats
        getProc(11, "/proc/fs/lustre/llite/$subdir/stats", "LLITE:$fsNum", 1, 19);
        getProc(0,  "/proc/fs/lustre/llite/$subdir/read_ahead_stats", "LLITE_RA:$fsNum", 1)
	    if $lustOpts=~/R/;
	$fsNum++;
      }

      # RPC stats are optional for both clients and servers
      if ($lustOpts=~/B/)
      {
        for ($index=0; $index<$NumLustreCltOsts; $index++)
        {
          getProc(2, "$lustreCltOstDirs[$index]/rpc_stats", "LLITE_RPC:$index", 8, 11);
        }
      }
      # Client OST detail data
      if ($lustOpts=~/O/)
      {
        for ($index=0; $index<$NumLustreCltOsts; $index++)
        {
          getProc(12, "$lustreCltOstDirs[$index]/stats", "LLDET:$index ", $lustreCltOstSkip);
        }
      }
    }
  }

  # even if /proc not there (nothing exported/mounted), it could
  # show up later so we need to be sure and look every time
  if ($fFlag || $FFlag)
  {
    getProc(8, '/proc/net/rpc/nfs',  "nfsc-")    if $nfsCFlag;
    getProc(8, '/proc/net/rpc/nfsd', "nfss-")    if $nfsSFlag;
  }

  if ($mFlag)
  {
    getProc(0, "/proc/meminfo", "");
    getProc(5, "/proc/vmstat",  "");
  }

  # NOTE - unlike other detail data this is only recorded when explicitly requested
  if ($MFlag)
  {
    for (my $i=0; $i<$CpuNodes; $i++)
    {
      # skip first line which is blank, noting 'Node X' is already part of data
      getProc(0, "/sys/devices/system/node/node$i/meminfo", "numai", 1);

      # only if we want hits, adds about 2 secs for 2 node home box
      getProc(0, "/sys/devices/system/node/node$i/numastat", "numas Node $i");
    }
  }

  if ($sFlag)
  {
    getProc(0, "/proc/net/sockstat", "sock");
  }

  if ($nFlag || $NFlag)
  {
    if ($rawNetFilter eq '')
    { getProc(0, "/proc/net/dev", "Net", 2); }
    else
    { getProc(7, "/proc/net/dev", "Net", 2); }
  }

  if ($xFlag || $XFlag)
  {
    # Whenever we hit the end of interconnect checking interval we need to 
    # see if any of them changed configuration (such as an IB port fail-over)
    # NOTE - we do the $filename test last so we ALWAYS do the elan/ib checks
    # even if printing to terminal.
    if (++$interConnectCounter==$interConnectIntervals)
    {
      newLog($filename, "", "", "", "", "")
	  if (($quadricsFlag && elanCheck()) || ($mellanoxFlag && ibCheck()))
	      && $filename ne '';
      $interConnectCounter=0;
    }

    # only if there is indeed quadric stats detected
    if ($quadricsFlag && $NumXRails)
    {
      for ($i=0; $i<$NumXRails; $i++)
      {
        getProc(0, "/proc/qsnet/ep/rail$i/stats", "Elan$i");
      }
    }

    if ($mellanoxFlag && $NumHCAs)
    {
      for ($i=0; $i<$NumHCAs; $i++)
      {
        if ( -e $SysIB ) 
        { 
          if ( -e $PQuery )
	  {
            foreach $j (1..2)
            {
              if ($HCAPorts[$i][$j])  # Make sure it has an active port
              {
		getExec(1, "$PQuery -r $HCALids[$i][$j] $j 0xf000", "ib$i-$j");
	      }
            }
          }
        }
        elsif ( -e $VoltaireStats )
        {
	  # If Voltaire ever supports multiple HCAs, we'll need the 
	  # uncommented code instead
	  getProc(0, $VoltaireStats, 'ib0', 3, 2);
	  #getProc(0, "/proc/voltaire/ib$i/stats", "ib$i", 3, 2);
	}
        else
        {
          # Currently only 1 port is active, but if more are, we need to
          # deal with them
          foreach $j (1..2)
          {
            if ($HCAPorts[$i][$j])  # Make sure it has an active port
            {
              # Grab counters and do an immediate reset of them
              getExec(2, "$PCounter -h $HCAName[$i] -p $j", "ib$i-$j");
	      `$PCounter -h $HCAName[$i] -p $j -s 5 >/dev/null`;
	     }
          }
        }
      }
    }
  }

  # Custom data import
  logdiag("begin import data")      if ($utimeMask & 1) && $impNumMods;
  for (my $i=0; $i<$impNumMods; $i++) { &{$impGetData[$i]}(); }

  logdiag("interval1 done")   if $utimeMask & 1;

  #############################################
  #    I n t e r v a l 2    P r o c e s s i n g
  #############################################

  if (($yFlag || $YFlag || $ZFlag) && $counted2==$limit2)
  {
    if ($yFlag || $YFlag)
    {
      # NOTE - $SlabGetProc is either 99 for all slabs or 14 for selective
      if ($slabinfoFlag)
      {
        getProc($SlabGetProc, "/proc/slabinfo", "Slab", 2);
      }
      else
      {
	# Reading the whole directory and skipping links via the 'skip' hash
        # is only about about 1/2 second slower over the day so let's just do it.
        opendir SLUBDIR, "/sys/slab" or logmsg('E', "Couldn't open '/sys/slub'");
        while ($slab=readdir SLUBDIR)
	{
	  next    if $slab=~/^\./;
	  next    if $slabFilt ne '' && !defined($slabdata{$slab});
	  next    if defined($slabskip{$slab});

	  # See if a new slab appeared, noting this doesn't apply when using
          # --slabfilt because of the optimization 'next' for '$slabFilt' above
	  # also remember since we're only looking at root slabs, we'll never
          # discover 'linked' ones
	  if (!defined($slabdata{$slab}))
          {
	    $newSlabFlag=1;
	    logmsg("W", "New slab detected: $slab");
  	  }

	  # Whenever there are 'new' slabs to read (which certainly includes the first 
          # full pass or any time we change log files) read constants before reading
          # variant data.
	  getSys('Slab', '/sys/slab', $slab, 1, ['object_size', 'slab_size', 'order','objs_per_slab'])
	      if $firstPass || $newRawSlabFlag || $newSlabFlag;
	  getSys('Slab', '/sys/slab', $slab, 1, ['objects', 'slabs']);
	  $newSlabFlag=0;
	}
      }
    }

    if ($ZFlag)
    {
      # need to know when we're looking at the first proc of this interval
      $firstProcCycle=1;

      # Process Monitoring RULES
      # if --procopt p OR --procfilt p and only pids
      # - only look at pids in %pidProc and nothing more
      #   - if + and no --procopt t, never look for new threads
      #   - if --procopt t, always look for new threads whether + or not
      # else always look for new processes
      # - if --procopt p look for threads for each pid
      undef %pidSeen;
      if ($pidOnlyFlag)
      {
        foreach $pid (keys %pidProc)
        {
          # When looking at threads, we read ALL data from /proc/pid/task/pid
          # rather than /proc/pid so we can be assured we only seeing stats
          # for the main process.  Later on too...
          # But also note earliest kernels only support process io under /proc/pid
          $task=$taskio=($allThreadFlag || $oneThreadFlag) ? "$pid/task/" : '';
          $taskio=''    if !-e "/proc/$pid/task/$pid/io";

          # note that not everyone has 'Vm' fields in status so we need
	  # special checks.  Also note both here and below whenever we process a pid
          # and not --procopt p (we could have gotten here via --procfilt p...) and 
          # we're doing threads on this pid, see if any new threads showed up.  If 
          # this gets much more involved it should probably become a sub since we do 
          # it below too.
	  $pidSeen{$pid}=getProc(17, "/proc/$task/$pid/stat",    "proc:$pid stat", undef, 1);
	  $pidSeen{$pid}=getProc(13, "/proc/$task/$pid/status",  "proc:$pid")
	      if $pidSeen{$pid}==1;
	  $pidSeen{$pid}=getProc(16, "/proc/$task/$pid/cmdline", "proc:$pid cmd", undef, 1)
	      if $pidSeen{$pid}==1;
	  $pidSeen{$pid}=getProc(17, "/proc/$taskio/$pid/io", "proc:$pid io")
	      if $pidSeen{$pid}==1 && $processIOFlag && ($rootFlag || -r "/proc/$taskio/$pid/io");
	  findThreads($pid)     if $allThreadFlag || ($oneThreadFlag && $procOpts!~/p/ && $pidThreads{$pid});
        }
      }
      else
      {
        opendir DIR, "/proc" or logmsg("F", "Couldn't open /proc");
        while ($pid=readdir(DIR))
        {
          next    if $pid=~/^\./;    # skip . and ..
          next    if $pid!~/^\d/;    # skip not pids
	  next    if defined($pidSkip{$pid});
	  next    if !defined($pidProc{$pid}) && pidNew($pid)==0;

          # see comment in previous block
          $task=$taskio=($allThreadFlag || $oneThreadFlag) ? "$pid/task/" : '';
          $taskio=''    if !-e "/proc/$pid/task/$pid/io";

  	  print "%%% READPID $pid\n"    if $debug & 256;
          $pidSeen{$pid}=getProc(17, "/proc/$task/$pid/stat",    "proc:$pid stat", undef, 1);
          $pidSeen{$pid}=getProc(13, "/proc/$task/$pid/status",  "proc:$pid")
	      if $pidSeen{$pid}==1;
	  $pidSeen{$pid}=getProc(16, "/proc/$task/$pid/cmdline", "proc:$pid cmd", undef, 1)
	      if $pidSeen{$pid}==1;
	  $pidSeen{$pid}=getProc(17, "/proc/$taskio/$pid/io", "proc:$pid io")
	      if $pidSeen{$pid}==1 && $processIOFlag && ($rootFlag || -r "/proc/$taskio/$pid/io");
	  findThreads($pid)     if $allThreadFlag || ($oneThreadFlag && $procOpts!~/p/ && $pidThreads{$pid});
        }
      }

      # if --procopts t OR '+' with --procfilt
      if ($allThreadFlag || $oneThreadFlag)
      {
        foreach $pid (keys %tpidProc)
        {
	  # Location of thread stats is below parent, but I/O only there when kernel patched!
          $task=$taskio=($allThreadFlag || $oneThreadFlag) ? "$pid/task/" : '';
          $taskio=''    if !-e "/proc/$pid/task/$pid/io";

	  # The 'T' lets the processing code know it's a thread for formatting purposes
  	  $tpidSeen{$pid}=getProc(17, "/proc/$task/$pid/stat",   "procT:$pid stat", undef, 1);
	  $tpidSeen{$pid}=getProc(13, "/proc/$task/$pid/status", "procT:$pid")
	      if $tpidSeen{$pid}==1; 
	  $tpidSeen{$pid}=getProc(17, "/proc/$taskio/$pid/io", "procT:$pid io")
	      if $tpidSeen{$pid}==1 && $processIOFlag && ($rootFlag || -r "/proc/$taskio/$pid/io");
        }
      }

      # how else will we know if a process exited?
      # This will also clean up stale thread pids as well.
      cleanStalePids();
    }
    $counted2=0;
    logdiag("interval2 done")    if $utimeMask & 1;
  }

  #############################################
  #    I n t e r v a l 3    P r o c e s s i n g
  #############################################

  if ($EFlag && ++$counted3==$limit3)
  {
    # On the off chance someone deleted it (how do you say overkill?)
    if (!-e $IpmiCache)
    {
      logmsg('E', "Who deleted my cache file '$IpmiCache'?");
      logmsg('I', "Recreated missing cache file");
      $command="$Ipmitool sdr dump $IpmiCache";
      `$command`;
    }

    # About the same overhead to invoke ipmitool twice but much less elapsed time.
    getExec(3, "$Ipmitool -c -S $IpmiCache exec $ipmiExec", 'ipmi');
    $counted3=0;
    logdiag("interval3 done")    if $utimeMask & 1;
  }

  ###########################################################
  #    E n d    O f    I n t e r v a l    P r o c e s s i n g
  ###########################################################

  # if printing to terminal OR generating data in plot format (or both)
  # we need to wait until the end of the interval so complete data is in hand
  if (!$logToFileFlag || $plotFlag || $export ne '')
  {
    $fullTime=sprintf("%d.%06d", $intSeconds, $intUsecs);
    intervalEnd(sprintf("%.3f", $fullTime));
    logdiag('interval processed')    if $utimeMask & 1;
  }

  # If there was a disk configuration change and writing to plot files (changes
  # can't be detected when writing to raw file), create new log files.
  if ($diskChangeFlag && $plotFlag && $filename ne '')
  {
    logmsg('I', 'Creating new log file')                                          if $options=~/u/;
    logmsg('W', 'all data mixed in same file! use -ou to force unique files!')    if $options!~/u/;
    newLog($filename, "", "", "", "", "");
  }
  $diskChangeFlag=0;

  # If our parent's pid went away we're done, unless --nohup specified or we're a daemon
  if (!-e "/proc/$myPpid" && !$daemonFlag && !$nohupFlag)
  {
    logmsg('W', 'parent exited and --nohup not specified');
    last;
  }

  # if we'll pass the end time while asleep, just get out now.
  last    if $endSecs && ($intSeconds+$interval)>$endSecs;

  # NOTE - I tried used select() as timer when no HiRes but got premature
  # wakeups on early 2.6 testing and so went back to sleep().  Also, in
  # case we lose our wakeup signal, only sleep as long as requested noting
  # we SHOULD get woken up before this timer expires since we already used
  # up part of our interval with data collection
  flushBuffers()    if !$autoFlush && $flushTime && time>=$flushTime;
  if ($interval!=0)
  {
    sleep $interval                    if !$hiResFlag;
    Time::HiRes::usleep($uInterval)    if  $hiResFlag;
  }
  $firstPass=0;
  $newRawSlabFlag=0    if $counted2==0;    # interval 2 just processed
  next;
}

# the only easy way to tell a complete interval is by writing a marker, with
# not time, since we don't need it anyway.
if ($hiResFlag)
{
  ($intSeconds, $intUsecs)=Time::HiRes::gettimeofday();
  $fullTime=sprintf("%d.%06d",  $intSeconds, $intUsecs);
}
else
{
  $fullTime=time;
}
record(1, sprintf(">>> %.3f <<<\n", $fullTime))               if $recFlag0;
record(1, sprintf(">>> %.3f <<<\n", $fullTime), undef, 1)     if $recFlag1;

# close logs cleanly and turn echo back on because when 'brief' we turned it off.
closeLogs($subsys);
unlink $PidFile       if $daemonFlag;
`stty echo`           if !$PcFlag && $termFlag && !$backFlag;
printf("%c[r", 27)    if $numTop && $userSubsys ne '';
printf "%c[%d;H\n", 27, $scrollEnd+$numTop+2    if $numTop;
logmsg("I", "Terminating...");
logsys("Terminating...");

sub preprocSwitches
{
  my $switches='';
  foreach $switch (@ARGV)
  {
    # Cleaner to not allow -top and force --top
    error("invalid switch '$switch'.  did you mean -$switch?")
         if $switch=~/^-to/;

    # multichar switches COULD be single char switch and option
    if ($switch=~/^-/ && length($switch)>2)
    {
      $use=substr($switch, 0, 2).' '.substr($switch,2);
      error("invalid switch '$switch'.  did you mean -$switch?  if not use '$use'")
	  if $switch=~/^-al|^-ad|^-be|^-co|-^de|^-de|^-en|^-fl|^-he|^-no|^-in|^-ra/;
      error("invalid switch '$switch'.  did you mean -$switch?  if not use '$use'")
	  if $switch=~/^-li|^-lu|^-me|-^ni|^-op|^-su|^-ro|^-ru|^-ti|^-wi|^-pr/;
    }
    $switches.="$switch ";
  }
  return($switches);
}

# This only effects multiple files for the same system on the same day.
# In most cases, those log files will have been run with the same parameters
# and as a result when their output is simply merged into single 'tab' or 
# detail files.  However on rare occasions, the configurations will NOT be the
# same and the purpose of this function is to recognize that and change the
# processing parameters according, if possible.  The best example of this is
# if one generates one log based on -scd and a second on -scm.  By forcing
# the processing of both to be -scdm, the resultant 'tab' file will contain
# everything.  Alas, things get more complicated with detail files and even
# more so with lustre detail files if filesystems are mounted/umounted, etc.
# In any event, the details are in the code...
#
# NOTE - if any files cannot be processed, none will and the user will be
#        require to change command options
sub preprocessPlayback
{
  my $playbackref=shift; 
  my ($selected, $header, $i);
  my ($lastPrefix, $thisSubSys, $thisInterval, $lastInterval, $mergedInterval);
  my ($lastSubSys, $lastSubOpt, $lastNfs, $lastDisks, $lastLustreConfig, $lastLustreSubSys);
  local ($configChange, $filePrefix, $file);

  $selected=0;
  $configChange=0;
  $lastPrefix=$lastLustreConfig=$lastInterval=$mergedInterval="";
  foreach $file (@$playbackref)
  {
    print "Preprocessing: $file\n"    if $debug & 2048;

    # need to do individual file checks in case filespec matches bad files
    if ($file!~/(.*-\d{8})-\d{6}\.raw[p]*/)
    {
      $preprocErrors{$file}="I:its name is wrong format";
      next;
    }
    $filePrefix=$1;
    $playback{$filePrefix}->{flags}|=0    if !defined($playback{$filePrefix}->{flags});

    if (-z $file)
    {
      $preprocErrors{$file}="I:its size is zero";
      next;
    }

    if ($file!~/raw$|rawp$|gz$/)
    {
      $preprocErrors{$file}="I:it doesn't end in 'raw', 'rawp' or 'gz'";
      next;
    }

    # If any files in 'gz' format, make sure we can cope.
    $zInFlag=0;
    if ($file=~/gz$/ && !$zlibFlag)
    {
      $zInFlag=1;
      $preprocErrors{$file}="E:Zlib not installed";
      next;
    }

    # Read header - cleanup code in newlog: see call to getHeader in newLog()
    # Set flags based on whether raw or rawp
    $header=getHeader($file);
    $header=~/SubSys:\s+(\S+)/;
    $thisSubSys=$1;

    $playback{$filePrefix}->{flags}|=1    if $file=~/\.rawp/;
    $playback{$filePrefix}->{flags}|=2    if $file!~/\.rawp/;

    # We finally dropped SubOpts and nfsOpts from the header in V3.2.1-5, but not LustOpts
    my $subOpts=($header=~/SubOpts:\s+(\S*)\s+Options:/) ? $1 : '';
    my $thisNfsOpts= ($header=~/NfsOpts: (\S*)\s*Interval/)   ? $1 : $subOpts;
    my $thisDisks=   ($header=~/DiskNames: (.*)/) ? $1 : '';
    my $thisLustOpts=($header=~/LustOpts: (\S*)\s*Services/) ? $1 : $subOpts;
    $thisNfsOpts=~s/[BDMORcom]//g;    # in case it came from SubOpts remove lustre stuff, 'com' for pre-lustsvc
    $thisLustOpts=~s/[234C]//g;       # ditto for nfs stuff

    $header=~/Interval:\s+(\S+)/;
    $thisInterval=$1;

    # If user specified '--procopts i' and file doesn't have data, we can't process it
    $flags=($header=~/Flags:\s+(\S+)/) ? $1 : '';
    if ($procOpts=~/i/ && $flags!~/i/)
    {
      $preprocErrors{$file}="E:--procopts i requested but data not present in file";
      next;
    }

    # we need to merge intervals if user has selected her own AND set a flag so
    # changeConfig() will update %playbackSettings{} correctly
    # NOTE - this has never been allowed as -i not allowed in playback
    if ($userInterval ne '')
    {
      $configChange=4;   # will cause config change processing AND -m notice
      $mergedInterval=mergeIntervals($thisInterval, $mergedInterval);

      # on subsequent files, we need to check for interval consistency
      if ($filePrefix eq $lastPrefix)
      {
        print "Merged Intervals: $mergedInterval\n"    if $debug & 2048;
	my ($int1, $int2, $int3)=   split(/:/, $mergedInterval);
	my ($uint1, $uint2, $uint3)=split(/:/, $userInterval);
        $preprocErrors{$file}="E:common interval '$mergedInterval' not self-consistent"
	    if (defined($int2) && ($int1>$int2 || int($int2/$int1)*$int1!=$int2)) ||
               (defined($int3) && ($int1>$int3 || int($int3/$int1)*$int1!=$int3));

        $preprocErrors{$file}="E:common interval '$mergedInterval' has value(s) > $userInterval"
	    if $uint1<$int1 || 
  	       (defined($uint2) && defined($int2) && $unint2<$int2) ||
	       (defined($uint3) && defined($int3) && $unint3<$int3);

        $preprocErrors{$file}="E:common interval '$mergedInterval' not consistent with $userInterval"
            if (int($uint1/$int1)*$int1!=$uint1) ||
	       (defined($unint2) && defined($int2) && (int($uint2/$int2)*$int2!=$uint2)) ||
  	       (defined($unint3) && defined($int3) && (int($uint3/$int3)*$int3!=$uint3));
      }
    }

    print "File: $file  FileSubSys: $thisSubSys  NfsOpts: $thisNfsOpts  LustOpts: $thisLustOpts\n"
	if $debug & 2048;

    # note that -s and --lustsvc override anything in the files AND in case -s contained +/- 
    # we need to do a merge rather than a wholesale replace     
    $thisSubSys=mergeSubsys($thisSubSys);
    $lastLustreConfig=$lustreSvcs    if $lustreSvcs ne '';
    $lastLustreConfig.='|||';

    # it's only if the prefix for this file is the same as the last that
    # we have to do all our interval merging and consistency checks.
    $selected++;
    if ($filePrefix ne $lastPrefix)
    {
      configChange($lastPrefix, $lastSubSys, $lastLustreConfig, $mergedInterval)
	  if $lastPrefix ne '';

      # New prefix, so initialize for subsequent tests
      $newPrefix=1;
      $configChange=0;
      $mergedInterval='';

      # this returns client/server and version or null string
      $thisNfs=checkNfs("", $thisSubSys, $thisNfsOpts);

      ($thisLustreConfig, $lastLustOpts)=checkLustre('', $header, '', $thisLustOpts);

      $lastDisks=checkDisks('', $thisDisks)    if $thisSubSys=~/D/;

      # useful for telling what may have changed
      $playback{$filePrefix}->{subsysFirst}=$thisSubSys;
    }
    else    # subsequent files (if any) for same prefix-date
    {
      # subsystem checks
      $newPrefix=0;
      $thisSubSys=checkSubSys($lastSubSys, $thisSubSys);
      $thisNfs=   checkNfs($thisNfs, $thisSubSys, $thisNfsOpts);

      ($thisLustreConfig, $lastLustOpts)=
	  checkLustre($lastLustreConfig, $header, $lastLustOpts, $thisLustOpts);

      $lastDisks=checkDisks($lastDisks, $thisDisks)    if $thisSubSys=~/D/;
    }
    $lastPrefix=$filePrefix;
    $lastSubSys=$thisSubSys;
    $lastLustreConfig=$thisLustreConfig;

    $playback{$filePrefix}->{subsys}=$thisSubSys;
  }

  # If multiple files for this prefix processed there are outstanding
  # potential changes we need to check for.
  configChange($lastPrefix, $lastSubSys, $lastLustreConfig, $mergedInterval)
      if $selected && !$newPrefix;
}

# if no -s, return default subsys
# if -s but no +/- return -s
# otherwise merge...
sub mergeSubsys
{
  my $default=shift;
 
  my $newSubsys=$default;
  if ($userSubsys ne '')
  {
    if ($userSubsys!~/[+-]/)
    {
      $newSubsys=$userSubsys;
    }
    else
    {
      if ($userSubsys=~/-(.*)/)
      {
        my $pat=$1;
        $pat=~s/\+.*//;         # if followed by '+' string
        $default=~s/[$pat]//g;  # remove matches
      }
      if ($userSubsys=~/\+(.*)/)
      {
        my $pat=$1;
        $pat=~s/-.*//;          # remove anything after '-' string
        $default.=$pat;         # add matches
      }
      $newSubsys=$default;
    }
  }
  return($newSubsys);
}

# This purpose of this routine is to look at the intervals from multiple headers
# and figured out what common intervals would be needed to process them all if the
# user wanted to override them.  In effect determine the 'least commmon interval',
# only I'm not going to be too precise since virtually all the time these files
# WILL have the same intervals and calculating the LCI will be a lot of work.
sub mergeIntervals
{
  my $interval=shift;
  my $merged=  shift;

  my ($mgr1, $mrg2, $mrg3)=split(/:/, $merged);
  my ($int1, $int2, $int3)=split(/:/, $interval);

  # if any intervals aren't in the merged list, simply move them in
  # which will always be the case the first time through
  $mrg1=$int1    if !defined($mrg1) || $mrg1 eq '';
  $mrg2=$int2    if !defined($mrg2) || $mrg2 eq '';
  $mrg3=$int3    if !defined($mrg3) || $mrg3 eq '';

  # get least common intervals, but only if new value defined
  $mrg1=lci($int1, $mrg1);
  $mrg2=lci($int2, $mrg2)    if defined($int2);
  $mrg3=lci($int3, $mrg3)    if defined($int3);

  # return the list of merged intervals
  $merged=$mrg1;
  $merged.=":$mrg2"    if defined($mrg2);
  $merged.=(defined($mrg2)) ? ":$mrg3" : "::$mrg3"    if defined($mrg3);
  return($merged);
}

sub lci
{
  my $new=shift;
  my $old=shift;

  $lci=$old;
  if ($new>$old)
  {
    # if a common multiple, use new interval for lci; other return their product 
    # which will be common but may NOT be the LEAST common!
    $lci=($new==int($new/$old)*$old) ? $new : $old*$new;
  }
  else
  {
    # same thing only see if $old a multiple of $new
    $lci=($old==int($old/$new)*$new) ? $old : $old*$new;
  }
}

sub configChange
{
  my $prefix=  shift;
  my $subsys=  shift;
  my $config=  shift;
  my $interval=shift;
  my ($services, $mdss, $osts, $clts);
  my ($i, $type, $names, $temp, $index);

  ($services, $mdss, $osts, $clts)=split(/\|/, $config);

  print "configChange() -- Pre: $prefix  Svcs: $services Mds: $mdss Osts: $osts Clts: $clts Int: $interval\n"
      if $debug & 8;

  # Usually there are no existing messages, but we gotta check...
  $index=defined($preprocMessages{$prefix}) ? $preprocMessages{$prefix} : 0;
  if ($configChange)
  {
    $preprocMessages{$prefix.'|'.$index++}="  -s overridden to '$subsys'"
	if $configChange & 1;
    $preprocMessages{$prefix.'|'.$index++}="  --lustsvr overridden to '$services'"
	if $configChange & 2;
    $preprocMessages{$prefix.'|'.$index++}="  -i overridden from '$interval' to '$userInterval'"
	if $configChange & 4;

    foreach $i (8,16,32)
    {
      next    if !($configChange & $i);
      if ($i==8)  { $types=$mdss; $temp="MDS"; }
      if ($i==16) { $types=$osts; $temp="OST"; }
      if ($i==32) { $types=$clts; $temp="Client"; }
      $preprocMessages{$prefix.'|'.$index++}="  combined Lustre $temp objects now '$types'";
    }
    $preprocMessages{$prefix}=$index;
    $playbackSettings{$prefix}="$subsys|$services|$mdss|$osts|$clts|$interval";
    print "Playback -- Prefix: $prefix  Settings: $playbackSettings{$prefix}\n"    if $debug & 2048;
  }

  # Send these to log if we're not running interactively and -m not specified
  for ($i=0; !$termFlag && !$msgFlag && $i<$index; $i++)
  {
    logmsg("W", $preprocMessages{$prefix.'|'.$i});
  }
  return;
}

sub checkSubSys
{
  my $lastSubSys=shift;
  my $thisSubSys=shift;
  my ($nextSubSys, $i);

  print "Check SubSys -- Last: $lastSubSys  This: $thisSubSys\n"
      if $debug & 2048;

  # if any differences between 'this' and 'last', we have a config change.
  my $temp1=$thisSubSys;
  $temp1=~s/[$lastSubSys]//g;    # remove 'last' from 'this'
  my $temp2=$lastSubSys;
  $temp2=~s/[$thisSubSys]//g;    # remove 'this' from 'last'
  $configChange|=1    if $temp1 ne '' || $temp2 ne '';

  # $temp1 contains any NEW subsys in current file, so add them to 'last'
  $lastSubSys.=$temp1;

  $preprocErrors{$file}="E:-P and details to terminal not allowed"
      if $lastSubSys=~/[A-Z]/ && $filename eq '' && $plotFlag;
 
  return($lastSubSys);  # has new sub-systems appended
}

sub checkSubsysOpts
{
  error("you cannot mix --slabopts with --top")  if $slabOpts ne '' && $topSlabFlag;
  error("invalid slab option in '$slabOpts'")    if $slabOpts ne '' && $slabOpts!~/^[sS]+$/;
  error("invalid env option in '$envOpts'")      if $envOpts ne ''  && $envOpts!~/^[fptCFMT\d]+$/;

  if ($procOpts ne '')
  {
    $procCmdWidth=($procOpts=~s/w(\d+)/w/) ? $1 : 1000;
    error("invalid process option '$procOpts'")                   if $procOpts!~/^[cfiImprRsStwxz]+$/;
    error("process options i and m are mutually exclusive")       if $procOpts=~/i/ && $procOpts=~/m/;
    error("your kernel doesn't support process extended info")    if $procOpts=~/x/ && !$processCtxFlag;
    error("--procopts z can only be used with --top")             if !$numTop && $procOpts=~/z/;
  }
  error("--procstate not one or more of 'DRSTWZ'")                if $procState ne '' && $procState!~/^[DRSTWZ]+$/;


  # it's possible this is not recognized as running a particular type of service
  # from the 'flag's if that service is isn't yet started and so we need
  # to check $lustreSvcs too.  Be sure to include '$userSubsys' in case -sl was
  # specified by the user and then disabled by collectl.
  error("--lustsvcs only applies to lustre")    
      if $lustreSvcs ne '' && $subsys!~/l/i && $userSubsys!~/l/i;
  my $cltFlag=($CltFlag || $lustreSvcs=~/c/i) ? 1 : 0;
  my $mdsFlag=($MdsFlag || $lustreSvcs=~/m/i) ? 1 : 0;
  my $ostFlag=($OstFlag || $lustreSvcs=~/o/i) ? 1 : 0;

  error("--lustopts only applies to lustre")                 if $lustOpts ne '' && $subsys!~/l/i;
  error("--lustopts B only applies to Lustre Clts/Osts")     if $lustOpts=~/B/ && !$ostFlag && !$cltFlag;
  error("--lustopts D only applies to Lustre OSTs/MDSs")     if $lustOpts=~/D/ && !$ostFlag && !$mdsFlag;
  error("--lustopts M only applies to Lustre Clients")       if $lustOpts=~/M/ && !$cltFlag;
  error("--lustopts R only applies to Lustre Clients")       if $lustOpts=~/R/ && !$cltFlag;
  error("--lustopts O only applies to client detail data")   if $lustOpts=~/O/ && (!$cltFlag || $subsys!~/L/);
  error("you cannot mix --lustopts 'O' with 'M' or 'R'")     if $lustOpts=~/O/ && $lustOpts=~/[MR]/;
  error("you cannot mix --lustopts 'B' with 'M'")            if $lustOpts=~/B/ && $lustOpts=~/M/;
  error("you cannot mix --lustopts 'B' with 'R'")            if $lustOpts=~/B/ && $lustOpts=~/R/;
    
  # Force if not already specified, but ONLY for details
  $lustOpts='BO'    if $cltFlag && $subsys=~/L/ && $lustOpts=~/B/ && $lustOpts!~/O/;
}

sub checkNfs
{
  my $lastNfs=shift;
  my $subsys= shift;
  my $subopt= shift;
  my $temp;

  print "checkNfs(): LastNfs: $lastNfs  SubSys: $subsys  SubOpt: $subopt\n"    if $debug & 2048;

  $temp='';
  if ($subsys=~/f/i)
  {
    $temp= ($subopt=~/C/) ? 'C' : 'S';
    $temp.=($subopt=~/2/) ? '2' : '3';
  }

  # all these are legal
  return($temp)       if $lastNfs eq '';
  return($lastNfs)    if $temp eq '';
  return($lastNfs)    if $lastNfs eq $temp;  # neither null, both MUST match

  # too tricky to handle all possible inconsistencies with multiple files
  # so we're only going to print a stock message
  $preprocErrors{$filePrefix}="E:confilicting nfs settings with other files of same prefix";
  return($temp);
}

sub checkDisks
{
  my $lastDisks=shift;
  my $thisDisks=shift;

  print "checkDisks(): Last: $lastDisks  This: $thisDisks\n"    if $debug & 2048;

  if (($lastDisks ne '') && ($thisDisks ne $lastDisks) && $options!~/u/)
  {
    $preprocErrors{$filePrefix}="E:confilicting disk names with other files of same prefix and -sD w/o -ou";
  }
  return($thisDisks);
}

sub checkLustre
{
  my $lastConfig= shift;
  my $header=     shift;
  my $lastLustOpts=shift;
  my $thisLustOpts=shift;
  my ($temp, $thisConfig, $thisMdss, $thisOsts, $thisClts);
  my ($services, $mdss, $osts, $clts);

  print "checkLustre() -- LastConfig: $lastConfig  LastOpts: $lastLustOpts  ThisOpts: $thisLustOpts\n"
      if $debug & 2048;

  ($services, $mdss, $osts, $clts)=split(/\|/, $lastConfig);
  $services=$osts=$mdss=$clts=''    if $lastConfig eq '';   # first time through

  #    C h e c k    L u s t r e    S e r v i c e s

  # Remember, if set --lustsvcs trumps everything!
  if ($lustreSvcs eq '')
  {
    $thisConfig='';
    if ($header=~/MdsNames:\s+(.*)\s*NumOst:\s+\d+\s+OstNames:\s+([^\n\r]*)$/m)
    {
      # for the first file of a new prefix, we just use the current mdss/osts
      # and only check for changes on subsequent calls
      if ($1 ne '')
      {
        $thisMdss=$1;
        $thisConfig.='m';
        $mdss=($lastConfig eq '') ? $thisMdss : setNames(4, $thisMdss, $mdss);
      }
      if ($2 ne '')
      {
        $thisOsts=$2;
        $thisConfig.='o';
        $osts=($lastConfig eq '') ? $thisOsts : setNames(8, $thisOsts, $osts);
      }
    }

    if ($header=~/CltInfo:\s+(.*)$/m)
    {
      $thisClts=$1;
      $thisConfig.='c';
      $clts=($lastConfig eq '') ? $thisClts : setNames(16, $thisClts, $clts);
    }

    # see if anything new in config
    for ($i=0; $i<length($thisConfig); $i++)
    {
      $temp=substr($thisConfig, $i, 1);
      if ($services!~/$temp/)
      {
	$services.=$temp;
	$configChange|=2    if $lastConfig ne '';    # only tell user if not first time for this prefix
      }
    }
  }
  else
  {
    $services=$lustreSvcs;
    $thisConfig=$lustreSvcs;
  }

  #    C h e c k    O p t i o n s

  # For now we only care about clients
  my $errorText='';
  if (($thisConfig=~/c/ || $lustreSvcs=~/c/) && $thisLustOpts ne '')
  {
    # This file needs to be consistent with respect to OST level detail
    # because if it was requested and this file doesn't know the OSTs
    # they can't even be faked!
    $errorText="requested BRW/OST details but none in file"
        if $lustOpts=~/B/ && $thisLustOpts!~/B/;

    # This one is really pretty rare but we gotta check it...
    $errorText="mixing files with/without B of the same prefix"
        if $thisLustOpts=~/B/ && $lastLustOpts!~/B/;

    # Be sure to return OLD state or else all kinds of other things will break
    if ($errorText ne '')
    {
      $preprocErrors{$file}="E:$errorText";
      print ">>>>>>>>>>>>> Preproc Error: $errorText\n"    if $debug & 2048;
      return(($lastConfig, $lastLustOpts));
    }
  }

  return(("$services|$mdss|$osts|$clts", $thisLustOpts));
}

sub setNames
{
  my $type=    shift;
  my $newNames=shift;
  my $oldNames=shift;
  my $name;

  print "Set Name -- Type: $type Old: $oldNames  New: $newNames\n"
      if $debug & 8;

  # remember, it's ok for names to go away.  we just want new ones!
  $oldNames=" $oldNames ";    # to make pattern match work
  foreach $name (split(/\s+/, $newNames))
  {
    if ($oldNames!~/ $name /)
    {
      $oldNames.="$name ";
      $configChange|=$type;
    }
  }
  $oldNames=~s/^\s+|\s+$//g;    # trim leading/trailing space
  return($oldNames);
}

# This routine reads partial files AND has /proc specific processing
# code for optimal performance.
sub getProc
{
  my $type=  shift;
  my $proc=  shift;
  my $tag=   shift;
  my $ignore=shift;
  my $quit=  shift;
  my $last=  shift;
  my ($index, $line, $ignoreString);

  # matches one or 2 consective //s for pids because when no threads there are 2 of them
  logdiag("$proc")   if ($utimeMask & 2) && ($proc!~/^\/proc\/?\/\d/) || ($utimeMask & 4) && ($proc=~/^\/proc\/?\/\d/);

  if (!open PROC, "<$proc")
  {
    # but just report it once, but not foe nfs or proc data
    logmsg("W", "Couldn't open '$proc'")
	if !defined($notOpened{$proc}) && $type!=8 && $type!=13 && $type!=16 && $type!=17;
    $notOpened{$proc}=1;
    return(0);
  }

  # Skip beginning if told to do so
  $ignore=0    if !defined($ignore);
  $quit=(defined($quit)) ? $ignore+$quit : 10000;
  for (my $i=0; $i<$ignore; $i++)  { <PROC>; }

  $index=0;
  for (my $i=$ignore; $i<$quit; $i++)
  {
    last    if !($line=<PROC>);
    last    if defined($last) && $line=~/$last/;

    # GENERIC - just prepend tag to records
    if ($type==0)
    {
      $spacer=$tag ne '' ? ' ' : '';
      record(2, "$tag$spacer$line");
      next;
    }

    # OST stats
    if ($type==1)
    {
      if ($line=~/^read/)  { record(2, "$tag $line"); next; }
      if ($line=~/^write/) { record(2, "$tag $line"); next; }
    }

    # Client RPC and OST brw_stats AND mds/oss disk stats
    elsif ($type==2)
    {
      # for RPC and brw_stats, this block is virtually always 11 entries, 
      # but the first time an OST is created it's not so we have to stop 
      # when we hit a blank.  In the case of disk stats, we call with 
      # $last so it quites on the 'totals' row
      last    if $line=~/^\s+$/;
      record(2, "$tag:$index $line");
      $index++;
    }

    # MDS stats
    elsif ($type==3)
    {
      if ($line=~/^mds_/)      { record(2, "$tag $line"); next; }
    }

    # type=4 no longer used

    # Memory
    elsif ($type==5)
    {
      next    if $line=~/^nr/;
      next    if $line=~/^numa/;
      last    if $memOpts!~/[ps]/ && $line=~/^pgre/;     # ignore from pgrefill forward
      last    if $memOpts!~/s/ && $line=~/^pgst/;        # ignore from pgstead forward
      last    if $line=~/^pginode/;                      # ignore from pginodesteal and below
      record(2, "$line");
    }

    elsif ($type==7)
    {
      next    if $rawNetIgnore ne '' && $line=~/$rawNetIgnore/;

      if ($line=~/$rawNetFilter/)        { record(2, "$tag $line"); next; }
    }

    # NFS
    elsif ($type==8)
    {
      # Can't use type==0 because we don't want a space after $tag
      record(2, "$tag$line");
    }

    # /proc/diskstats & /proc/partitions
    # would be nice if we could improve even more since this table can
    # get quite large.  Note the pattern for cciss MUST match that used
    # in formatit.ph!!!
    elsif ($type==9)
    {
      next    if $rawDskIgnore ne '' && $line=~/$rawDskIgnore/;

      # If disk filter NOT specified in collectl.conf, use the following syntax.
      # Even thought it matches internal constant $DiskFilter, it's a little
      # faster to as separate if statements
      if (!$DiskFilterFlag)
      {
        if ($line=~/cciss\/c\d+d\d+ /)   { record(2, "$tag $line"); next; }
        if ($line=~/hd[ab] /)            { record(2, "$tag $line"); next; }
        if ($line=~/ sd[a-z]+ /)         { record(2, "$tag $line"); next; }
        if ($line=~/dm-\d+ /)            { record(2, "$tag $line"); next; }
        if ($line=~/xvd[a-z] /)          { record(2, "$tag $line"); next; }
        if ($line=~/fio[a-z]+ /)         { record(2, "$tag $line"); next; }
        if ($line=~/ vd[a-z] /)          { record(2, "$tag $line"); next; }
        if ($line=~/emcpower[a-z]+ /)    { record(2, "$tag $line"); next; }
        if ($line=~/psv\d+ /)            { record(2, "$tag $line"); next; }
      }
      else
      {
        if ($line=~/$DiskFilter/)        { record(2, "$tag $line"); next; }
      }
    }

    # /proc/fs/lustre/llite/fsX/stats
    elsif ($type==11)
    {
      if ($line=~/^dirty/)      { record(2, "$tag $line"); next; }
      if ($line=~/^read/)       { record(2, "$tag $line"); next; }
      if ($line=~/^write_/)     { record(2, "$tag $line"); next; }
      if ($line=~/^open/)       { record(2, "$tag $line"); next; }
      if ($line=~/^close/)      { record(2, "$tag $line"); next; }
      if ($line=~/^seek/)       { record(2, "$tag $line"); next; }
      if ($line=~/^fsync/)      { record(2, "$tag $line"); next; }
      if ($line=~/^getattr/)    { record(2, "$tag $line"); next; }
      if ($line=~/^setattr/)    { record(2, "$tag $line"); next; }
    }

    # /proc/fs/lustre/osc/XX/stats
    # since I've seen difference instances of SFS report these in different
    # locations we have to hunt them out, quitting after 'write' or course.
    elsif ($type==12)
    {
      # This is for the standard CFS/SUN release
      if ($sfsVersion eq '')
      {
        if ($line=~/^read_bytes/)   { record(2, "$tag $line"); next; }
        if ($line=~/^write_bytes/)  { record(2, "$tag $line"); last; }
      }
      else
      {
        # and this is the older HP/SFS V2.*
        if ($line=~/^ost_read/)   { record(2, "$tag $line"); next; }
        if ($line=~/^ost_write/)  { record(2, "$tag $line"); last; }
      }
    }

    # /proc/*/status - save it all!
    elsif ($type==13)
    {
      # only saving a subset because there is a lot of 'noise' in here
      # looks like not exiting early via ^Threads is costing ~10 seconds.  If this
      # ever turns out to be an issue we could always make collecting the context
      # switches optional but for at least now I'm thinking we just do it!
      # since ^nonvol is the last entry no need for a test to exit loop earlier
      if ($line=~/^Tgid/)       { record(2, "$tag $line", undef, 1); next; }
      if ($line=~/^Uid/)        { record(2, "$tag $line", undef, 1); next; }
      if ($line=~/^Vm/)         { record(2, "$tag $line", undef, 1); next; }
      if ($line=~/^vol/)        { record(2, "$tag $line", undef, 1); next; }
      if ($line=~/^nonv/)       { record(2, "$tag $line", undef, 1); next; }
    }

    # /proc/slabinfo - only if not doing all of them
    elsif ($type==14)
    {
      $slab=(split(/ /, $line))[0];
      record(2, "$tag $line")    if defined($slabProc{$slab});
    }

    # /proc/pid/cmdline - only 1 line long
    elsif ($type==16)
    {
      $line=~s/\000/ /g;
      record(2, "$tag $line\n", undef, 1);
      last;
    }

    # identical to type 0, only it writes to process raw file
    elsif ($type==17)
    {
      $spacer=$tag ne '' ? ' ' : '';
      record(2, "$tag$spacer$line", undef, 1);
      next;
    }

    # /proc/dev/netstat
    elsif ($type==20)
    {
      record(2, "tcp-$line")    if ($tcpFilt=~/I/ && $line=~/^I/) || ($tcpFilt=~/T/ &&  $line=~/^T/);
    }

    # /proc/dev/netstat
    elsif ($type==21)
    {
      # no UdpLite or IcmpMsg (at least for now)
      if    ($line=~/^Icmp:/ && $tcpFilt=~/c/) { record(2, "tcp-$line"); next; }
      elsif ($line=~/^Ip/    && $tcpFilt=~/i/) { record(2, "tcp-$line"); next; }
      elsif ($line=~/^T/     && $tcpFilt=~/t/) { record(2, "tcp-$line"); next; }
      elsif ($line=~/^Udp:/  && $tcpFilt=~/u/) { record(2, "tcp-$line"); next; }
    }

    # GENERIC 2 - same as generic but support for rawp file
    if ($type==99)
    {
      $spacer=$tag ne '' ? ' ' : '';
      record(2, "$tag$spacer$line", undef, 1);
      next;
    }
  }
  close PROC;
  return(1);
}

# Functionally equivilent to getProc(), but instead has to run a command rather
# than look in proc.
sub getExec
{
  my $type=   shift;
  my $command=shift;
  my $tag=    shift;

  # for now, always send error messages to /dev/null unless we're debugging.  This is
  # really manditory for perfquery >= ofed 1.5 but let's do it everywhere unless it becomes
  # problematic later on.
  $command.=' 2>/dev/null'            unless $debug & 3;
  print "Type: $type Exec: $command\n"    if $debug & 2;

  # If we can't exec command, only report it once.
  if (!open CMD, "$command|")
  {
    logmsg("W", "Couldn't execute '$command'")
      if !defined($notExec[$type]);
    $notExec[$type]=1;
    return;
  }

  # Return complete contents of command
  my $oneLine='';
  if ($type==0)
  {
    foreach my $line (<CMD>)
    { record(2, "$tag: $line"); }
  }

  # Open Fabric
  elsif ($type==1)
  {
    my $lineNum=0;
    foreach my $line (<CMD>)
    {
      # Skip warnings found in perfquery/ofed 1.5
	next    if $line=~/^ibwarn/;

      # Perfquery V1.5 adds an extra field called CounterSelect2 so ignore.
      next    if ++$lineNum==13 && ($PQVersion ge '1.5.0');

      if ($line=~/^#.*port (\d+)/)
      {
        # The 0 is a place holder we don't care about, at least not now
        $oneLine="$1 0 ";
        next;
      }

      # Since we're not doing anything with hex values this will not include
      # the leading 0x, but it will be faster than trying to include it.
      $line=~/([0x]*\d+$)/; 
      $oneLine.="$1 ";
    }
    $oneLine=~s/ $//;
    record(2, "$tag: $oneLine\n");
  }

  # Voltaire
  elsif ($type==2)
  {
    foreach my $line (<CMD>)
    {
      if ($line=~/^PORT=(\d+)$/)
      {
	  $oneLine="$1 ";
	  next;
      }

      # If counter, append to list.  Note the funky pattern match that will catch
      # both decimal and hex numbers.
      $oneLine.="$1 "    if $line=~/\s(\S*\d)$/;
    }
    $oneLine=~s/ $//;
    record(2, "$tag: $oneLine\n");
  }

  # impi
  elsif ($type==3)
  {
    foreach my $line (<CMD>)
    {
      next    if $envFilt ne '' && $line!~/$envFilt/;
      record(2, "$tag: $line");
    }
  }

  # just count records
  elsif ($type==4)
  {
    my $count=0;
    foreach my $line (<CMD>)
    {  $count++; }
    record(2, "$tag: $count\n");
  }
}

# This guy is in charge of reading single valued entries, which are
# typical of those found in /sys.  The other big difference between
# this and getProc() is it doens't have to deal with all those 
# special 'skip', 'ignore', etc flags.  Just read the data!
sub getSys
{
  my $tag=     shift;
  my $sys=     shift;
  my $dir=     shift;
  my $rawpFlag=shift;    # write to rawp file if one and this is defined
  my $files=   shift;

  foreach my $file (@$files)
  {
    # as of writing this for slub, I'm not expecting file open failures
    # but might as well put in here in case needed in the future
    my $filespec="$sys/$dir/$file";
    if (!open SYS, "<$filespec")
    {
      # but just report it once
      logmsg("E", "Couldn't open '$filespec'")
	  if !defined($notOpened{$filespec});
      $notOpened{$filespec}=1;
      return(0);
    }

    my $line=<SYS>;
    record(2, "$tag $dir $file $line", undef, $rawpFlag);
  }
}

sub record
{
  my $type=    shift;
  my $data=    shift;
  my $recMode= shift;    # error recovery mode
  my $rawpFlag=shift;    # if defined, write to rawp or zrawp

  print "$data"     if $debug & 4;

  #    W r i t e    T o    R A W    F i l e

  # a few words about writing to the raw gz file...  If we fail, we need to
  # create a new file and I want to use newLog() since there's a lot going
  # one.  However, part of newLog() writes the commonHeader as well and that
  # in turn calls this routine, so...  We pass a flag around indicating we're 
  # in recovery mode and if writing the common header fails, we have no 
  # alternative other than to abort.

  # when logging raw data to a file $data, the data to write is either an
  # interval marker or raw data.  Note that when doing plot format to a file
  # as well as any terminal based I/O, that all gets handled by dataAnalyze().
  if ($logToFileFlag && $rawFlag)
  {
    if ($zlibFlag)
    {
      # When flags set, we write 'process' data (identified by '$recFlag1') to a 'rawp' 
      # file; otherwise just 'raw'
      my $rawComp=(defined($rawpFlag) && $recFlag1) ? $ZRAWP : $ZRAW;
      $status=$rawComp->gzwrite($data);
      if (!$status)
      {
        $zlibErrors++;
	$temp=$recMode ? 'F' : 'E';
	logmsg($temp, "Error writing to raw.gz file: ".$rawComp->gzerror());
        logmsg("F", "Max Zlib error count exceeded")    if $zlibErrors>$MaxZlibErrors;
	newLog($filename, "", "", "", "", "", 1);
        record(1, sprintf(">>> %.3f <<<\n", $fullTime))               if $recFlag0;
        record(1, sprintf(">>> %.3f <<<\n", $fullTime), undef, 1)     if $recFlag1;
      }
    }
    else
    {
      # Same logic as for compressed data above.
      my $rawNorm=(defined($rawpFlag) && $recFlag1) ? $RAWP : $RAW;
      print $rawNorm $data;
    }
  }

  #    G e n e r a t e    N u m b e r s    F r o m    D a t a

  # When doing interative reporting OR generating plot data, we need to 
  # analyze each record as it goes by.  This means that in the case of '-P --rawtoo'
  # we write to the raw file AND generate the numbers.  Also remember that in the 
  # case of --export we may not end up writing anywhere other than the exported file
  dataAnalyze($subsys, $data)   if $type==2 && (!$logToFileFlag || $plotFlag || $export ne '');
}

# Design note - this is very subtle, but when creating consecutive files via the log rolling
# mechanism, the last timestamp of one file matches that of the new one.  This tells us NOT
# to reset 'last' counters during playback.  BUT if newlog() called before new timestamp
# generated, as when $diskChangeFlag set, this does not happen and so you lose 1 interval
# during playback.  Not a big deal but worth noting somewhere...
sub newLog
{
  my $filename=shift;
  my $recDate= shift;
  my $recTime= shift;
  my $recSecs= shift;
  my $recTZ=   shift;
  my $playback=shift;
  my $recMode= shift;    # only used during error recovery mode

  my ($ss, $mm, $hh, $mday, $mon, $year, $datetime);
  my ($dirname, $basename, $command, $fullname, $mode);
  my (@disks, $dev, $numDisks, $i, $oldHeader, $oldSubsys, $timesecs, $timezone);

  print "NewLog -- Playback: $playback  File: $filename  Raw: $rawFlag  Plot: $plotFlag\n"    if $debug & 1;

  if ($recDate eq '')
  {
    # We need EXACT seconds associated with the timestamp of the filename.
    # turns out time() and gettimeofday can differ by 5 or 6 msec and when that happens files could end up
    # getting rolled 1 second earlier.  Therefore always use gettimeofday when using hires to be consistent.
    $timesecs=($hiResFlag) ? (Time::HiRes::gettimeofday())[0] : time();
    ($ss, $mm, $hh, $mday, $mon, $year)=localtime($timesecs);
    $datetime=sprintf("%d%02d%02d-%02d%02d%02d", 
		      $year+1900, $mon+1, $mday, $hh, $mm, $ss);
    $dateonly=substr($datetime, 0, 8);
    $timezone=$LocalTimeZone;
  }
  else
  {
    $timesecs=$recSecs;
    $datetime="$recDate-$recTime";
    $dateonly=$recDate;
    $timezone=$recTZ;
  }

  # Build a common header for ALL files, noting type1 for process
  # we only build it if we need it.
  $temp="# Date:       $datetime  Secs: $timesecs TZ: $timezone\n";
  $commonHeader= buildCommonHeader(0, $temp);
  $commonHeader1=buildCommonHeader(1, $temp)    if $recFlag1;

  # Now build a slab subheader just to be used for 'raw' and 'slb' files
  if ($slubinfoFlag)
  {
    $slubHeader="#SLUB DATA\n";
    foreach my $slab (sort keys %slabdata)
    {
      # when we have a slab with no aliases, 'first' gets set to that same
      # name which in turns ends up on the alias list because it always
      # contains 'first' followed by any additional aliases.  On the rare
      # case we have no alias, which can happen where we have only the root
      # slab itself, set the aliases to that slab which will then be skipped.
      my $aliaslist=$slabdata{$slab}->{aliaslist};
      next    if defined($aliaslist) && $slab eq $aliaslist;

      $aliaslist=$slab    if !defined($aliaslist);
      $slubHeader.="#$slab $aliaslist\n";
    }
    $slubHeader.=sprintf("%s\n", '#'x80);
  }

  # If generating plot data on terminal, just open everything on STDOUT
  # but be SURE set the buffers to flush in case anyone runs as part
  # of a script and needs the output immediately.
  if ($filename eq "" && $plotFlag)
  {
    # sigh...
    error("Cannot use -P for terminal output of process and 'other' data at the same time")
	if $subsys=~/Z/ && length($subsys)>1;

    # in the event that someone runs this as a piped command from 
    # a script and turns off headers things lock up unless these 
    # files are set to auto-flush.
    $zFlag=0;
    open $LOG, ">-" or logmsg("F", "Couldn't open LOG for STDOUT");  select $LOG; $|=1;
    open BLK,  ">-" or logmsg("F", "Couldn't open BLK for STDOUT");  select BLK; $|=1;
    open BUD,  ">-" or logmsg("F", "Couldn't open BUD for STDOUT");  select BUD; $|=1;
    open CLT,  ">-" or logmsg("F", "Couldn't open CLT for STDOUT");  select CLT; $|=1;
    open CPU,  ">-" or logmsg("F", "Couldn't open CPU for STDOUT");  select CPU; $|=1;
    open DSK,  ">-" or logmsg("F", "Couldn't open DSK for STDOUT");  select DSK; $|=1;
    open ELN,  ">-" or logmsg("F", "Couldn't open ELN for STDOUT");  select ELN; $|=1;
    open ENV,  ">-" or logmsg("F", "Couldn't open ENV for STDOUT");  select ENV; $|=1;
    open IB,   ">-" or logmsg("F", "Couldn't open IB for STDOUT");   select IB;  $|=1;
    open NFS,  ">-" or logmsg("F", "Couldn't open NFS for STDOUT");  select NFS; $|=1;
    open NET,  ">-" or logmsg("F", "Couldn't open NET for STDOUT");  select NET; $|=1;
    open NUMA, ">-" or logmsg("F", "Couldn't open NUMA for STDOUT"); select NUMA; $|=1;
    open OST,  ">-" or logmsg("F", "Couldn't open OST for STDOUT");  select OST; $|=1;
    open TCP,  ">-" or logmsg("F", "Couldn't open TCP for STDOUT");  select TCP; $|=1;
    open SLB,  ">-" or logmsg("F", "Couldn't open SLB for STDOUT");  select SLB; $|=1;
    open PRC,  ">-" or logmsg("F", "Couldn't open PRC for STDOUT");  select PRC; $|=1;
    for (my $i=0; $i<$impNumMods; $i++)
    {
      open $impGz[$i], ">-" or logmsg("F", "Couldn't open $impKey[$i] for STDOUT"); select $impGz[$i]; $|=1;
    }

    select STDOUT; $|=1;
    return 1;
  }

  #    C r e a t e    N e w    L o g

  # note the way we build files:
  # - if name is a dir, the filename starts with hostname.  
  # - if name not a dir, the filename gets '-host' appended
  # - if raw file it also gets date/time but if plot file only date.
  $filename= "."         if $filename eq '';  # -P and no -f
  $filename.=(-d $filename || $filename=~/\/$/) ? "/$Host" : "-$Host";
  $filename.=(!$plotFlag || $options=~/u/) ? "-$datetime" : "-$dateonly";

  # if the directory doesn't exist (we don't need date/time stamp), create it
  $temp=dirname($filename);
  if (!-e $temp)
  {
    logmsg('W', "Creating directory '$temp'");
    `mkdir $temp`;
  }

  # track number of times same file processed, primarily for options 'a/c'.  in
  # case multiple raw files for same day, only check on initial one
  # If we're in playback mode and writing a plotfile, either the user specified
  # an option of 'a', 'c' or 'u', we just created it (newFiles{} defined) OR it had 
  # better not exist!  If is does, return it name so a contextual error message
  # can be generated.
  return $filename    if $playback ne "" && 
                         $options!~/a|c|u/ && 
                         !defined($newFiles{$filename}) &&
			 plotFileExists($filename);

  # -ou is special in that we're never going to have multiple source files generate
  # the same output file so 'a' doesn't mean anything in this context.  Furthermore
  # if the output file already exists and its update time is less than that of the
  # source file, the source file has changed since the output file was created and
  # it should and will be overwritten.  Finally, the user may also have chosen to
  # reprocess a source file with different options and so if 'c' is included the
  # file WILL be overwritten even if newer.  Whew...
  if ($options=~/u/ && plotFileExists($filename))
  {
    my @files;
    @files=glob("$filename*");
    my $plotTime=(stat($files[0]))[9];
    my $rawTime= (stat($playback))[9];
    return($filename)    if $plotTime>$rawTime && $options!~/c/;
  }

  # The only time we force creation of a new file is for the first one of the
  # day when in plot create mode (not sure why 'u' too).  In all others cases
  # we append, which will also create file if not already there.
  $newFiles{$filename}++;
  if ($options=~/c|u/ && $newFiles{$filename}==1)
  {
    $mode=">";
    $zmode="wb";
  }
  else
  {
    $mode=">>";
    $zmode="ab";
  }
  print "NewLog Modes: $mode + $zmode Name: $filename\n"    if $debug & 1;

  #    C r e a t e    R A W    F i l e

  if ($rawFlag)
  {
    # on subsequent file creates (this is new for V3.1.3) write a terminating time
    # stamp, noting this will be the SAME starting timestamp of the new file.
    if (!$firstPass)
    {
      my $fullTime=sprintf("%d.%06d", $intSeconds, $intUsecs);
      record(1, sprintf(">>> %.3f <<<\n", $fullTime))               if $recFlag0;
      record(1, sprintf(">>> %.3f <<<\n", $fullTime), undef, 1)     if $recFlag1;

      # Now we can safely close the raw log(s)
      closeLogs($subsys, 'r');
    }

    # In some cases, such as when using --rawtoo (and other situations as well),
    # the default filename may only have a datestamp put time back in.
    my $rawFilename=$filename;
    $rawFilename=~s/$dateonly$/$datetime/;
    print "Create raw file:   $rawFilename Flag0: $recFlag0  Flag1: $recFlag1\n"    if $debug & 8192;

    # Unlike plot files, we ALWAYS compress when compression lib exists
    $ZRAW=Compress::Zlib::gzopen("$rawFilename.raw.gz", $zmode) or
        logmsg("F", "Couldn't open '$rawFilename.raw.gz'")       if $zlibFlag && $recFlag0;
    $ZRAWP=Compress::Zlib::gzopen("$rawFilename.rawp.gz", $zmode) or
        logmsg("F", "Couldn't open '$rawFilename.rawp.gz'")      if $zlibFlag && $recFlag1;
    open $RAW, "$mode$rawFilename.raw"  or
        logmsg("F", "Couldn't open '$rawFilename.raw'")          if !$zlibFlag && $recFlag0;
    open $RAWP, "$mode$rawFilename.rawp"  or
        logmsg("F", "Couldn't open '$rawFilename.rawp'")         if !$zlibFlag && $recFlag1;

    # write common header to raw file (record() ignores otherwise).  Note that we
    # we need to pass along the recovery mode flag because if this record()
    # fails it's fatal.  we may also need a slub header
    record(1, $commonHeader, $recMode)        if $recFlag0;
    record(1, $commonHeader1, $recMode, 1)    if $recFlag1;
    record(1, $slubHeader, $recMode, 1)       if $slubinfoFlag && $subsys=~/y/i;

    # This flag indicated a new file was created and full SLUB records may need to be read
    $newRawSlabFlag=1;
  }

  #    C r e a t e    P l o t    F i l e s

  if ($plotFlag)
  {
    print "Create plot files: $filename.*\n"    if $debug & 8192;

    # but first close any that might be open
    closeLogs($subsys, 'p')    if !$firstPass;

    # Indicates something needs to be printed
    printProcAnalyze($filename)    if $procAnalCounter;
    printSlabAnalyze($filename)    if $slabAnalCounter;

    print "Writing file(s): $mode$filename\n"    if $msgFlag && !$daemonFlag;
    print "Subsys: $subsys\n"    if $debug & 1;

    # this is already taken care of in playback mode, but when doing -P in
    # collection mode we need to clear this since nobody else does!
    $headersPrinted=0    if $newFiles{$filename}==1;

    # Open 'tab' file in plot mode if processing at least 1 core variable (or extended core)
    # OR we're --importing something that prints summary data
    $temp="$SubsysCore$SubsysExcore";

    if ($subsys=~/[$temp]/ || $impSummaryFlag)
    {
      $ZLOG=Compress::Zlib::gzopen("$filename.tab.gz", $zmode) or
	logmsg("F", "Couldn't open '$filename.tab.gz'")       if $zFlag;
      open $LOG, "$mode$filename.tab"  or
	logmsg("F", "Couldn't open '$filename.tab'")          if !$zFlag;
      $headersPrintedProc=$headersPrintedSlab=0;
    }

    open BLK, "$mode$filename.blk" or 
	  logmsg("F", "Couldn't open '$filename.blk'")   if !$zFlag && $LFlag && $lustOpts=~/D/;
    $ZBLK=Compress::Zlib::gzopen("$filename.blk.gz", $zmode) or
  	  logmsg("F", "Couldn't open BLK gzip file")     if  $zFlag && $LFlag && $lustOpts=~/D/;

    open BUD, "$mode$filename.bud" or 
	  logmsg("F", "Couldn't open '$filename.bud'")   if !$zFlag && $BFlag;
    $ZBUD=Compress::Zlib::gzopen("$filename.bud.gz", $zmode) or
    	  logmsg("F", "Couldn't open BUD gzip file")     if  $zFlag && $BFlag;

    open CPU, "$mode$filename.cpu" or 
	  logmsg("F", "Couldn't open '$filename.cpu'")   if !$zFlag && $CFlag;
    $ZCPU=Compress::Zlib::gzopen("$filename.cpu.gz", $zmode) or
	  logmsg("F", "Couldn't open CPU gzip file")     if  $zFlag && $CFlag;

    open CLT, "$mode$filename.clt" or 
	  logmsg("F", "Couldn't open '$filename.clt'")   if !$zFlag && $LFlag && $reportCltFlag;
    $ZCLT=Compress::Zlib::gzopen("$filename.clt.gz", $zmode) or
	  logmsg("F", "Couldn't open CLT gzip file")     if  $zFlag && $LFlag && $reportCltFlag;

    # if only doing exceptions, we don't need this file.
    if ($options!~/x/)
    {
      open DSK, "$mode$filename.dsk" or 
	  logmsg("F", "Couldn't open '$filename.dsk'")   if !$zFlag && $DFlag;
      $ZDSK=Compress::Zlib::gzopen("$filename.dsk.gz", $zmode) or
	  logmsg("F", "Couldn't open DSK gzip file")     if  $zFlag && $DFlag;
    }

    # exception processing for both x and X options
    if ($options=~/x/i)
    {
      open DSKX, "$mode$filename.dskX" or 
	  logmsg("F", "Couldn't open '$filename.dskX'")   if !$zFlag && $DFlag;
      $ZDSKX=Compress::Zlib::gzopen("$filename.dskX.gz", $zmode) or
	  logmsg("F", "Couldn't open DSKX gzip file")     if  $zFlag && $DFlag;
    }

    if ($XFlag && $NumXRails)
    {
      open ELN, "$mode$filename.eln" or 
	  logmsg("F", "Couldn't open '$filename.eln'")   if !$zFlag;
      $ZELN=Compress::Zlib::gzopen("$filename.eln.gz", $zmode) or
          logmsg("F", "Couldn't open ELN gzip file")     if  $zFlag;
    }

    if ($XFlag && $NumHCAs)
    {
      open IB, "$mode$filename.ib" or 
	  logmsg("F", "Couldn't open '$filename.ib'")   if !$zFlag;
      $ZIB=Compress::Zlib::gzopen("$filename.ib.gz", $zmode) or
          logmsg("F", "Couldn't open IB gzip file")     if  $zFlag;
    }

    open ENV, "$mode$filename.env" or 
	  logmsg("F", "Couldn't open '$filename.env'")   if !$zFlag && $EFlag;
    $ZENV=Compress::Zlib::gzopen("$filename.env.gz", $zmode) or
          logmsg("F", "Couldn't open ENV gzip file")     if  $zFlag && $EFlag;

    open NFS, "$mode$filename.nfs" or 
	  logmsg("F", "Couldn't open '$filename.nfs'")   if !$zFlag && $FFlag;
    $ZNFS=Compress::Zlib::gzopen("$filename.nfs.gz", $zmode) or
          logmsg("F", "Couldn't open NFS gzip file")     if  $zFlag && $FFlag;

    open NUMA, "$mode$filename.numa" or 
	  logmsg("F", "Couldn't open '$filename.numa'")  if !$zFlag && $MFlag;
    $ZNUMA=Compress::Zlib::gzopen("$filename.numa.gz", $zmode) or
          logmsg("F", "Couldn't open NUMA gzip file")    if  $zFlag && $MFlag;

    open NET, "$mode$filename.net" or 
	  logmsg("F", "Couldn't open '$filename.net'")   if !$zFlag && $NFlag;
    $ZNET=Compress::Zlib::gzopen("$filename.net.gz", $zmode) or
          logmsg("F", "Couldn't open NET gzip file")     if  $zFlag && $NFlag;

    open OST, "$mode$filename.ost" or 
	  logmsg("F", "Couldn't open '$filename.ost'")   if !$zFlag && $LFlag && $reportOstFlag;
    $ZOST=Compress::Zlib::gzopen("$filename.ost.gz", $zmode) or
          logmsg("F", "Couldn't open OST gzip file")     if  $zFlag && $LFlag && $reportOstFlag;

    # These next two guys are 'special' because they're not really detail files per se, 
    # Also note when doing --rawtoo, the data in 'prc' and 'raw' is essentially identical and
    # we don't need it on both places.  Furthermore, raw is already being compressed.
    if (!$rawtooFlag)
    {
      if (!$procAnalOnlyFlag && $ZFlag)
      {
        print "Creating PRC file\n"    if $debug & 8192;
        open PRC, "$mode$filename.prc" or 
            logmsg("F", "Couldn't open '$filename.prc'")  if !$zFlag && $ZFlag;
        $ZPRC=Compress::Zlib::gzopen("$filename.prc.gz", $zmode) or
            logmsg("F", "Couldn't open PRC gzip file")    if  $zFlag && $ZFlag;
      }

      if (!$slabAnalOnlyFlag && $YFlag && !$rawtooFlag)
      {
        print "Creating SLB file\n"    if $debug & 8192;
        open SLB, "$mode$filename.slb" or 
	    logmsg("F", "Couldn't open '$filename.slb'")  if !$zFlag && $YFlag;
        $ZSLB=Compress::Zlib::gzopen("$filename.slb.gz", $zmode) or
            logmsg("F", "Couldn't open SLB gzip file")    if  $zFlag && $YFlag;
      }
    }

    open TCP, "$mode$filename.tcp" or 
	  logmsg("F", "Couldn't open '$filename.tcp'")  if !$zFlag && $TFlag;
    $ZTCP=Compress::Zlib::gzopen("$filename.tcp.gz", $zmode) or
          logmsg("F", "Couldn't open TCP gzip file")    if  $zFlag && $TFlag;

    # Open any detail files associated with --import
    for (my $i=0; $i<$impNumMods; $i++)
    {
      next    if $impOpts[$i]!~/d/;

      open $impText[$i], "$mode$filename.$impKey[$i]" or
	logmsg("F", "Couldn't open '$filename.$impKey[$i]'")  if !$zFlag;
      $impGz[$i]=Compress::Zlib::gzopen("$filename.$impKey[$i].gz", $zmode) or
	logmsg("F", "Couldn't open $impKey[$i] gzip file")    if  $zFlag;
    }

    if ($autoFlush)
    {
      print "Setting non-compressed files to 'autoflush'\n"    if $debug & 1;
      if (defined($LOG))           { select $LOG; $|=1; }
      if (defined(fileno(BLK)))    { select BLK;  $|=1; }
      if (defined(fileno(BUD)))    { select BUD;  $|=1; }
      if (defined(fileno(CLT)))    { select CLT;  $|=1; }
      if (defined(fileno(CPU)))    { select CPU;  $|=1; }
      if (defined(fileno(DSK)))    { select DSK;  $|=1; }
      if (defined(fileno(DSKX)))   { select DSKX; $|=1; }
      if (defined(fileno(ELN)))    { select ELN;  $|=1; }
      if (defined(fileno(ENV)))    { select ENV;  $|=1; }
      if (defined(fileno(IB)))     { select IB;   $|=1; }
      if (defined(fileno(OST)))    { select OST;  $|=1; }
      if (defined(fileno(NET)))    { select NET;  $|=1; }
      if (defined(fileno(NFS)))    { select NFS;  $|=1; }
      if (defined(fileno(NUMA)))   { select NUMA;  $|=1; }
      if (defined(fileno(PRC)))    { select PRC;  $|=1; }
      if (defined(fileno(SLB)))    { select SLB;  $|=1; }
      if (defined(fileno(TCP)))    { select TCP;  $|=1; }
      select STDOUT; $|=1;
    }
  }

  #    P u r g e    O l d    L o g s

  # ... but only if an interval specified
  # explicitly purge anything in the logging directory as long it looks like a collectl log
  # starting with the host name.  in the case of monthly logs, we typically will keep them
  # around a LOT longer
  if ($purgeDays)
  {
    my ($day, $mon, $year)=(localtime(time-86400*$purgeDays))[3..5];
    my $purgeDate=sprintf("%4d%02d%02d", $year+1900, $mon+1, $day);

    $dirname=dirname($filename);
    if (opendir(DIR, "$dirname"))
    {
      while (my $filename=readdir(DIR))
      {
        next    if $filename=~/^\./;
        next    if $filename=~/log$/;
        next    if $filename!~/-(\d{8})(-\d{6})*\./ || $1 ge $purgeDate;

        unlink "$dirname/$filename";
      }
    }
    else
    {
      logmsg('E', "Couldn't open '$dirname' for purging");
    }
    close DIR;

    # now do it for the collectl logs themselves, based on the number
    # of months, so no days included
    ($day, $mon, $year)=(localtime(time-86400*$purgeMons*30))[3..5];
    $purgeDate=sprintf("%4d%02d", $year+1900, $mon+1);

    my $globspec="$dirname/*.log";
    foreach my $file (glob($globspec))
    {
      next            if $file!~/-(\d{6})\.log$/;
      unlink $file    if $1 < $purgeDate;
    }
  }

  # Save as a global for later use.  Could probably avoid passing back the name
  # on error below, but I'm afraid to change it if I don't have to.
  $lastLogPrefix=$filename;
  return 1;
}

# Build a common header for ALL files...
sub buildCommonHeader
{
  my $rawType=     shift;
  my $timeZoneInfo=shift;

  # if grouping we need to remove subsystems for groups not in
  # the associated files
  my $tempSubsys=$subsys;
  if ($tworawFlag)
  {
    $tempSubsys=~s/[YZ]//g      if $rawType==0;
    $tempSubsys=~s/[^YZ]+//g    if $rawType==1;
  }

  # We want to store all the interval(s) being used and not just what
  # the user specified with -i.  So include i2 if process/slabs and
  # i3 more for a placeholder.  NOTE - if we're playing back multiple
  # files and first doesn't have process data, i2 not set for second
  # and so we can't put in header.
  $tempInterval=$interval;
  $tempInterval.=(defined($interval2)) ? ":$interval2" : ':'    if $subsys=~/[yz]/i;
  $tempInterval.=($subsys!~/[yz]/i) ? "::$interval3" : ":$interval3"
      if $subsys=~/E/;

  # For now, these are the only flags I can think of but clearly they
  # can grow over time...
  my $flags='';
  $flags.='d'    if $diskChangeFlag;
  $flags.='2'    if $tworawFlag;   # start using 2 instead of 'g'
  $flags.='i'    if $processIOFlag;
  $flags.='s'    if $slubinfoFlag;
  $flags.='x'    if $processCtxFlag;
  $flags.='D'    if $cpuDisabledFlag;

  my $dskNames='';
  foreach my $disk (@dskOrder)
  { $dskNames.="$disk "; }
  $dskNames=~s/ $//;

  my $netNames='';
  foreach my $netname (@netOrder)
  { $netNames.=sprintf("$netname:%s ", defined($netSpeeds{$netname}) ? $netSpeeds{$netname} : '??'); }
  $netNames=~s/ $//;

  my ($sec, $min, $hour, $day, $mon, $year)=localtime($boottime);
  my $booted=sprintf "%d%02d%02d-%02d:%02d:%02d", $year+1900, $mon+1, $day, $hour, $min, $sec;

  my $commonHeader='';
  if ($rawType!=-1 && $playback ne '')
  {
    $commonHeader.='#'x35;
    $commonHeader.=' RECORDED ';
    $commonHeader.='#'x35;
    $commonHeader.="\n# $recHdr1";
    $commonHeader.="\n# $recHdr2"    if $recHdr2 ne '';
    $commonHeader.="\n";
  }
  $commonHeader.='#'x80;
  $commonHeader.="\n# Collectl:   V$Version  HiRes: $hiResFlag  Options: $cmdSwitches\n";
  $commonHeader.="# Host:       $Host  DaemonOpts: $DaemonOptions\n";
  $commonHeader.="# Booted:     $boottime [$booted]\n";
  $commonHeader.="# Distro:     $Distro  Platform: $ProductName\n";
  $commonHeader.=$timeZoneInfo  if defined($timeZoneInfo);
  $commonHeader.="# SubSys:     $tempSubsys Options: $options Interval: $tempInterval NumCPUs: $NumCpus $Hyper";
  $commonHeader.=               " CPUsDis: $cpusDisabled"    if $cpusDisabled;
  $commonHeader.=               " NumBud: $NumBud Flags: $flags\n";
  $commonHeader.="# Filters:    NfsFilt: $nfsFilt EnvFilt: $envFilt TcpFilt: $tcpFilt\n";
  $commonHeader.="# HZ:         $HZ  Arch: $SrcArch PageSize: $PageSize\n";
  $commonHeader.="# Cpu:        $CpuVendor Speed(MHz): $CpuMHz Cores: $CpuCores  Siblings: $CpuSiblings Nodes: $CpuNodes\n";
  $commonHeader.="# Kernel:     $Kernel  Memory: $Memory  Swap: $Swap\n";
  $commonHeader.="# NumDisks:   $dskIndexNext DiskNames: $dskNames\n";
  $commonHeader.="# NumNets:    $netIndexNext NetNames: $netNames\n";
  $commonHeader.="# NumSlabs:   $NumSlabs Version: $SlabVersion\n"    if $yFlag || $YFlag;
  $commonHeader.="# IConnect:   NumXRails: $NumXRails XType: $XType  XVersion: $XVersion\n"    if $NumXRails;
  $commonHeader.="# IConnect:   NumHCAs: $NumHCAs PortStates: $HCAPortStates IBVersion: $IBVersion PQVersion: $PQVersion\n"                if $NumHCAs;
  $commonHeader.="# SCSI:       $ScsiInfo\n"    if $ScsiInfo ne '';
  if ($subsys=~/l/i)
  {
    # Lustre Version and services (if any) info
    $commonHeader.="# Lustre:   ";
    $commonHeader.="  CfsVersion: $cfsVersion"       if $cfsVersion ne '';
    $commonHeader.="  SfsVersion: $sfsVersion"       if $sfsVersion ne '';
    $commonHeader.="  LustOpts: $lustOpts Services: $lustreSvcs";
    $commonHeader.="\n";

    $commonHeader.="# LustreServer:   NumMds: $NumMds MdsNames: $MdsNames  NumOst: $NumOst OstNames: $OstNames\n"
	if $NumOst || $NumMds;
    $commonHeader.="# LustreClient:   CltInfo:  $lustreCltInfo\n"
	if $CltFlag && $lustreCltInfo ne '';    # in case all filesystems umounted

    # more stuff for Disk Stats
    $commonHeader.="# LustreDisks:    Num: $NumLusDisks  Names: $LusDiskNames\n"
	if ($lustOpts=~/D/);
  }
  for (my $i=0; $i<$impNumMods; $i++) { &{$impUpdateHeader[$i]}(\$commonHeader); }
  $commonHeader.="# Comment:    $comment\n"    if $comment ne '';
  $commonHeader.='#'x80;
  $commonHeader.="\n";
  return($commonHeader);
}

sub writeInterFileMarker
{
  # I was torn between putting this test in the one place this routine 
  # is called or keeping it cleaner and so put it here.
  return    if $procAnalOnlyFlag;

  # for now, only need one for process data
  my $marker="# >>> NEW LOG <<<\n";
  if ($subsys=~/Z/ && !$rawtooFlag)
  {
    $ZPRC->gzwrite($marker) or 
        writeError('prc', $ZPRC)    if  $zFlag;
    print PRC $marker               if !$zFlag;
  }
}

# see if there is a file that matches this filename root (should't have
# an extension).
sub plotFileExists
{
  my $filespec=shift;
  my (@files, $file);

  @files=glob("$filespec*");
  foreach my $file (@files)
  {
      return(1)  if $file!~/raw/;
  }
  return(0);
}

# In retrospect, there are a number of special cases in here just for playback
# and things might be clearer to do away with this function and move code where
# it applies.
sub setOutputFormat
{
  # By default, brief has been initialized to 1 and verbose to 0 but in these
  # cases (when not doing --import) we switch to verbose automatically
  $verboseFlag=1    if ($subsys ne '' && $subsys!~/^[$BriefSubsys]+$/) || $lustOpts=~/[BDM]/;
  $verboseFlag=1    if $memOpts=~/[psPV]/;
  $verboseFlag=1    if $tcpFilt eq 'I';

  # except as where noted below, columns in verbose mode are assumed different
  $sameColsFlag=($verboseFlag) ? 0 : 1;

  # Now let's deal with a few special cases where we're in verbose mode but 
  # the cols  are the same after all, such as a single subsystem or '-sCj'
  $sameColsFlag=1    if $verboseFlag && (length($subsys)==1 || $subsys=~/^[Cj]+$/);

  # Environmental data is multipart if '--envopts M' so we only have same columns when 1 type
  $sameColsFlag=0    if $subsys eq 'E' && length($envOpts)>1 && $userEnvOpts=~/M/;

  # As usual, lustre complicates things since we can get multiple lines of
  # output and if more than 1 clear the flag.
  $sameColsFlag=0    if length($lustOpts)>1;

  # Finally, if --import modules we've been called at least a second time
  if ($impNumMods)
  {
    # Detail mode forces verbose
    if ($impDetailFlag)
    {
      $verboseFlag=1;
      $sameColsFlag=0;
    }

    # Verbose mode special, because if we don't have any subsystem data and only have 1 type of
    # imported data, we still get all data on the same line and won't need to repeat headers every pass.
    # On the other hand it we have more than 1 type of data we can't have the same columns
    $sameColsFlag=($impSummaryFlag+$impDetailFlag+length($subsys)==1) ? 1 : 0    if $verboseFlag;

    # and finally if processing any standard detail data we know we have at least 2 fields, at least
    # one of which is our custom import, and so we can't have same columns in effect.
    $sameColsFlag=0    if $subsys=~/[A-Z]/;    # detail for single -s would have set flag
  }

  # time doesn't print when not all columns the same AND not something that
  # was exported since they's on their own for formatting
  if (!$sameColsFlag && $export eq '')
  {
    $miniDateFlag=$miniTimeFlag=0;
    $miniDateTime=$miniFiller='';
  }

  $briefFlag=($verboseFlag) ? 0 : 1;
  print "Set Output -- Subsys: $subsys Verbose: $verboseFlag SameCols: $sameColsFlag\n"    if $debug & 1;

  # This also feels like a good place to do these
  $i1DataFlag=($subsys!~/^[EYZ]+$/i) ? 1 : 0;
  $i2DataFlag=($subsys=~/[yYZ]/)    ? 1 : 0;
  $i3DataFlag=($subsys=~/E/)        ? 1 : 0;
}

# Control C Processing
# This will wake us if we're sleeping or let us finish a collection cycle
# if we're not.
sub sigInt
{
  print "Ouch!\n"    if !$daemonFlag;
  $doneFlag=1;
}

sub sigTerm
{
  logmsg("W", "Shutting down in response to signal TERM on $myHost...");
  $doneFlag=1;
}

sub sigAlrm
{
  # This will set next alarm to the next interval that's a multiple of
  # our base time.  Note the extra 1000usecs which we need as fudge
  # Also note that arg[0] always defined with "ALRM" when ualarm below
  # fires so we need to use arg[1] as the 'first time' switch for 
  # logmsg() below.
  my ($intSeconds, $intUsecs)=Time::HiRes::gettimeofday();
  my $nowUSecs=$intSeconds*1000000+$intUsecs;
  my $secs=int(($nowUSecs-$BaseTime+$uAlignInt)/$uAlignInt)*$uAlignInt;
  my $waitTime=$BaseTime+$secs-$nowUSecs;
  Time::HiRes::ualarm($waitTime+1000);

  # message only on the very first call AND when --align since we always
  # align on an interval boundary anyway and don't want cluttered messages
  logmsg("I", "Waiting $waitTime usecs for time alignment")
      if defined($_[1]) && $alignFlag;

  # The following is all debug
  #($intSeconds, $intUsecs)=Time::HiRes::gettimeofday();
  #$nowUSecs2=$intSeconds*1000000+$intUsecs;
  #$diff=($nowUSecs2-$nowUSecs)/1000000;
  #printf "Start: %f  Current: %f  Wait: %f  Time: %f\n", $BaseTime/1000000, $nowUSecs/1000000, $waitTime/1000000, $diff;
}

# flush buffer(s) on sigUsr1
sub sigUsr1
{
  # There should be a small enough number of these to make it worth logging
  logmsg("I", "Flushing buffers in response to signal USR1")    if !$autoFlush;
  logmsg("W", "No need to signal 'USR1' since autoflushing")    if  $autoFlush;
  flushBuffers()    if !$autoFlush;
}

sub sigPipe
{
  # The only time we're treating a broken pipe as an error is when not in server mode,
  # where we simply log but ignore the message since we don't want to quit.
  if (!$serverFlag)
  {
    logmsg("W", "Shutting down due to a broken pipe");
    $doneFlag=1;
  }
  else
  {
    logmsg("W", "Ignoring broken pipe");
  }
}


sub flushBuffers
{
  return    if !$logToFileFlag;

  # Remember, when $rawFlag set we flush everything including process/slab data.  But if
  # just $rawtooFlag set we those 2 other files aren't open and so we don't flush them.
  $flushTime=time+$flush     if $flushTime;
  logdiag("begin flush")     if $utimeMask & 1;

  if ($zFlag)
  {
    if ($rawFlag)
    {
      # if in raw mode, may be up to 2 buffers to flush
      $ZRAW-> gzflush(2)<0 and flushError('raw', $ZRAW)     if $recFlag0;
      $ZRAWP->gzflush(2)<0 and flushError('raw', $ZRAWP)    if $recFlag1;
      if (!$plotFlag)
      {
        logdiag("end flush")     if $utimeMask & 1;
        return;
      }
    }

    $ZLOG-> gzflush(2)<0 and flushError('log', $ZLOG)     if $subsys=~/[a-z]/;
    $ZBLK-> gzflush(2)<0 and flushError('blk', $ZBLK)     if $LFlag && $lustOpts=~/D/;
    $ZBUD-> gzflush(2)<0 and flushError('bud', $ZBUD)     if $BFlag;
    $ZCPU-> gzflush(2)<0 and flushError('cpu', $ZCPU)     if $CFlag;
    $ZCLT-> gzflush(2)<0 and flushError('clt', $ZCLT)     if $LFlag && $CltFlag;
    $ZDSK-> gzflush(2)<0 and flushError('dsk', $ZDSK)     if $DFlag && $options!~/x/;    # exception only file?
    $ZDSKX->gzflush(2)<0 and flushError('dskx',$ZDSKX)    if $DFlag && $options=~/x/i;
    $ZELN-> gzflush(2)<0 and flushError('eln', $ZELN)     if $XFlag && $NumXRails;
    $ZIB->  gzflush(2)<0 and flushError('ib',  $ZIB)      if $XFlag && $NumHCAs;
    $ZENV-> gzflush(2)<0 and flushError('env', $ZENV)     if $EFlag;
    $ZNFS-> gzflush(2)<0 and flushError('nfs', $ZNFS)     if $FFlag;
    $ZNUMA->gzflush(2)<0 and flushError('net', $ZNET)     if $MFlag;
    $ZNET-> gzflush(2)<0 and flushError('net', $ZNET)     if $NFlag;
    $ZOST-> gzflush(2)<0 and flushError('ost', $ZOST)     if $LFlag && $OstFlag;
    $ZTCP-> gzflush(2)<0 and flushError('tcp', $ZTCP)     if $TFlag;
    $ZSLB-> gzflush(2)<0 and flushError('slb', $ZSLB)     if $YFlag && !$rawtooFlag;
    $ZPRC-> gzflush(2)<0 and flushError('prc', $ZPRC)     if $ZFlag && !$rawtooFlag;

    # handle --import
    for (my $i=0; $i<$impNumMods; $i++)
    {
      # we can only flush detail data if something in buffer or else we'll throw an error!
      $impGz[$i]->gzflush(2)<0 and flushError($impKey[$i], $impGz[$i])    if defined($impGz[$i]) && $impDetFlag[$i];
      $impDetFlag[$i]=0;
    }
  }
  else
  {
    if (defined($LOG)) { select $LOG;  $|=1; print $LOG ""; $|=0;  select STDOUT; }
    if (!$plotFlag)
    {
      logdiag("end flush")     if $utimeMask & 1;
      return;
    }
    return    if !$plotFlag;

    if ($BFlag)   { select BUD;  $|=1; print BUD ""; $|=0; }
    if ($CFlag)   { select CPU;  $|=1; print CPU ""; $|=0; }
    if ($DFlag)   { select DSK;  $|=1; print DSK ""; $|=0; }
    if ($EFlag)   { select ENV;  $|=1; print ENV ""; $|=0; }
    if ($FFlag)   { select NFS;  $|=1; print NFS ""; $|=0; }
    if ($NFlag)   { select NET;  $|=1; print NET ""; $|=0; }
    if ($TFlag)   { select TCP;  $|=1; print TCP ""; $|=0; }
    if ($XFlag && $NumXRails)                  { select ELN;  $|=1; print ELN ""; $|=0; }
    if ($XFlag && $NumHCAs)                    { select IB;   $|=1; print IB  ""; $|=0; }
    if ($YFlag && !$rawtooFlag)                { select SLB;  $|=1; print SLB ""; $|=0; }
    if ($ZFlag && !$rawtooFlag)                { select PRC;  $|=1; print PRC ""; $|=0; }
    if ($LFlag && $CltFlag)                    { select CLT;  $|=1; print CLT ""; $|=0; }
    if ($LFlag && $OstFlag)                    { select OST;  $|=1; print OST ""; $|=0; }
    if ($LFlag && $lustOpts=~/D/)              { select BLK;  $|=1; print BLK ""; $|=0; }

    # Handle --import
    for (my $i=0; $i<$impNumMods; $i++)
    {
      if (defined($impText[$i]))  { select $impText[$i];  $|=1; print {$impText[$i]} ""; $|=0; }
    }

    if ($options=~/x/i)
    {
      if ($DFlag) { select DSKX;  $|=1; print DSKX ""; $|=0; }
    }
    select STDOUT;
  }
  logdiag("end flush")     if $utimeMask & 1;
}

sub writeError
{
  my $file=shift;
  my $desc=shift;

  # just print the error and reopen ALL files (since it should be rare)
  # we also don't need to set '$recMode' in newLog() since not recursive.
  $zlibErrors++;
  logmsg("E", "Write error - File: $file Reason: ".$desc->gzerror());
  logmsg("F", "Max Zlib error count exceeded")    if $zlibErrors>$MaxZlibErrors;
  $headersPrinted=0;
  newLog($filename, "", "", "", "", "");
}

sub flushError
{
  my $file=shift;
  my $desc=shift;

  # just print the error and reopen ALL files (since it should be rare)
  # we also don't need to set '$recMode' in newLog() since not recursive.
  $zlibErrors++;
  logmsg("E", "Flush error - File: $file Reason: ".$desc->gzerror());
  logmsg("F", "Max Zlib error count exceeded")    if $zlibErrors>$MaxZlibErrors;
  $headersPrinted=0;
  newLog($filename, "", "", "", "", "");
}

# write diagnostic record into raw file
sub logdiag
{
  my ($intSeconds, $intUsecs)=Time::HiRes::gettimeofday();
  my $fullTime=sprintf("%d.%06d",  $intSeconds, $intUsecs);
  record(1, "### $fullTime $_[0]\n");
}

# Note - ALL errors (both E and F) will be written to syslog.  If you want
# others to go there (such as startup/shutdown messages) you need to call
# logsys() directly, but be sure to make sure $filename ne '' (but can't
# unless $filename is known at that point).
sub logmsg
{
  my ($severity, $text)=@_;
  my ($ss, $mm, $hh, $day, $mon, $year, $msg, $time, $logname, $yymm, $date);

  # may need time if in debug and this routine gets called infrequently enough
  # that the extra processing is no big deal.  Also note that time and gettimeofday
  # are not always exactly in sync so when hires loaded, ALWAYS use it
  my $timesecs=($hiResFlag) ? (Time::HiRes::gettimeofday())[0] : time();
  ($ss, $mm, $hh, $day, $mon, $year)=localtime($timesecs);
  $time=sprintf("%02d:%02d:%02d", $hh, $mm, $ss);

  # always report non-informational messages and if not logging, we're done
  # BUT - if not attached to a terminal or not running as a daemon we CAN'T print 
  # because no terminal to talk to.
  # Also, not that we ONLY write to the log when writing to a file and -m
  $text="$time $text"      if $debug & 1;
  print STDERR "$text\n"   if $termFlag && !$daemonFlag && ($msgFlag || ($severity eq 'W' && !$quietFlag) || $severity=~/[EF]/ || $debug & 1);
  exit(1)                  if !$msgFlag && $severity eq "F";

  # Remember: if running as a daemon and NOT -m, we'll never see any messages
  # in collectl log OR syslog.
  return                   unless $msgFlag && $filename ne '';

  $yymm=sprintf("%d%02d", 1900+$year, $mon+1);
  $date=sprintf("%d%02d%02d", 1900+$year, $mon+1, $day);
  $msg=sprintf("%s-%s", $severity, $text);

  # the log file live in same directory as logs
  $logname=(-d $filename) ? $filename : dirname($filename);
  $logname.="/$myHost-collectl-$yymm.log";
  open  MSG, ">>$logname"        or logsys("Couldn't open log file '$logname' to write: $msg", 1);
  print MSG "$date $time $msg\n" or logsys("Print Error: $! Text: $msg");
  close MSG;

  logsys($msg)     if $severity=~/[EF]/;
  exit(1)          if $severity=~/F/;
}

sub logsys
{
  my $message=shift;
  my $force=  shift;

  # if not writing to a file, only log when forced
  return    if $PcFlag || ($filename eq '' && !$force);

  $x=Sys::Syslog::openlog($Program, "", "user");
  $x=Sys::Syslog::syslog("info", "%s", $message);
  Sys::Syslog::closelog();
}

# this is for non-fatal messages that are reported before collectl actually
# starts.  by saving them, we can then report after the startup message to
# make things cleaner in the log
sub pushmsg
{
  my $severity=shift;
  my $text=    shift;

  push @messages, "$severity-$text";
}

sub setFlags
{
  my $subsys=shift;

  print "SetFlags: $subsys\n"    if $debug & 1;

  # NOTE - are flags are faster than string compares?
  # unfortunately I got stuck using zFlag for ZIP and ZFlag for processes
  $bFlag=($subsys=~/b/) ? 1 : 0;  $BFlag=($subsys=~/B/) ? 1 : 0;
  $cFlag=($subsys=~/c/) ? 1 : 0;  $CFlag=($subsys=~/C/) ? 1 : 0;
  $dFlag=($subsys=~/d/) ? 1 : 0;  $DFlag=($subsys=~/D/) ? 1 : 0;
                                  $EFlag=($subsys=~/E/) ? 1 : 0;
  $fFlag=($subsys=~/f/) ? 1 : 0;  $FFlag=($subsys=~/F/) ? 1 : 0;
  $iFlag=($subsys=~/i/) ? 1 : 0;
  $jFlag=($subsys=~/j/) ? 1 : 0;  $JFlag=($subsys=~/J/) ? 1 : 0;
  $lFlag=($subsys=~/l/) ? 1 : 0;  $LFlag=($subsys=~/L/) ? 1 : 0;  
  $mFlag=($subsys=~/m/) ? 1 : 0;  $MFlag=($subsys=~/M/) ? 1 : 0;
  $nFlag=($subsys=~/n/) ? 1 : 0;  $NFlag=($subsys=~/N/) ? 1 : 0;
  $sFlag=($subsys=~/s/) ? 1 : 0;
  $tFlag=($subsys=~/t/) ? 1 : 0;  $TFlag=($subsys=~/T/) ? 1 : 0;
  $xFlag=($subsys=~/x/) ? 1 : 0;  $XFlag=($subsys=~/X/) ? 1 : 0;
  $yFlag=($subsys=~/y/) ? 1 : 0;  $YFlag=($subsys=~/Y/) ? 1 : 0;
                                  $ZFlag=($subsys=~/Z/) ? 1 : 0;

  # NOTE - the definition of 'core' as slightly changed and maybe should be
  # changed to be 'summary' to better reflect what we're trying to do.  
  $coreFlag=($subsys=~/[a-z]/) ? 1 : 0;

  # by default, all data gets logged in a single file.  if the 'tworaw' flag is set,
  # we defined flags that control recording into groups based on process/other
  $recFlag0=1;
  $recFlag1=0;
  if ($tworawFlag)
  {
    $tempSys=$subsys;
    $tempSys=~s/[YZ]//g;
    $recFlag0=0    if $tempSys eq '';
    $recFlag1=1    if $subsys=~/[YZ]/;
  }
  print "RecFlags: $recFlag0 $recFlag1\n"    if $debug & 1 && !$playback;
}

sub setNFSFlags
{
  my $nfsFilt=shift;

  #  Assume no NFS data of any type seen yet.  Do it twice to get rid of -w warning
  $nfs2CSeen=$nfs3CSeen=$nfs4CSeen=$nfs2SSeen=$nfs3SSeen=$nfs4SSeen=0;
  $nfs2CSeen=$nfs3CSeen=$nfs4CSeen=$nfs2SSeen=$nfs3SSeen=$nfs4SSeen=0;

  if ($nfsFilt eq '')
  {
    $nfsCFlag=$nfsSFlag=$nfs2Flag=$nfs3Flag=$nfs4Flag=1;
    $nfs2CFlag=$nfs2SFlag=$nfs3CFlag=$nfs3SFlag=$nfs4CFlag=$nfs4SFlag=1;
  }
  else
  {
    $nfsCFlag=$nfsSFlag=$nfs2Flag=$nfs3Flag=$nfs4Flag=0;
    $nfs2CFlag=$nfs2SFlag=$nfs3CFlag=$nfs3SFlag=$nfs4CFlag=$nfs4SFlag=0;
    foreach my $filt (split(/,/, $nfsFilt))
    {
      # These flags make processing easier/faster later on
      if    ($filt eq 'c2') { $nfsCFlag=1; $nfs2Flag=1; $nfs2CFlag=1; }
      elsif ($filt eq 's2') { $nfsSFlag=1; $nfs2Flag=1; $nfs2SFlag=1; }
      elsif ($filt eq 'c3') { $nfsCFlag=1; $nfs3Flag=1; $nfs3CFlag=1; }
      elsif ($filt eq 's3') { $nfsSFlag=1; $nfs3Flag=1; $nfs3SFlag=1; }
      elsif ($filt eq 'c4') { $nfsCFlag=1; $nfs4Flag=1; $nfs4CFlag=1; }
      elsif ($filt eq 's4') { $nfsSFlag=1; $nfs4Flag=1; $nfs4SFlag=1; }
      else { error("--nfsfilt option '$filt' not one of 'c2,s2,c3,s3,c4,s4'"); }
    }
  } 
}

sub getSeconds
{
  my $date=shift;
  my $time=shift;
  my ($year, $mon, $day, $hh, $mm, $ss, $seconds);

  $year=substr($date, 0,  4);
  $mon= substr($date, 4,  2);
  $day= substr($date, 6,  2);
  $hh=  substr($time, 0,  2);
  $mm=  substr($time, 2, 2);
  $ss=  substr($time, 4, 2);

  return(timelocal($ss, $mm, $hh, $day, $mon-1, $year-1900));
}

# print error and exit if bad datetime without going crazy over all the
# possible purmutations of a bad date/time format
sub checkTime
{
  my $switch=  shift;
  my $datetime=shift;

  my $date=0;   # can't return ''
  my $time=$datetime;
  if (length((split(/:/,$datetime))[0])>2)
  {
    $datetime=~s/^(\d+):?(.*)//;
    $date=$1;
    $time=$2;
  }
  $time=($switch eq '--from') ? '00:00:00' : '23:59:59'    if $time eq '';
  error("Date portion of $switch must be exactly 8 digits")
      if $date!=0 && length($date)!=8;

  # Make sure time format correct. minimal being HH:MM. supply date and/or ":ss"
  $time="0$time"    if $time=~/^\d{1}:/;
  $time.=":00"      if $time!~/^\d{2}:\d{2}:\d{2}$/;
  error("$switch time format must be hh:mm[:ss]")    if ($time!~/^\d{2}:\d{2}:\d{2}$/);

  ($hh, $mm, $ss)=split(/:/, $time);
  error("$switch specifies invalid time")    if ($hh>23 || $mm >59 || $ss>59);

  return(($date,"$hh$mm$ss"));
}

sub getDateTime
{
  my $seconds=shift;
  my ($sec, $min, $hour, $day, $mon, $year)=localtime($seconds);
  return(sprintf("%d%02d%02d %02d:%02d:%02d", $year+1900, $mon+1, $day, $hour, $min, $sec));
}

sub checkHiRes
{
  if ($TimeHiResCheck && $hiResFlag && -e '/lib/libc.so.6')
  {
    my $hiResVersion=Time::HiRes->VERSION;
    $hiResVersion=~/(\d+)\.(\d+)/;
    my $hiResMajor=$1;
    my $hiResMinor=$2;
    
    my $glibcAnnounce=`'/lib/libc.so.6'`;
    if ($hiResMajor==1 && $hiResMinor<91 &&
	$glibcAnnounce=~/GNU C Library stable release version (\d+)\.(\d+)/)
    {
      my $glibcMajor=$1;
      my $glibcMinor=$2;
      if ($glibcMajor==2 && ($glibcMinor==4 || $glibcMinor==5))
      {
        logmsg('W', "WARNING - Your versions of Time::HiRes and glibc are incompatible.");
	logmsg('W', "          See /opt/hp/collectl/docs/RELEASE-collectl 'Restrictions' for details.");
      }
    }
  }
}


# This is only called during collection, not playback
sub closeLogs
{
  my $subsys=shift;
  my $ctype= shift;
  return    if !$logToFileFlag;

  # when not specified, close both raw and plot files.
  $ctype='rp'    if !defined($ctype);

  setFlags($subsys);
  
  #    C l o s e    R a w    F i l e ( s )

  # closing raw files based on presence of zlib and NOT -oz
  if ($rawFlag && $ctype=~/r/)
  {
    print "Closing raw logs\n"    if $debug & 1;
    if ($zlibFlag && $logToFileFlag)
    {
      $ZRAW->  gzclose()    if $recFlag0;
      $ZRAWP-> gzclose()    if $recFlag1;
    }
    else
    {
      close $RAW     if defined($RAW)  && $recFlag0;
      close $RAWP    if defined($RAWP) && $recFlag1;
    }
  }

  #    C l o s e    P l o t    F i l e ( s )

  if ($plotFlag && $ctype=~/p/)
  {
    print "Closing plot logs\n"    if $debug & 1;

    # Even if not open, can't hurt to close them.
    if (!$zFlag)
    {
      close LOG;
      close BLK;
      close BUD;
      close CPU;
      close CLT;
      close DSK;
      close DSKX;
      close ELN;
      close IB;
      close ENV;
      close NFS;
      close NET;
      close OST;
      close TCP;
      close SLB;
      close PRC;
    }
    else  # These must be opened in order to close them
    {
      $temp="$SubsysCore$SubsysExcore";
      $ZLOG-> gzclose()     if $subsys=~/[$temp]+/ || $impSummaryFlag;
      $ZBUD-> gzclose()     if $BFlag;
      $ZCLT-> gzclose()     if $LFlag && CltFlag;
      $ZCPU-> gzclose()     if $CFlag;
      $ZDSK-> gzclose()     if $DFlag && $options!~/x/;
      $ZDSKX->gzclose()     if $DFlag && $options=~/x/i;
      $ZELN-> gzclose()     if $XFlag && $NumXRails;
      $ZIB->  gzclose()     if $XFlag && $NumHCAs;
      $ZENV-> gzclose()     if $EFlag;
      $ZNFS-> gzclose()     if $FFlag;
      $ZNUMA->gzclose()     if $MFlag;
      $ZNET-> gzclose()     if $NFlag;
      $ZOST-> gzclose()     if $LFlag && $OstFlag;
      $ZTCP-> gzclose()     if $TFlag;
      $ZSLB-> gzclose()     if $YFlag && !$rawtooFlag && !$slabAnalOnlyFlag;
      $ZPRC-> gzclose()     if $ZFlag && !$rawtooFlag && !$procAnalOnlyFlag;
    }

    # Finally, close any detail logs that may have been opened via --import
    for (my $i=0; $i<$impNumMods; $i++)
    {
      next    if $impOpts[$i]!~/d/;
      close $impText[$i]       if !$zFlag;
      $impGz[$i]->gzclose()    if  $zFlag;
    }
  }
}

sub loadConfig
{
  my $resizePath='';
  my ($line, $num, $param, $value, $switches, $file, $openedFlag, $lib);

  # If no specified config file, look in /etc and then BinDir and then MyDir
  # Note - we can't use ':' as a separator because that screws up windows!
  if ($configFile eq '')
  {
    $configFile="/etc/$ConfigFile;$BinDir/$ConfigFile";
    $configFile.=";$MyDir/$ConfigFile"    if $BinDir ne '.' && $MyDir ne $BinDir;
  }
  print "Config File Path: $configFile\n"    if $debug & 1;

  $openedFlag=0;
  foreach $file (split(/;/, $configFile))
  {
    if (open CONFIG, "<$file")
    {
      print "Reading Config File: $file\n"    if $debug & 1;
      $configFile=$file;
      $openedFlag=1;
      last;
    }
  }
  logmsg("F", "Couldn't open '$configFile'")    if !$openedFlag;

  $num=0;
  foreach $line (<CONFIG>)
  {
    $num++;
    next    if $line=~/^\s*$|^\#/;    # skip blank lines and comments

    if ($line!~/=/)
    {
      logmsg("W", "CONFIG ERROR:  Line $num doesn't contain '='.  Ignoring...");
      next;
    }

    chomp $line;
    ($param, $value)=split(/\s*=\s*/, $line);
    print "Param: $param  Value: $value\n"    if $debug & 128;

    #    S u b s y s t e m s    A r e   S p e c i a l
 
    # Subsystems -- this is a little tricky because after user overrides
    # SubsysCore, SubsysExcore needs to contain all other core subsystems.
    if ($param=~/SubsysCore/)
    {
      # we put everything in 'Excore' and substract what's in 'Core'
      $SubsysExcore="$SubsysCore$SubsysExcore";
      error("config file entry for '$param' contains invalid subsystem(s) - $value")
	  if $value!~/^[$SubsysExcore]+$/;

      $SubsysCore=$value;
      $SubsysExcore=~s/[$SubsysCore]//g;
      next;
    }

    #    D a e m o n    P r o c e s s i n g

    elsif ($param=~/DaemonCommands/ && $daemonFlag)
    { 
      # Pull commmand string off line and add a 'special' end-of-line marker.
      # Note that we save off the whole thing for the header and we need the
      # ',2' in the split since we can have '=' in the options
      $DaemonOptions=$switches=(split(/=\s*/, $line, 2))[1];
      $switches.=" -->>>EOL<<<";

      # ultimately, we want to prepend these onto the ARG list.  The problem is we need to
      # preserve the order and the easiest way to do this is to push onto a temp stack
      # and pop off when we're done.
      my $quote='';
      my $switch='';
      my @temp;
      foreach $param (split(/\s+/, $switches))
      {
        if ($param=~/^-/)
        {
          # If new switch, time to write out old one (and arg), but note we're pushing them
          # onto a stack so recan retrieve them in the reverse order
	  if ($switch ne '')
          {
	    push @temp, $switch;
	    push @temp, $arg    if $arg ne '';
  	  }

	  last    if $param eq '-->>>EOL<<<';
          $switch=$param;
	  $arg='';
          next;
	}
        elsif ($quote ne '')    # Processing quoted argument
        {
	  $quote=''    if $param=~/$quote$/;    # this is the last piece
	  $arg.=" $param";
	  next        if $quote ne '';
        }
	else  # unquoted argument
        {
          $arg=$param;
          $quote=$1    if $param=~/^(['"])/;
        }
      }

      # now put them back, preserving the order
      while (my $arg=pop(@temp))
      {	unshift(@ARGV, $arg); }
      #foreach my $arg (@ARGV) { print "$arg "; } print "\n"; exit;
    }   

    #    L i b r a r i e s    A r e    S p e c i a l    T o o

    elsif ($param=~/Libraries/)
    {
      $Libraries=$value;
      foreach $lib (split(/\s+/, $Libraries))
      {
        push @INC, $lib;
      }
    }

    #    S t a n d a r d    S e t

    else
    {
      $ReqDir=$value           if $param=~/^ReqDir/;
      $Grep=$value             if $param=~/^Grep/;
      $Egrep=$value            if $param=~/^Egrep/;
      $Ps=$value               if $param=~/^Ps/;
      $Rpm=$value              if $param=~/^Rpm/;
      $Lspci=$value            if $param=~/^Lspci/;
      $Lctl=$value             if $param=~/^Lctl/;
      $resizePath=$value       if $param=~/^Resize/;
      $ipmitoolPath=$value     if $param=~/^Ipmitool/;
      $IpmiCache=$value        if $param=~/^IpmiCache/;
      $IpmiTypes=$value        if $param=~/^IpmiTypes/;

      # For Infiniband
      $PCounter=$value         if $param=~/^PCounter/;
      $PQuery=$value           if $param=~/^PQuery/;
      $VStat=$value            if $param=~/^VStat/;
      $IbDupCheckFlag=$value   if $param=~/^IbDupCheckFlag/;
      $OfedInfo=$value         if $param=~/^OfedInfo/;

      $Interval=$value         if $param=~/^Interval$/;
      $Interval2=$value        if $param=~/^Interval2/;
      $Interval3=$value        if $param=~/^Interval3/;
      $LimSVC=$value           if $param=~/^LimSVC/;
      $LimIOS=$value           if $param=~/^LimIOS/;
      $LimLusKBS=$value        if $param=~/^LimLusKBS/;
      $LimLusReints=$value     if $param=~/^LimLusReints/;
      $LimBool=$value          if $param=~/^LimBool/;
      $Port=$value             if $param=~/^Port/;
      $Timeout=$value          if $param=~/^Timeout/;
      $MaxZlibErrors=$value    if $param=~/^ZMaxZlibErrors/;
      $LustreSvcLunMax=$value  if $param=~/^LustreSvcLunMax/;
      $LustreMaxBlkSize=$value  if $param=~/^LustreMaxBlkSize/;
      $LustreConfigInt=$value  if $param=~/^LustreConfigInt/;
      $InterConnectInt=$value  if $param=~/^InterConnectInt/;
      $TermHeight=$value       if $param=~/^TermHeight/;
      $DefNetSpeed=$value      if $param=~/^DefNetSpeed/;
      $TimeHiResCheck=$value   if $param=~/^TimeHiResCheck/;
      $PasswdFile=$value       if $param=~/^Passwd/;

      $DiskMaxValue=$value     if $param=~/^DiskMaxValue/;
      $dISKfILTER=$value       if $param=~/^DiskFilter/;  # note different spelling!!!

      $ProcReadTest=$value     if $param=~/^ProcReadTest/;
    }
  }
  close CONFIG;

  foreach my $bin (split/:/, $resizePath)
  {
    $Resize=$bin    if -e $bin;
  }
  logmsg('I', "Couldn't find 'resize' so assuming terminal height of 24")
      if $Resize eq '';

  # Just in case using an older collectl.conf file.  Only a problem if
  # someone wants to collect IPMI data.
  if (!defined($ipmitoolPath))
  {
    logmsg('E', "Can't find 'Ipmitool' in 'collectl.conf'.  Is it old?");
    $ipmitoolPath='';
  }

  # Even though currently one entry, let's make this a path like above
  $Ipmitool='';
  foreach my $bin (split/:/, $ipmitoolPath)
  {
      $Ipmitool=$bin    if -e $bin;
  }

  # Unlike other parameters that can be overridden in collectl.conf, we DO need to know if
  # that has been done with DiskFilter so we can set the flag correctly and only then
  if (defined($dISKfILTER))
  {
    # the leading/trailing /s are just there for ease of reading in collectl.conf
    $DiskFilterFlag=1;
    $DiskFilter=$dISKfILTER;
    $DiskFilter=~s/^\///;
    $DiskFilter=~s/\/$//;
    print "DiskFilter set in $configFile: >$DiskFilter<\n"    if $debug & 1;
  }
}

sub loadSlabs
{
  my $slabFilt= shift;

  if ($slabinfoFlag)
  {
    if (!open PROC,"</proc/slabinfo")
    {
      logmsg("W", "Slab monitoring disabled because /proc/slabinfo doesn't exist");
      $yFlag=$YFlag=0;
      $subsys=~s/y//ig;
      return;
    }

    while (my $line=<PROC>)
    {
      my $slab=(split(/\s+/, $line))[0];
      foreach my $filter (split(/,/, $slabFilt))
      {
        if ($slab=~/^$filter/)
        {
	  $slabProc{$slab}=1;
	  last;
	}
      }
    }

    if ($debug & 1024)
    {
      print "*** SLABS ***\n";
      foreach $slab (sort keys %slabProc)
      { print "$slab\n"; }
    }
  }

  if ($slubinfoFlag)
  {
    ###########################################
    #    build list of all slabs NOT softlinks
    ###########################################

    opendir SYS, '/sys/slab' or logmsg('F', "Couldn't open '/sys/slab'");
    while (my $slab=readdir(SYS))
    {
      next    if $slab=~/^\./;

      # If a link, it's actually an alias
      $dirname="/sys/slab/$slab";
      if (-l $dirname)
      {
        # If filtering, only keep those aliases that match
        next    if $slabFilt ne '' && !passSlabFilter($slabFilt, $slab);

        # get the name of the slab this link points to
        my $linkname=readlink($dirname);
        my $rootslab=basename($linkname);

        # Note that since scalar returns the number of elements, it's always the index
        # we want to write the next entry into.  We also want to save a list of the link
        # names so we can easily skip over them later.
        my $alias=(defined($slabdata{$rootslab}->{aliases})) ? scalar(@{$slabdata{$rootslab}->{aliases}}) : 0;
        $slabdata{$rootslab}->{aliases}->[$alias]=$slab;
        $slabskip{$slab}=1;
      }
      else
      {
        $slabdata{$slab}->{lastobj}=$slabdata{$slab}->{lastslabs}=0;
      }
    }
   
    ##########################################
    #    secondary filter scan
    ##########################################

    if ($slabFilt ne '')
    {
      # Note, at this point we only have aliases that pass the filter and so we need
      # to keep the entries OR we have entries with no aliases that might still pass 
      # filters only we couldn't check them yet so we need this second pass.
      foreach my $slab (keys %slabdata)
      {
        delete $slabdata{$slab}
	    if !defined($slabdata{$slab}->{aliases}) && !passSlabFilter($slabFilt, $slab)
      }
    }

    ############################################################
    #    now find a better name to use, choosing length first
    ############################################################

    # what we want to do here is also build up a list of all the aliases to
    # make it easier to insert them into the header as well as display with
    # --showslabaliases.  Also note is --showrootslabs, we override '$first'
    # to that of the slab root name.
    foreach my $slab (sort keys %slabdata)
    {
      my ($first,$kmalloc,$list)=('','',' ');    # NOTE - $list set to leading space!
      foreach my $alias (@{$slabdata{$slab}->{aliases}})
      {
	$list.="$alias ";
	$kmalloc=$alias    if $alias=~/^kmalloc/;
	$first=$alias      if $alias!~/^kmalloc/ && length($alias)>length($first);
      }
      $first=$kmalloc    if $first eq '';
      $first=$slab       if $first eq '' || $showRootSlabsFlag;
      $slabdata{$slab}->{first}=$first;
      $slabfirst{$first}=$slab;

      # note that in some cases there is only a single alias in which case 'list' is ''
      $list=~s/ $first / /;
      $list=~s/^ | $//g;
      $slabdata{$slab}->{aliaslist}=$first       if $first ne $slab;
      $slabdata{$slab}->{aliaslist}.=" $list"    if $list ne '';
    } 
    ref($slabfirst);    # need to mention it to eliminate -w warning
  }
}

sub passSlabFilter
{
  my $filters=shift;
  my $slab=   shift;

  foreach my $name (split(/,/, $filters))
  {
    return(1)    if $slab=~/^$name/;
  }
  return(0);
}

# This needs some explaining...  When doing processes, we build a list of all the pids that
# match the --procfilt selection.  However, over time a selected command could exist and restart again
# under a different pid and we WANT to pick that up too.  So, everytime we check the processes
# and a non-pid selector has been specified we will have to recheck ALL pids to see in any new
# ones show up.  Naturally we can skip those in @skipPids and if the flag $pidsOnlyFlag is set
# we can also skip the pid checking.  Finally, since over time the list of pids can grow 
# unchecked we need to clean out the stale data after every polling cycle.
sub loadPids
{
  my $procs=shift;
  my ($process, $pid, $ppid, $user, $uid, $cmd, $line, $file, $temp);
  my ($type, $value, @ps, $selector, $pidOnly);

  # Step 0 - an enhancement!  If the process list string is actually a 
  # filename turn entries into one long string as if entered with --procfilt.
  # This makes it possible to have a constant --procfilt parameter yet change
  # the process list dynamically, before starting collectl.
  if (-e $procs)
  {
    $temp='';
    open TEMP, "<$procs" or logmsg("F", "Couldn't open --procfilt file");
    while ($line=<TEMP>)
    {
      chomp $line;
      next    if $line=~/^#|^\s*$/;  # ignore blank lines
      $line=~s/\s+//g;               # get rid of ALL whitespace in each line
      $temp.="$line,"                # smoosh it all together
    }
    $temp=~s/,$//;                   # get rid of trailing comma
    $procs=$temp;
  }

  # this is pretty brute force, but we're only doing it at startup
  # Step 1 - validate list for invalid types OR non-numeric pids
  #          assume including collectl
  $oneThreadFlag=($procs=~/\+/) ? 1 : 0;    # handy flag to optimize non-thread cases
  $uidMin=$uidMax=$uidSelFlag=0;
  foreach $task (split(/,/, $procs))
  {
    # for now, we don't do too much validation, but be sure to note
    # if our pid was requsted via 'p%'
    if ($task=~/^([cCpfPuU])\+*(.*)/)
    {
      $type=$1;
      $value=$2;

      if ($type=~/u/ && $value=~/(\d+)-(\d+)/)
      {
        # uids are a special case in that one can specify range or multiple singletons but not multiple
        # ranges.  when we DO see a range, save it's min/max but DON'T include in the array of selectors
        error("you cannot specify multiple uuid ranges in --procfilt")    if $uidMin;

        $uidMin=$1;
	$uidMax=$2;
        $uidSelFlag=1;
        next;
      }

      # if we ever do allow this in playback we can't handle 'f'
      error("--procfilt f not allowed in playback mode")    if $type eq 'f' && $playback ne '';

      # pids must be numeric
      error("pid $value not numeric in --procfilt")    if $type=~/p/i && $value!~/^\d+$/;

      # max usernames returned by ps w/o converting to UID looks to be 19
      error("cannot use usernames > 19 chars with procfilt")    if $type=~/U/ && length($value)>19;

      # max command name length returned by ps o comm looks to be 15
      error("cannot use commands > 15 chars with procfilt c/C")    if $type=~/c/i && length($value)>15;

      # when dealing with embedded string in command line, note that spaces
      # are converted to NULs, so do it to our match string so it only happens
      # once and also be sure to quote any meta charaters the user may have
      # in mind to use.
      if ($type eq 'f')
      {
        $task=~s/ /\000/g;
	$task=quotemeta($task);
      }

      push @TaskSelectors, $task;
      next;
    }
    else
    {
      error("invalid task selection in --procfilt: $task");
    }
  }

  # Step 2 - no longer needed.  UIDs loaded earlier

  # Step 3 - find pids of all processes that match selection criteria
  #          be sure to truncate leading spaces since pids are fixed width
  # Note: $cmd includes full directory path and args.  Furthermore, this is NOT
  # what gets stored in /proc/XXX/stat and to make sure we look at the same 
  # values dynamically as well as staticly, we better pull cmd from the stat
  # file itself.
  @ps=`ps axo pid,ppid,uid,comm,user`;
  my $firstFilePass=1;
  foreach $process (@ps)
  {
    next    if $process=~/^\s+PID/;
    $process=~s/^\s+//;

    chomp $process;
    ($pid, $ppid, $uid, $cmd, $user)=split(/\s+/, $process);

    # if no criteria, select ALL
    if ($procs eq '')
    {
      $pidProc{$pid}=1;
      next;
    }

    # If uid range specified and this UID there, save it noting it's not
    # part of the task selection list so we do before the loop below.
    if ($uidMin>0 && $uid>=$uidMin && $uid<=$uidMax)
    {
      $pidOnly=0;
      $pidProc{$pid}=1;
      next;
    }

    # select based on criteria, but assume we're not getting a match
    $pidOnly=1;
    $keepPid=0;
    foreach $selector (@TaskSelectors)
    {
      $pidOnly=0    if $selector!~/^p/;
      $uidSelFlag=1    if $selector=~/^u/i;    # need to know if doing UID matching

      if (($selector=~/^p\+*(.*)/ && $pid eq $1)  ||
	  ($selector=~/^P\+*(.*)/ && $ppid eq $1) ||
	  ($selector=~/^c\+*(.*)/ && $cmd=~/$1/)  ||
	  ($selector=~/^C\+*(.*)/ && $cmd=~/^$1/) ||
          ($selector=~/^f\+*(.*)/ && cmdHasString($pid,$1)) ||
	  ($selector=~/^u\+*(.*)/ && $uid eq $1)  ||
          ($selector=~/^U\+*(.*)/ && $user eq $1))
      {
	# We need to figure out if '+' appended to selector and set flag if so.
	# However, since it's extra overhead to maintain %pidThreads, we only set it
        # when there are threads to deal with.
	$pidThreads{$pid}=(substr($selector, 1, 1) eq '+') ? 1 : 0
	    if $oneThreadFlag;

	$keepPid=1;
	last;
      }
    }

    if ($keepPid)
    { $pidProc{$pid}=1; }
    else
    { $pidSkip{$pid}=1; }
  }

  # STEP 4 - deal with threads
  # &pidThreads has been set to 1 for any pids we want to watch threads for. 
  # We clean this up when we clean pids in general.  If no pid threads, 
  # no %pidThreads.
  foreach $pid (keys %pidThreads)
  {
    findThreads($pid)    if $pidThreads{$pid};
  }

  # if a selection list and it's only for pids (and doesn't include uxx-yy), set 
  # the $pidOnlyFlag so that those are all we ever want to look for
  # for force the $pidsOnlyFlag to be set.  It's those minor optimization
  # in life that count!
  $pidOnlyFlag=1    if $procs ne '' && !$uidMin && $pidOnly;

  if ($debug & 256)
  {
    print "PIDS  Selected: ";
    foreach $pid (sort keys %pidProc)
    {
      print "$pid ";
    }
    print "\n";
    if ($oneThreadFlag)
    {
      print "TPIDS Selected: ";
      foreach $pid (sort keys %tpidProc)
      {
        print "$pid ";
      }
    }
    print "\nPIDS  Skipped:  ";
    foreach $pid (sort keys %pidSkip)
    {
      print "$pid ";
    }
    print "\n";
    print "\$pidOnlyFlag set!!!\n"           if $pidOnlyFlag;
  }
}

sub loadUids
{
  my $passwd=shift;
  my (@passwd, $line, $user, $uid);
  print "Load UIDS from $passwd\n"    if $debug & 1;

  if (!-e $passwd)
  {
    print "WARNING - UID translation file '$passwd' doesn't exist.  consider using --passwd\n";
    return;
  }

  @passwd=`$Cat $passwd`;
  foreach $line (@passwd)
  {
    next    if $line=~/^\+|^\s*$/;    # ignore '+' and blank lines

    ($user, $uid)=(split(/:/, $line))[0,2];
    $UidSelector{$uid}=$user;
  }
}

# here we have just found a new pid neither in the list to skip nor to process so
# we have to go back to our selector list and see if it meets the selection specs.
# if so, return the pid AND be sure to add to pidProc{} so we don't come here again.
# There are time we get called and /proc/$pid doesn't exist anymore.  This is
# because these are short lived processes that are there where in the directory
# when first read but are gone by the time we want to open them.  For efficiency
# we do a test to see if the pid directory exists and then trap later opens in case it
# disappeared by then!
# NOTE - we could probably return 0/1 depending on whether or not pid found, but since
#        it's already in the $match variable, we return that for convenience
sub pidNew
{
  my $pid=shift;
  my ($selector, $type, $param, $match, $cmd, $ppid, $line, $uid);

  return(0)    if !-e "/proc/$pid/stat";

  # if no filter, by defition this is a match
  $match=($procFilt ne '') ? 0 : $pid;

  # if selecting by uid (either as a range or explict match), try to read this procs
  # UID and if not there, no match!
  if ($uidSelFlag)
  {
    $uid=0;
    open TMP, "</proc/$pid/status" or return(0);    # went away between first check and now!
    while ($line=<TMP>)
    {
      if ($line=~/^Uid:\s+(\d+)/)
      {
	$uid=$1;
	last;
      }
    }

    # If UID not found it will be 0 and the following always fail
    $match=$pid    if $uidMin>0 && $uid>=$uidMin && $uid<$uidMax;
  }

  foreach $selector (@TaskSelectors)
  {
    $type=substr($selector, 0, 1);
    next              if  $type eq 'p';    # if a pid, can't be a new one

    $param=substr($selector, 1);
    if ($oneThreadFlag)
    {
      $param=~s/(\+)//;
      $pidThreads{$pid}=($1 eq '+') ? 1 : 0;
    }

    # match on parents pid?  or command?
    if ($type=~/[PCc]/)
    {
      open PROC, "</proc/$pid/stat" or return(0);
      $temp=<PROC>;
      ($cmd, $ppid)=(split(/ /, $temp))[1,3];
      $cmd=~s/[()]//g;

      if (($type eq 'P' && $param==$ppid)      ||
          ($type eq 'C' && $cmd=~/^$param/) ||
          ($type eq 'c' && $cmd=~/$param/))
      {
        $match=$pid;
	last;
      }
    }

    # match on full command path?
    elsif ($type=~/f/ && cmdHasString($pid, $param))
    {
      $match=$pid;
      last;
    }

    # match on UID
    elsif ($type=~/u/ && $uid==$param)
    {
      $match=$pid;
      last;
    }

    # match on username
    elsif ($type=~/U/ && defined($UidSelector{$uid}) && $UidSelector{$uid} eq $param)
    {
      $match=$pid;
      last;
    }
  }
  print "%%% Discovered new pid for monitoring: $pid\n"
      if $match && ($debug & 256);
  $pidProc{$match}=1     if $match!=0;
  findThreads($match)    if $match && $oneThreadFlag && $pidThreads{$pid};

  # since this pid didn't match selection criteria, don't look at it again.
  # but, whenever we cycle though all the pids and delete the entire 'skip'
  # hash so in case someone we reuses a pid we skipped.
  if (!$match)
  {
    $pidSkip{$pid}=1;

    my $num=0;
    foreach my $pid (keys %pidSkip)
    { $num++; }

    # we only care about the first pid seen at the start of a monitoring interval
    if ($firstProcCycle)
    {
      if ($debug & 4096)
      {
       my $seconds=int($fullTime);
       my $timenow=(split(/\s+/, localtime($seconds)))[3];
       printf "$timenow New PID: %5d  LastNew: %5d NumPids: %4d NumSkip: $num\n", 
           $pid, $lastFirstPid, $pid-$lastFirstPid;
      }

      if ($pid<$lastFirstPid)
      {
	undef(%pidSkip);
	$pid=0;    # so we reset $lastFirstPid
	print "skipped pids flushed...\n"    if $debug & 4096;;
      }

      $firstProcCycle=0;
      $lastFirstPid=$pid;
    }
  }

  return($match);
}

# see if the command that started a process contains a string
sub cmdHasString
{
  my $pid=   shift;
  my $string=shift;
  my $line;

  # never include ourself when matching by a command line string since it will
  # ALWAYS match the collectl command itself
  return()    if $pid==$$;

  # Not an error because proc may have already exited
  return(0)    if (!open PROC, "</proc/$pid/cmdline");
  $cmdline=<PROC>;

  # since not all processes have command line associated with them be sure to
  # check before looking for a match and only return success after making it.
  return(!defined($cmdline) || $cmdline!~/$string/ ? 0 : 1)
}

# see if a pid has any active threads
sub findThreads
{
  my $pid=shift;

  # In some cases the thread owning process may have gone away.  When this 
  # happens we can't open 'task', so act accordingly.
  if (!opendir DIR2, "/proc/$pid/task")
  {
    logmsg("W", "Looks like $pid exited so not looking for new threads");
    $pidThreads{$pid}=0;
    return;
  }
  while ($tpid=readdir(DIR2))
  {
    next    if $tpid=~/^\./;    # skip . and ..
    next    if $tpid==$pid;     # skip parent beause already covered

    # since this routine gets called both at the start when %tpidProc is empty and
    # every thread found is new AND during runtime when they may not be, check the
    # active thread hash and only include it if not already there
    if (!defined($tpidProc{$tpid}))
    {
      print "%%% Discovered new thread $tpid for pid: $pid\n"    if $debug & 256;
      $tpidProc{$tpid}=$pid;        # add to thread watch list
    }
  }
}

sub cleanStalePids
{
  my ($pid, %pidTemp, %tpidTemp, $removeFlag, $x);

  $removeFlag=0;
  foreach $pid (keys %pidProc)
  {
    if ($pidSeen{$pid})
    {
      $pidTemp{$pid}=1;

      # If working with threads, we also need to purge the flag array that tells
      # us whether or not to look for thread pids
      $tpidTemp{$pid}=$pidThreads{$pid}    if $oneThreadFlag;      
    }
    else
    {
      print "%%% Stale Pid: $pid\n"    if $debug & 256;
      $removeFlag=1;
    }
  }

  if ($removeFlag)
  {
    undef %pidProc;
    undef %pidThreads;
    %pidProc=%pidTemp;
    %pidThreads=%tpidTemp;
  }
  undef %pidTemp;
  undef %tpidTemp;

  if ($debug & 512)
  {
    foreach $x (sort keys %pidProc)
    { print "%%% pidProc{}: $x = $pidProc{$x}\n"; }
  }
  return    unless $oneThreadFlag;
  
  # Do it again for threads...
  $removeFlag=0;
  foreach $pid (keys %tpidProc)
  {
    if ($tpidSeen{$pid})
    {
      $pidTemp{$pid}=$tpidProc{$pid};
    }
    else
    {
      print "%%% Stale TPid: $pid\n"    if $debug & 256;
      $removeFlag=1;
    }
  }

  if ($removeFlag)
  {
    undef %tpidProc;
    %tpidProc=%pidTemp;
  }
  undef %pidTemp;

  if ($debug & 512)
  {
    foreach $x (sort keys %tpidProc)
    { print "%%% tpidProc{}: $x = $tpidProc{$x}\n"; }
  }
}

sub showSlabAliases
{
  my $slabFilt=shift;

  # by setting the slub flag and calling the 'load' routine, we'll get the header
  # built
  $slubinfoFlag= (-e '/sys/slab') ? 1 : 0;
  error("this kernel does not support 'slub-based' slabs")    if !$slubinfoFlag;
  loadSlabs($slabFilt);

  foreach my $slab (sort keys %slabdata)
  {
    my $aliaslist=$slabdata{$slab}->{aliaslist};
    $aliaslist=$slab    if !defined($aliaslist);
    next    if $slab eq $aliaslist;
    printf "%-20s %s\n", $slab, $aliaslist    if $aliaslist=~/ /;
  }
  exit(0);
}

sub showVersion
{
  $temp='';
  $temp.=sprintf("zlib:%s,", Compress::Zlib->VERSION)     if $zlibFlag;
  $temp.=sprintf("HiRes:%s", Time::HiRes->VERSION)        if $hiResFlag;
  $temp=~s/,$//;
  $version=sprintf("collectl V$Version %s\n\n", $temp ne '' ? "($temp)" : '');
  $version.="$Copyright\n";
  $version.="$License\n";
  printText($version);
  exit(0);
}

sub showDefaults
{
  printText("Default values by switch:\n");
  printText("              Interactive   Daemon\n");
  printText("  -c             -1         -1\n");
  printText("  -i             1:$Interval2:$Interval3   $Interval:$Interval2:$Interval3\n");
  printText("  --lustsvcs      :$LustreConfigInt       :$LustreConfigInt\n");
  printText("  -s             cdn        $SubsysCore\n");
  printText("Defaults only settable in config file:\n");
  printText("  LimSVC        = $LimSVC\n");
  printText("  LimIOS        = $LimIOS\n");
  printText("  LimLusKBS     = $LimLusKBS\n");
  printText("  LimLusReints  = $LimLusReints\n");
  printText("  LimBool       = $LimBool\n");
  printText("  Port          = $Port\n");
  printText("  Timeout       = $Timeout\n");
  printText("  MaxZlibErrors = $MaxZlibErrors\n");
  printText("  Libraries     = $Libraries\n")    if defined($Libraries);
  exit(0);
}

sub envTest
{
  $subsys='E';
  open ENV, "<$envTestFile" or error("Couldn't open '$envTestFile'");
  while (my $line=<ENV>)
  {
    next    if $line=~/^\s*$|^#/;
    dataAnalyze('E', "ipmi $line");
  }
  close ENV;
  $briefFlag=0;
  $verboseFlag=1;
  intervalPrint(time);
  `stty echo`    if !$PcFlag && $termFlag && !$backFlag;
}

sub error
{
  my $text=shift;

  if (defined($text))
  {
    # when runing as a server, we need to turn off sockFlag otherwise
    # printText() will try to send error over socket and we want it local.
    $sockFlag=0    if $serverFlag;

    `stty echo`    if !$PcFlag && $termFlag && !$backFlag;
    logmsg("F", "Error: $text")    if $daemonFlag;

    # we can only call printText() when formatit loaded.
    if ($formatitLoaded)
    {
      printText("Error: $text\n");
      printText("type '$Program -h' for help\n");
    }
    else
    {
      print "Error: $text\n";
    }
    exit(1);
  }

my $help=<<EOF;
This is a subset of the most common switches and even the descriptions are
abbreviated.  To see all type 'collectl -x', to get started just type 'collectl'

usage: collectl [switches]
  -c, --count      count      collect this number of samples and exit
  -f, --filename   file       name of directory/file to write to
  -i, --interval   int        collection interval in seconds [default=1]
  -o, --options    options    misc formatting options, --showoptions for all
                                d|D - include date in output
                                  T - include time in output
                                  z - turn off compression of plot files
  -p, --playback   file       playback results from 'file' (be sure to quote
			      if wild carded) or the shell might mess it up
  -P, --plot                  generate output in 'plot' format
  -s, --subsys     subsys     specify one or more subsystems [default=cdn]
      --verbose               display output in verbose format (automatically
                              selected when brief doesn't make sense)

Various types of help
  -h, --help                  print this text
  -v, --version               print version
  -V, --showdefs              print operational defaults
  -x, --helpextend            extended help, more details descriptions too
  -X, --helpall               shows all help concatenated together

  --showoptions               show all the options
  --showsubsys                show all the subsystems
  --showsubopts               show all subsystem specific options
  --showtopopts               show --top options

  --showheader                show file header that 'would be' generated
  --showcolheaders            show column headers that 'would be' generated
  --showslabaliases           for SLUB allocator, show non-root aliases
  --showrootslabs             same as --showslabaliases but use 'root' names

$Copyright
$License
EOF
printText($help);
exit(0);
}

sub extendHelp
{
my $extended=<<EOF2;
This is the complete list of switches, more details in man page

      --align                   align on time boundary
      --all                     selects 'all' summary subsystems except slabs,
                                which means NO detail or process data either
			          note: the opposite of --all is -s-all
  -A, --address    addr[:port[:time]]      open a socket/port on addr with optional
                                timeout OR run as a server with no timeout
      --comment    string       add the string to the end of the header
  -C, --config     file         use alternate collectl.conf file
  -c, --count      count        collect this number of samples and exit
  -d, --debug      debug        see source for details or try -d1 to get started
  -D, --daemon                  run as a daemon
      --extract    file         extract a subset of a raw file into another one
  -f, --filename   file         name of directory/file to write to
  -F, --flush      seconds      number of seconds between output buffer flushes
      --from       time         time from which to playback data, -thru optional
                                   [yyyymmdd:]hh:mm[:ss][-[yyyymmdd:]hh:mm[:ss]]
      --grep       pattern      print timestamped entries in raw file for each
                                occurance of pattern
  -G, --group                   write process/slab data to separate, rawp file
  -h, --help                    print basic help
      --home                    move cursor to top before printing interval data
      --hr,--headerrepeat num   repeat headers every 'num' lines, once or never
      --import     file         name of file(s) to use for data importation
  -i, --interval   int[:pi:ei]] collection interval in seconds
                                  [defaults: interactive=1, daemon=10]
                                  pi is process interval [default=60]
                                  ei is environmental interval [default=300]
      --iosize                  include I/O sizes as appropriate in brief format
  -l, --limits     limits       override default exceptions name:val[-name:val]
  -m, --messages                write messages to log file and/or terminal
  -N, --nice                    give yourself a 'nicer' priority
      --nohup                   do not exit if the process that started collectl exits
      --offsettime secs         seconds by which to offset times during playback
  -o, --options                 misc formatting options, --showoptions for all
  -p, --playback   file         playback results from 'file'
      --passwd     file         use this instead if /etc/passwd for UID->name
      --pname      name         set process name to 'collectl-pname'
  -P, --plot                    generate output in 'plot' format
      --procanalyze             analyze process data, generating prcs file
      --quiet                   do note echo warning messages on the terminal
  -r, --rolllogs   time,d,m     roll logs at 'time', retaining for 'd' days, 
                                  every 'm' minutes [default: d=7,m=1440]
      --rawtoo                  when run with -P, this tell collectl to also
                                  create a raw log file as well
      --runas      uid[:gui]    collectl will change its uid/gid in daemon mode
                                  see man page for details
  -R, --runtime    duration     time to run in <number><units> format
                                  where unit is w,d,h,m,s
      --sep        separator    specify an alternate plot format separator
      --slabanalyze             analyze slab data, generating slbs file
      --stats                   same as -oA
  -s, --subsys     subsys       record/playback data from one or more subsystems
                                  --showsubsys for details
      --sumstat                 same as --stats but only summary
      --thru       time         time thru which to playback data (see --from)
      --top        [type][,num] show top 'num' processes sorted by type
                                  --showtopopts for details
      --tworaw                  synonym for -G and -group, which are now deprecated
      --umask      mask         set output file permissions mask (see man umask)
      --utime      mask         write diagnostic micro timestamps into raw file
      --verbose                 display output in verbose format (automatically
                                selected when brief doesn't make sense)
  -w, --wide                    print wide field contents (don't use K/M/G)

Synonyms
  --utc = -oU

These are Alternate Display Formats
  --vmstat                    show output similar to vmstat

Logging options
  --rawtoo                    used with -P, write raw data to a log as well
  --export name[,options]     write data to an exported socket/file

Various types of help
  -h, --help                  print this text
  -v, --version               print version
  -V, --showdefs              print operational defaults
  -x, --helpext               extended help
  -X, --helpall               shows all help concatenated together

  --showoptions               show all the options
  --showsubopts               show all substem specific options
  --showsubsys                show all the subsystems
  --showtopopts               show --top options

  --showheader                show file header that 'would be' generated
  --showcolheaders            show column headers that 'would be' generated
  --showslabaliases           for SLUB allocator, show non-root aliases
  --showrootslabs             same as --showslabaliases but use 'root' names
  --whatsnew                  show summary of recent version new features
EOF2
printText("$extended\n");
return    if defined($_[0]);

printText("$Copyright\n");
printText("$License\n");
exit(0);
}

sub showSubsys
{
  my $subsys=<<EOF3;
The following subsystems can be specified in any combinations with -s or 
--subsys in both record and playbackmode.  [default=$SubsysCore]

These generate summary, which is the total of ALL data for a particular type
  b - buddy info (memory fragmentation)
  c - cpu
  d - disk
  f - nfs
  i - inodes
  j - interrupts by CPU
  l - lustre
  m - memory
  n - network
  s - sockets
  t - tcp
  x - interconnect (currently supported: Infiniband and Quadrics)
  y - slabs
 
These generate detail data, typically but not limited to the device level

  C -  individual CPUs, including interrupts if -sj or -sJ
  D -  individual Disks
  E -  environmental (fan, power, temp) [requires ipmitool]
  F -  nfs data
  J -  interrupts by CPU by interrupt number
  L -  lustre
  M -  memory numa/node
  N -  individual Networks
  T -  tcp details (lots of data!)
  X -  interconnect ports/rails (Infiniband/Quadrics)
  Y -  slabs/slubs
  Z -  processes

An alternative format lets you add and/or subtract subsystems to the defaults by
immediately following -s with a + and/or -
  eg: -s+YZ-x adds slabs & processes and removes interconnet summary data
      -s-n removes network summary data
      -s-all removes ALL subsystems, something that can handy when playing back
             data collected with --import and you ONLY want to see that data
EOF3
printText($subsys);
exit(0)    if !defined($_[0]);
}

sub showOptions
{
  my $options=<<EOF4;
Various combinations can be specified with -o or --options, both interactively
and in playback mode, in far too many combinations to describe.  In general if
they make sense together they probably work!

Date and Time
  d - preface output with 'mm/dd hh:mm:ss'
  D - preface outout with 'ddmmyyyy hh:mm:ss'
  T - preface output with time only
  U - preface output with UTC time
  m - when reporting times, include milli-secs

Numerical Formats
  g - include/substitute 'g' for decimal point for numbers > 1G
  G - include decimal point (when it will fit) for numbers > 1G

Exception Reporting
  x - report exceptions only (see man page)
  X - record all values + exceptions in plot format (see manpage)
 
Modify results before display (do NOT effect collection)
  n - do NOT normalize rates to units/second

Plot File Naming/Creation
  a - if plotfile exists, append [default=skip -p file]
  c - always create new plot file
  u - create unique plot file names - include time

Plot Data Format
  1 - plot format with 1 decimal place of precision
  2 - plot format with 2 decimal places of precision
  z - don't compress output file(s)

File Header Information
  i - include file header in output
                                   
EOF4
printText($options);
exit(0)    if !defined($_[0]);
}

sub showSubopts
{
  my $subopts=<<EOF5;
These options are all subsystem specific and all take one or more arguments.
Options typically effect the type of data collectl and filters effect the way
it is displayed.  In the case of lustre there are also 'services'

CPU
  --cpuopts
      z - do not show any detail lines which are ALL 0     

Disk
  --dskfilt perl-regx[,perl-regx...]
      this ONLY applies to disk detail output and not data collection
      only data for disk names that match the pattern(s) will be displayed
      if you don't know perl, a partial string will usually work too
  --dskopts
      f - include fractions for some of the detail output columns
      i - include average i/o size in brief mode (as with --iosize)
      z - do not show any detail lines which are ALL 0     
  --rawdskfilt
      this works like dskfilt except rather than being applied to the
      output it applies to the data collection.
  --rawdskignore
      this is the opposite if --rawdskfilt in that any disks matching this
      pattern will not have their statistics recorded as well as not being
      shown in any output

Environmental
  --envopts [def=fpt]  NOTE: these do not filter data on collection
      f - display fan data
      p - display power data
      t - display temperature data
      C - display temperature in celcius
      F - display temperature in fahrenheit
      M - display data on multiple lines (useful when too much data)  
      T - display all env data truncated to whole integers
    0-9 - use as ipmi device number

  --envfilt perl-regx
      during collection, this filter is applied to the data returned by
      ipmitool and only those lines that match are kept

  --envremap perl-regx...
      a list of regx expressions, comma separated, are applied to the 
      final env names before reporting

  The following are for those needed to develop/debug remapping rules.
  See online documentation OR Ipmi.html in docs/
  --envrules  filename     file containin remapping rules
  --envdebug               show processing of ipmi data
  --envtest   filename     file containing extract of 'ipmitool -c sdr'

Lustre
  --lustopts
      B - only for OST's and clients, collect buffer/rpc stats
      D - collect lustre disk stats (HPSFS: MDS and OSS only)
      M - collect lustre client metadata
      O - collect lustre OST level stats (detail mode only and not MDS)
      R - collect lustre client readahead stats

  --lustsvc: force monitoring/reporting of these lustre services
      c - client
      m - mds
      o - oss
    NOTE - you can specify the service in either lower or upper case, in
    case other tools might care.  see the collectl documentation on lustre
    for details

Interconnect
  --xopts
      i - include i/o sizes in brief mode
      
Memory
  --memopts
      P - display physical portion of verbose display
      V - display virtual portion of verbose display
      p - display/record alloc/refill number of pages
      s - display/record steal/kswap/direct number of pages
      R - show changes in memory as rates, not instantaneous values

      note that including p or s will collect more data and will slightly increase in processing
      time.  if neither P or V are specified none of the basic memory stats will be displayed BUT
      they will be recorded making it possible to display later either by including P/V as an
      option OR leaving off both p and s.

Network
  --netfilt perl-regx[,perl-regx...]
      this ONLY applies to network detail output and not data collection
      only data for network interface names that match the pattern(s) 
      will be displayed
  --netopts eEw99
      e - include errors in brief mode and explicit error types in
          verbose and detail formats
      E - only display intervals which have network errors in them
      i - include i/o sizes in brief mode
      w - sets minimal network name width in network stats output which 
          can be useful for aligning output from multiple systems
  --rawnetfilt
      this works like netfilt except rather than being applied to the
      output it applies to the data collection.
  --rawnetignore
      this is the opposite of --rawnetfilt in that any networks matching this
      pattern will not have their statistics recorded as well as not being
      shown in any output

NFS
  --nfsfilt  TypeVer,...
      C - client
      S - server
      2 - V2
      3 - V3
      4 - V4
      By specifying a csv list, collectl will only collect/record the type
      of data indicated (eg c3,s3 indicates V3 clients/server data)
   --nfsopts
      z - do not show lines of 0 activity with -sF

Processes
   --procopts
      c - include cpu time of children who have exited (same as ps S switch)
      f - use cumulative totals for page faults in proc data instead of rates
      i - show io counters in display
      I - disable collection/display of I/O stats.  saves over 25% in data
          collection overhead
      m - show memory breakdown and faults in display
      p - never look for new pids or threads to match processing criteria
            This also improves performance!
      r - show root command name for a narrower display, can be combined with w
      R - show ALL process priorities ('RT' currently displayed if realtime)
      s - include process start times in hh:mm:ss format
      S - include process start times in mmmdd-hh:mm:ss format
      t - include ALL threads (can be a lot of overhead if many active threads)
      w - make format wider by including entire process argument string
          you can also set a max number of chars, eg w32
      x - include extended process attributes (currently only for context switches)
      z - exclude any processes with 0 in sort field

   --procfilt: restricts which procs are listed, where 'procs' is of the
      Format: <type><match>[[,<type><match>],...], and valid types are any
      combinations of:
      c - any substring in command name
      C - command name starts with this string
      f - full path of command (including args) contains string
      p - pid
      P - parent pid
      u - any processes owned by this user's UID or in range xxx-yyy
      U - any processes owned by this user

      NOTE1:  if 'procs' is actually a filename, that file will be read and all
              lines concatenated together, comma separted, as if typed in as an
              argument of --procfilt.  Lines beginning with # will be ignored
              as comments and blank lines will be skipped.
      NOTE2:  if any type fields are immediatly followed by a plus sign, any 
              threads associated with that process will also be reported.
              see man page for important restrictions

   --procstate  Only show processes in one or more of the following states
      D - waiting in uninterruptable disk sleep
      R - running
      S - sleeping in uninterruptable wait
      T - traced or stopped
      W - paging
      Z - zombie

Slab Options and Filters
   --slabopts
      s - only show slabs with non-zero allocations
      S - only show slabs that have changed since last interval

   --slabfilt: restricts which slabs are listed, where 'slab's is of the form: 
               'slab[,slab...].  only slabs whose names start with this name
               will be included

TCP Stack Options - these DO effect data collection as well as printing
   --tcpfilt
      i - ip stats, no brief stats so selecting it alone will force --verbose
      t - tcp stats
      u - udp stats
      c - Icmp Stats
      I - ip extended stats
      T - tcp extended stats
  
EOF5

printText($subopts);
exit(0)    if !defined($_[0]);
}

sub showTopopts
{
  my $subopts=<<EOF5;
The following is a list of --top's sort types which apply to either
process or slab data.  In some cases you may be allowed to sort
by a field that is not part of the display if you so desire

TOP PROCESS SORT FIELDS

Memory
  vsz    virtual memory
  rss    resident (physical) memory

Time
  syst   system time
  usrt   user time
  time   total time
  accum  accumulated time

I/O
  rkb    KB read
  wkb    KB written
  iokb   total I/O KB

  rkbc   KB read from pagecache
  wkbc   KB written to pagecache
  iokbc  total pagecacge I/O
  ioall  total I/O KB (iokb+iokbc)

  rsys   read system calls
  wsys   write system calls
  iosys  total system calls

  iocncl Cancelled write bytes

Page Faults
  majf   major page faults
  minf   minor page faults
  flt    total page faults

Context Switches
  vctx   volunary context switches
  nctx   non-voluntary context switches

Miscellaneous (best when used with --procfilt)
  cpu    cpu number
  pid    process pid
  thread total process threads (not counting main)

TOP SLAB SORT FIELDS

  numobj    total number of slab objects
  actobj    active slab objects
  objsize   sizes of slab objects
  numslab   number of slabs
  objslab   number of objects in a slab
  totsize   total memory sizes taken by slabs
  totchg    change in memory sizes
  totpct    percent change in memory sizes
  name      slab names

EOF5

printText($subopts);
exit(0)    if !defined($_[0]);
}

sub whatsnew
{
  my $whatsnew=<<EOF6;
What's new in collectl in the last year or so?

version 3.6.7  March 2013
- new switch: --cpuopts z, to disable detail lines for idle CPUs
- do NOT use vnet speeds, which are hardcoded to 10, in bogus checks
- a couple of new switches for graphite, e and r
- fixed a broken lexpr which wasn't handling intervals correctly which
  was broken in 3.6.5, sorry about that
- removed checks for disk minor/major numbers changing
- added additional disk detail counters to lexpr

version 3.6.5  October 2012
- bugfixes, see RELEASE-collectl for details
- officially declaring sexpr deprecated as it hasn't been updated in
  several years and I have no idea if it is being used by anyone
- -r option to purge .log files, def=12 months
- new lexpr option, align, will align output to whole minute boundary
- new graphite switch: f will report hostname field as FQDN

version 3.6.4  June 2012
- no longer need to be root to get network speed because ethtool no longer required
- support for dynamic disk/networks (vital for virtual host monitoring)
- merged experimental snmp stats with tcp stack stats and dropped snmp from the kit
- deprecated:   -G and -group will be removed in approximately 6 months.  use --tworaw
- new switch    --tcpfilt controls what is collected AND reported
- new switch:   --rawdskignore tells collectl to ignore specific disks during collection
- new switch:   --rawnetfilter tells collectl to ignore specific nets during collection
- new procopt:  s/S for showing process starting times
- new dskopt:   f reports fractional disk details
- new graphite switch: b=str will cause output to be prefaced by 'str'

version 3.6.3  May 2012
- new switch:   --rawdskfilt overrides DskFilter in collectl.conf
- new switch:   --rawnetfilt does for networks what DiskFilter does for disks
- fixed problem during process owner filtering

version 3.6.2  March 2012
- changed behavior of how to use --runas for non-root daemons

EOF6

  printText($whatsnew);
  exit(0);
}
