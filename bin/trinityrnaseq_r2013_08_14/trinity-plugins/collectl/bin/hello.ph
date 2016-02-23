# copyright, 2003-2009 Hewlett-Packard Development Company, LP

#    H e l l o    W o r l d

# Though not required, it is especially useful to use strict to force all variable to be
# declare and minimize the risk of stepping on any that collectl itself uses
use strict;

# Allow reference to collectl variables, but be CAREFUL as these should be treated as readonly
our ($miniFiller, $rate, $SEP, $datetime, $intSecs, $showColFlag);

# Global to this module
my $counter=0;
my ($hwOpts, $hwTot, @hwNow, $hwTotTOT);

# support for 's','d', and 'sd, assuming 's' is the default.  Since collectl doesn't
# restrict which options are valid, we must to it ourself and call errror() accordingly
# For an additional example of error handling, if this module required CPU data to be 
# collected as well, you could incldue an error message based on the condition $subsys!~/c/i;
sub helloInit
{
  my $impOptsref=shift;
  my $impKeyref= shift;

  $hwOpts=$$impOptsref;
  error('valid hw options are: s,d and sd')    if defined($hwOpts) && $hwOpts!~/^[sd]*$/;
  $hwOpts='s'     if !defined($hwOpts);

  $$impOptsref=$hwOpts;
  $$impKeyref='hw';
  return(1);
}

# Anything you might want to add to collectl's header.  
# Try the command 'collectl --import hello --showheader'
sub helloUpdateHeader
{
  my $lineref=shift;

  $$lineref.="# HelloWorld: Version 1.0\n";
}

# Simulate 3 lines of data being read from /proc and include a further qualifier to act
# as a device number.  See how this is used in Analyze().
sub helloGetData
{
  for (my $i=0; $i<3; $i++)
  {
    my $string=sprintf("HelloWorld %d\n", $i*10*$counter++);
    record(2, "hw-$i $string");
  }
}

# Reset running total for the 3 'devices' for the current interval, which will be
# diplayed in both brief and summary formats.
sub helloInitInterval
{
  $hwTot=0;
}

# We could get fancier and look at how much each counter changed between intervals by
# subtracting the last value from the current one, but we're only going to look at
# explict values to keep things simple.
sub helloAnalyze
{
  my $type=   shift;
  my $dataref=shift;

  $type=~/^hw-(.*)/;
  my $index=$1;
  my @fields=split(/\s+/, $$dataref);
  $hwNow[$index]=$fields[1];
  $hwTot+=$fields[1];
}

# This and the 'print' routines should be self explanitory as they pretty much simply
# return a string in the appropriate format for collectl to dispose of.
sub helloPrintBrief
{
  my $type=shift;
  my $lineref=shift;

  if ($type==1)       # header line 1
  {
    $$lineref.="<-Hello->";
  }
  elsif ($type==2)    # header line 2
  {
    $$lineref.="  Total  ";
  }
  elsif ($type==3)    # data
  {
    $$lineref.=sprintf("   %4s   ", cvt($hwTot/$intSecs));
  }
  elsif ($type==4)    # reset 'total' counters
  {
    $hwTotTOT=0;
  }
  elsif ($type==5)    # increment 'total' counters
  {
    $hwTotTOT+=$hwTot;
  }
  elsif ($type==6)    # print 'total' counters
  {
    # Since this never goes over a socket we can just do a simple print.
    printf "   %4s   ", cvt($hwTotTOT);
  }
}

# The only magic here is knowing when to print a headers.  Note the use of $rate which
# you can see change with you use -on.  Since all -on does is set $intSecs to 1, there's
# no custom coding required.  Also note how $datetime and $miniFiller are used together to
# allow the actual timestamps to align with the header correctly.
sub helloPrintVerbose
{
  my $printHeader=shift;
  my $homeFlag=   shift;
  my $lineref=    shift;

  # Note that last line of verbose data (if any) still sitting in $$lineref
  my $line=$$lineref='';
  if ($hwOpts=~/s/)
  {
    if ($printHeader)
    {
      $line.="\n"    if !$homeFlag;
      $line.="# HELLO STATISTICS ($rate)\n";
      $line.="#$miniFiller   Total\n";
    }
    $$lineref.=$line;
    return    if $showColFlag;

    $$lineref.=sprintf("$datetime  %7s\n", cvt($hwTot/$intSecs,7));
  }

  $line='';
  if ($hwOpts=~/d/)
  {
    if ($printHeader)
    {
      $line.="\n"    if !$homeFlag;
      $line.="# HELLO DETAIL ($rate)\n";
      $line.="#$miniFiller HW    Value\n";
    }
    $$lineref.=$line;
    return    if $showColFlag;

    $line='';
    for (my $i=0; $i<3; $i++)
    {
      $line.=sprintf("$datetime  %2d  %7s\n", $i, cvt($hwNow[$i],7));
    }
  }
  $$lineref.=$line;
}

# Just be sure to use $SEP in the right places.  A simple trick to make sure you've done it
# correctly is to generste a small plot file and load it into a speadsheet, making sure each
# column of data has a header and that they aling 1:1.
sub helloPrintPlot
{
  my $type=   shift;
  my $ref1=   shift;

  #    H e a d e r s

  # Summary
  if ($type==1 && $hwOpts=~/s/)
  {
    $$ref1.="[HW]Tot${SEP}";
  }

  # Detail - these typically have :devname inside the []s
  if ($type==2 && $hwOpts=~/d/)
  {
    for (my $i=0; $i<3; $i++)
    {
      $$ref1.="[HW:$i]Val$SEP";
    }
  }

  #    D a t a

  # Summary
  if ($type==3 && $hwOpts=~/s/)
  {
    $$ref1.=sprintf("$SEP%d",
	int($hwTot/$intSecs));
  }

  # Detail
  if ($type==4 && $hwOpts=~/d/)
  {
    for (my $i=0; $i<3; $i++)
    {
      $$ref1.=sprintf("$SEP%d$SEP%d", $i, int($hwNow[$i]/$intSecs));
    }
  }
}

sub helloPrintExport
{
  my $type=shift;
  my $ref1=shift;
  my $ref2=shift;
  my $ref3=shift;
  my $ref4=shift;
  my $ref5=shift;
  my $ref6=shift;

  if ($hwOpts=~/s/)
  {
    if ($type eq 'l')
    {
      push @$ref1, "hwtotals.val";
      push @$ref2, int($hwTot/$intSecs);
      push @$ref5, 1;    # makes it a gauge and so an avg for 'tot'
    }
    elsif ($type eq 's')
    {
      $$ref1.=sprintf("  (hwtotals (hw %d))\n", int($hwTot/$intSecs));
    }
    elsif ($type eq 'g')
    {
      push @$ref1, "hwtotals.hw";
      push @$ref2, 'num/sec';
      push @$ref3, int($hwTot/$intSecs);
     }
  }

  if ($hwOpts=~/d/)
  {
    if ($type=~/[gl]/)
    {
      for (my $i=0; $i<3; $i++)
      {
        if ($type eq 'l')
        {
          push @$ref3, "hwinfo.hw$i.val";
          push @$ref4, int($hwNow[$i]/$intSecs);
        }
        else
        {
          push @$ref1, "hwinfo.hw$i.val";
          push @$ref2, 'num/sec';
          push @$ref3, int($hwNow[$i]/$intSecs);
        }
      }
    }
    elsif ($type eq 's')
    {
      $$ref2.="  (hwinfo\n";
      $$ref2.="    (name 0 1 2))\n";
      $$ref2.="    (hw0 $hwNow[0])\n";
      $$ref2.="    (hw0 $hwNow[1])\n";
      $$ref2.="    (hw0 $hwNow[2]))\n";
    }
  }
}

1;
