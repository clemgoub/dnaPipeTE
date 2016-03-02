#!/usr/bin/env perl

use strict;
use warnings;

my $usage = "usage: $0 pairs.stats.sorted max_cov max_pct_stdev\n\n";

my $pair_stats_file = $ARGV[0] or die $usage;
my $max_cov = $ARGV[1] or die $usage;
my $max_pct_stdev = $ARGV[2] or die $usage;

main: {

    open (my $fh, $pair_stats_file) or die $!;
    while (<$fh>) {
        chomp;
        my $line = $_;
        my ($med_cov, $avg_cov, $stdev, $pct_dev, $core_acc) = split(/\t/);
        
        $core_acc =~ s|/[12]$||;
        
        if ($med_cov < 1) { next; }
        
        if ($pct_dev > $max_pct_stdev) { next; }
                                
        if (rand(1) <= $max_cov/$med_cov) {
            print "$core_acc\n";
        }
    }
    close $fh;
    

    exit(0);
}
