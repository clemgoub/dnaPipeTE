sub vmstatInit
{
  error("-s not allowed with 'vmstat'")          if $userSubsys ne '';
  error("-f requires either --rawtoo or -P")     if $filename ne '' && !$rawtooFlag && !$plotFlag;
  error("-P or --rawtoo require -f")             if $filename eq '' && ($rawtooFlag || $plotFlag);
  $subsys=$userSubsys='cm';
}

sub vmstat
{
  my $line;
  $sameColsFlag=1;
  if (printHeader())
  {
    $line= "${clscr}#${miniBlanks}procs ---------------memory (KB)--------------- --swaps-- -----io---- --system-- ----cpu-----\n";
    $line.="#$miniDateTime r  b   swpd   free   buff  cache  inact active   si   so    bi    bo   in    cs us sy  id wa\n";
    $headersPrinted=1;
  }

  $datetime='';
  if ($options=~/[dDTm]/)
  {
    ($ss, $mm, $hh, $mday, $mon, $year)=localtime($lastSecs[0]);
    $datetime=sprintf("%02d:%02d:%02d", $hh, $mm, $ss);
    $datetime=sprintf("%02d/%02d %s", $mon+1, $mday, $datetime)                   if $options=~/d/;
    $datetime=sprintf("%04d%02d%02d %s", $year+1900, $mon+1, $mday, $datetime)    if $options=~/D/;
    $datetime.=".$usecs"                                                          if ($options=~/m/);
    $datetime.=" ";
  }

  # currently only happens when called by colmux
  if ($showColFlag)
  {
    printText($line);
    return;
  }

  my $i=$NumCpus;
  my $usr=$userP[$i]+$niceP[$i];
  my $sys=$sysP[$i]+$irqP[$i]+$softP[$i]+$stealP[$i];
  $line.=sprintf("%s %2d %2d %6s %6s %6s %6s %6s %6s %4d %4d %5d %5d %4d %5d %2d %2d %3d %2d\n",
                $datetime, $procsRun, $procsBlock,
                cvt($swapUsed,6,1,1),  cvt($memFree,6,1,1),  cvt($memBuf,6,1,1),
                cvt($memCached,6,1,1), cvt($memInact,6,1,1), cvt($memAct,6,1,1),
                $swapin/$intSecs, $swapout/$intSecs, $pagein/$intSecs, $pageout/$intSecs,
                $intrpt/$intSecs, $ctxt/$intSecs,
                $usr, $sys, $idleP[$i], $waitP[$i]);

  printText($line);
}
1;
