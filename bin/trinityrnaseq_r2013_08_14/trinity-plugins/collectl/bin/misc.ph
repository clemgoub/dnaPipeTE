# copyright, 2003-2009 Hewlett-Packard Development Company, LP

# NOTE - by default, this module only collectl data once a minute, which you can change
# with the i=x parameter (eg --import misc,i=x).  Regardless of the collection interval,
# date will be reported every interval in brief/verbose formats to provide a consisent 
# set of output each monitoring cycle.  However, --export lexpr will report light-weight
# counters every interval but heavy-weight ones (currenly only logins) based in i=.  
# sexpr and gexpr will report all 4 counters every interval independent of when sampled.
# To report --export data in ALL lexpr samples, in case the listener expects it, include 
# the a switch (eg misc,a).

#    M i s c e l l a n e u o s    C o u n t e r

use strict;

# Allow reference to collectl variables, but be CAREFUL as these should be treated as readonly
our ($miniFiller, $rate, $SEP, $datetime, $miniInstances, $interval, $showColFlag);

my (%miscNotOpened, $miscUptime, $miscMHz, $miscMounts, $miscLogins);
my ($miscUptimeTOT, $miscMHzTOT, $miscMountsTOT, $miscLoginsTOT);
my ($miscInterval, $miscImportCount, $miscSampleCounter, $miscAllFlag);
sub miscInit
{
  my $impOptsref=shift;
  my $impKeyref= shift;

  # If we ever run with a ':' in the inteval, we need to be sure we're
  # only looking at the main one.  NOTE - if --showcolflag, collectl
  # sets $interval to 0 and we need to make sure out division doesn't bomb
  my $miscInterval1=(split(/:/, $interval))[0];
  $miscInterval1=1    if $showColFlag;

  # For now, only options are a, 'i=' and s
  $miscInterval=60;
  $miscAllFlag=0;
  if (defined($$impOptsref))
  {
    foreach my $option (split(/,/,$$impOptsref))
    {
      my ($name, $value)=split(/=/, $option);
      error("invalid misc option: '$name'")    if $name ne 'a' && $name ne 'i' && $name ne 's';

      $miscInterval=$value    if $name eq 'i';
      $miscAllFlag=1          if $name eq 'a';
    }
  }

  $miscImportCount=int($miscInterval/$miscInterval1);
  error("misc interval option not a multiple of '$miscInterval1' seconds")
        if $miscInterval1*$miscImportCount != $miscInterval;

  $$impOptsref='s';    # only one collectl cares about
  $$impKeyref='misc';

  $miscSampleCounter=-1;
  $miscLogins=0;
  return(1);
}

# Nothing to add to header
sub miscUpdateHeader
{
}

sub miscGetData
{
  getProc(0, '/proc/uptime', 'misc-uptime');
  grepData(1, '/proc/cpuinfo', 'MHz', 'misc-mhz');
  grepData(2, '/proc/mounts', ' nfs ', 'misc-mounts');

  # we only retrieve heavy-weight counters at the misc sampling interval
  # as specified by "i=" or the default value of 60.
  return    if ($miscSampleCounter++ % $miscImportCount)!=0;

  getExec(4, '/usr/bin/who -s -u', 'misc-logins');
}

sub miscInitInterval
{
}

sub miscAnalyze
{
  my $type=   shift;
  my $dataref=shift;

  $type=~/^misc-(.*)/;
  $type=$1;
  my @fields=split(/\s+/, $$dataref);

  if ($type eq 'uptime')
  {
    $miscUptime=$fields[0];
  }
  elsif ($type eq 'mhz')
  {
    $miscMHz=$fields[3];
  }
  elsif ($type eq 'mounts')
  {
    $miscMounts=$fields[0];
  }
  elsif ($type eq 'logins:')  # getExec adds on the ':'
  {
    $miscLogins=$fields[0];
  }
}

sub miscPrintBrief
{
  my $type=shift;
  my $lineref=shift;

  if ($type==1)       # header line 1
  {
    $$lineref.="<------Misc------>";
  }
  elsif ($type==2)    # header line 2
  {
    $$lineref.=" UTim  MHz MT Log ";
  }
  elsif ($type==3)    # data
  {
    $$lineref.=sprintf(" %4s %4d %2d %3d ", 
	cvt($miscUptime/86400), $miscMHz, $miscMounts, $miscLogins);
  }
  elsif ($type==4)    # reset 'total' counters
  {
    $miscUptimeTOT=$miscMHzTOT=$miscMountsTOT=$miscLoginsTOT=0;
  }
  elsif ($type==5)    # increment 'total' counters
  {
    $miscUptimeTOT+=   int($miscUptime/86400+.5);    # otherwise we get round off error
    $miscMHzTOT+=      $miscMHz;
    $miscMountsTOT+=   $miscMounts;
    $miscLoginsTOT+=   $miscLogins;
  }
  elsif ($type==6)    # print 'total' counters
  {
    printf " %4d %4d %2d %3d ", $miscUptimeTOT/$miniInstances, $miscMHzTOT/$miniInstances,
	                        $miscMountsTOT/$miniInstances, $miscLoginsTOT/$miniInstances;
  }
}

sub miscPrintVerbose
{
  my $printHeader=shift;
  my $homeFlag=   shift;
  my $lineref=    shift;

  my $line='';
  if ($printHeader)
  {
    $line.="\n"    if !$homeFlag;
    $line.="# MISC STATISTICS\n";
    $line.="#$miniFiller UpTime  CPU-MHz Mounts Logins\n";
  }
  $$lineref.=$line;
  return    if $showColFlag;

  $$lineref.=sprintf("$datetime  %6s   %6d %6d %6d \n", 
	cvt($miscUptime/86400), $miscMHz, $miscMounts, $miscLogins);
}

sub miscPrintPlot
{
  my $type=   shift;
  my $ref1=   shift;

  # Headers - note we end with $SEP but that's ok because writeData() removes it
  $$ref1.="[MISC]Uptime${SEP}[MISC]MHz${SEP}[MISC]Mounts${SEP}[MISC]Logins${SEP}"
			if $type==1;

  # Summary Data Only - and here we start with $SEP
  $$ref1.=sprintf("$SEP%d$SEP%d$SEP%d$SEP%d",
		$miscUptime/86400, $miscMHz, $miscMounts, $miscLogins)
			if $type==3;
}

sub miscPrintExport
{
  my $type=   shift;
  my $ref1=   shift;
  my $ref2=   shift;
  my $ref3=   shift;

  # The light-weight counters are reported every sampling interval but since I think sexpr
  # needs to be contant, we'll always report all even if some only sampled periodically.
  # Same thing for gexpr, at least for now.
  if ($type eq 'l')
  {
     push @$ref1, "misc.uptime";   push @$ref2, sprintf("%d", $miscUptime/86400);
     push @$ref1, "misc.cpuMHz";   push @$ref2, sprintf("%d", $miscMHz);
     push @$ref1, "misc.mounts";   push @$ref2, sprintf("%d", $miscMounts);
  }
  elsif ($type eq 's')
  {
    $$ref1.=sprintf("  (misctotals (uptime %d) (cpuMHz %d) (mounts %d) (logins %d))\n",
	$miscUptime/86400, $miscMHz, $miscMounts, $miscLogins);
  }
  elsif ($type eq 'g')
  {
     push @$ref2, 'num', 'num', 'num', 'num', 'num';
     push @$ref1, "misc.uptime";   push @$ref3, sprintf("%d", $miscUptime/86400);
     push @$ref1, "misc.cpuMHz";   push @$ref3, sprintf("%d", $miscMHz);
     push @$ref1, "misc.mounts";   push @$ref3, sprintf("%d", $miscMounts);
     push @$ref1, "misc.logins";   push @$ref3, sprintf("%d", $miscLogins);
  }

  # Heavy-weight lexpr counters are only returned based on "i=" or default of 60 seconds
  return    if !$miscAllFlag && (($miscSampleCounter-1) % $miscImportCount)!=0;

  if ($type eq 'l')
  {
     push @$ref1, "misc.logins";   push @$ref2, sprintf("%d", $miscLogins);
  }
}

# Type 1: return contents of first match
# Type 2: return count of all matches
sub grepData
{
  my $type=  shift;
  my $proc=  shift;
  my $string=shift;
  my $tag=   shift;

  # From getProc()
  if (!open PROC, "<$proc")
  {
    # but just report it once, but not foe nfs or proc data
    logmsg("W", "Couldn't open '$proc'")    if !defined($miscNotOpened{$proc});
    $miscNotOpened{$proc}=1;
    return(0);
  }

  my $count=0;
  foreach my $line (<PROC>)
  {
    next    if $line!~/$string/;

    if ($type==1)
    {
      record(2, "$tag $line");
      return;
    }

    $count++;
  }
  record(2, "$tag $count\n");
}

1;
