#!/usr/bin/env perl

use strict;
use warnings;

my $usage = "usage: $0 pairs.stats.sorted max_cov max_pct_stdev\n\n";

my $pair_stats_file = $ARGV[0] or die $usage;
my $max_cov = $ARGV[1] or die $usage;
my $max_pct_stdev = $ARGV[2] or die $usage;

main: {

    ## First pass, get counts for each coverage level
    my %coverage_counter;

    open (my $fh, $pair_stats_file) or die $!;
    open (my $ofh, ">$pair_stats_file.lte_stdev") or die $!;
    while (<$fh>) {
        my $line = $_;
        chomp;
        my ($cov, $pct_dev, $core_acc, $read_1, $read_2) = split(/\t/);
        if ($pct_dev > $max_pct_stdev) {
            next;
        }
        $coverage_counter{$cov}++;
        print $ofh $line;
    }
    close $fh;
    close $ofh;


    ## Second pass, select reads prioritized by quality
    open ($fh, "$pair_stats_file.lte_stdev") or die $!;
    while (<$fh>) {
        my $line = $_;
        chomp;
        my ($log2_cov, $pct_dev, $core_acc, $read_1, $read_2) = split(/\t/);
        my $count = $coverage_counter{$log2_cov};
        
        ## deterimine how many to print
        my $num_reads_to_report = &estimate_selection($log2_cov, $max_cov, $count);
        if ($num_reads_to_report >= 1) {
            print $line;
        }
        $count--;
        $num_reads_to_report--;
        while ($count > 0) {
            my $line = <$fh>;
            if ($num_reads_to_report > 0) {
                print $line;
                $num_reads_to_report--;
            }
            $count--;
        }
    }
    close $fh;
    

    exit(0);
    
}


####
sub estimate_selection {
    my ($log2_cov, $max_cov, $count) = @_;

    my $cov = 2 ** $log2_cov;;
    
    if ($cov < 1) { # don't think this should happen
        return(0);
    }
    
    my $num_selected = 0;
    
    for (1..$count) {
        
        if (rand(1) <= $max_cov/$cov) {
            $num_selected++;
        }
    }

    return($num_selected);
}
