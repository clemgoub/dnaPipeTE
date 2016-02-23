#!/usr/bin/perl -w

# Copyright 2003-2009 Hewlett-Packard Development Company, L.P.

# Revision history (some of)
#1.2.0 Convert alphabetic fields to 0s, which at this point are only for DSK and NET

use Config;
use Getopt::Std;
use File::Basename;
use strict;

my $Version="1.2.0";
my $Copyright='Copyright 2003-2008 Hewlett-Packard Development Company, L.P.';

my $pcFlag=($Config{"osname"}=~/MSWin32/) ? 1 : 0;
my $SEP=($pcFlag) ? '\\' : '/';

our ($opt_h, $opt_i, $opt_o, $opt_v);
my  ($inspec, $outdir);
getopts('hi:o:v');
$inspec=$opt_i    if defined($opt_i);
$outdir=$opt_o    if defined($opt_o);

if (defined($opt_v))
{
  print "col2tlviz V$Version\n";
  print "$Copyright\n";
  exit;
}

if (defined($opt_h) || !defined($inspec))
{
  print "usage: col2tlv.pl -i filespec [-o dirname] [-v]\n";
  print "$Copyright\n";
  exit;
}

error("output directory doesn't exist")    if defined($outdir) && !-e $outdir;

my @files;
my $glob=$inspec;
my $skipped=0;
@files=glob($glob);
foreach my $file (@files)
{
  if ($file!~/tab$|cpu$|dsk$|net$|nfs$/)
  {
    $skipped++;
    next;
  }

  open IN, "<$file" or error("Couldn't open '$file'");

  my $outfile="$file.csv";
  $outfile="$outdir$SEP".basename($outfile)    if defined($outdir);
  open OUT, ">$outfile" or error("Couldn't create '$outfile'");
  print "Creating: $outfile\n";

  my $state=0;
  my $header='';
  while (my $line=<IN>)
  {
    if ($line=~/^#Date/)
    {
      cvtHeader(\$header);

      $state=1;
      $line=~s/ /,/g;
      $line=~s/#Date,Time(.*),?$/Sample Time$1/;  # also get rid of optional trailing comma!
      print OUT $line;
      next;
    }

    if ($state==0)
    {
      $header.=$line;
      next;
    }

    my ($date, $time, $therest)=split(/ /, $line, 3);
    my $year=substr($date, 0, 4);
    my $mon= substr($date, 4, 2);
    my $day=substr($date, 6, 2);

    my $month=substr('JanFebMarAprMayJunJulAugSepOctNovDec', ($mon-1)*3, 3);
    my $newdate="$day-$month-$year";

    $therest=~s/ /,/g;
    $therest=~s/[a-z].*?,/0,/g;    # for DSK and NET files, this will convert instance names to 0's
    print OUT "$newdate $time,$therest";
  }
}
print "skipped $skipped file(s) that did not extension(s): tab,cpu,dsk,net,nfs\n"    if $skipped;

sub cvtHeader
{
  my $hdrref=shift;

  $$hdrref=~s/##.*//g;
  $$hdrref=~s/#\s+(.*)/"$1",/g;
  $$hdrref=~s/[\n\r]+//g;
  $$hdrref=~s/,$//;
  $$hdrref=~/Host:\s+(\S+)/;
  $$hdrref="$1,$$hdrref\n";
  print OUT $$hdrref;
}

sub error
{
  print "$_[0]\n";
  exit;
}
