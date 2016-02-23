#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib ("$FindBin::Bin/../PerlLib");
use Fasta_reader;
use Nuc_translator;
use Getopt::Long qw(:config no_ignore_case bundling pass_through);

my $usage = <<__EOUSAGE__;

##################################################################
#
# Required:
#
#  --transcripts <string>       file containing target transcripts in fasta format
#
# Optional:
#
#  --read_length <int>          default: 76
#
#  --spacing <int>              default: 1  (simulate read from every (spacing) position)
#
#  --pair_gap <int>             default: 150
# 
#  --SS                         strand-specific flag
#
#################################################################

__EOUSAGE__

    ;


my $transcripts;
my $read_length = 76;
my $spacing = 1;
my $pair_gap = 150;
my $help_flag;
my $SS = 0;

&GetOptions ( 'h' => \$help_flag,
              'transcripts=s' => \$transcripts,
              'read_length=i' => \$read_length,
              'spacing=i' => \$spacing,
              'pair_gap=i' => \$pair_gap,
              'SS' => \$SS,
              );

if ($help_flag) {
    die $usage;
}

unless ($transcripts) { 
    die $usage;
}


main: {

    my $fasta_reader = new Fasta_reader($transcripts);
    print STDERR "-parsing incoming $transcripts...";
    my %read_seqs = $fasta_reader->retrieve_all_seqs_hash();
    print STDERR "done.\n";
    
    my $num_trans = scalar (keys %read_seqs);
    my $counter = 0;
    
    foreach my $read_acc (keys %read_seqs) {
        $counter++;
        print STDERR "\r[" . sprintf("%.2f%%  = $counter/$num_trans]     ", $counter/$num_trans*100);
        
        my $seq = $read_seqs{$read_acc};

        
        ## uniform dist
        for (my $i = 0; $i <= length($seq); $i+=$spacing) {
                        
            my $left_read_seq = "";
            my $right_read_seq = "";
            my $ill_acc = $read_acc . "_Ap$i";
            
            my $left_start = $i - $read_length - $pair_gap;
            if ($left_start >= 0) {
                $left_read_seq = substr($seq, $left_start, $read_length);
            }
                        
            my $right_start = $i;
            if ($right_start + $read_length  <= length($seq)) {
                $right_read_seq = substr($seq, $right_start, $read_length);
            }
            

            if ($left_read_seq) {
                print ">$ill_acc/1\n"
                    . "$left_read_seq\n";    
            }
            if ($right_read_seq) {
                unless ($SS) {
                    $right_read_seq = &reverse_complement($right_read_seq);
                }
                print ">$ill_acc/2\n"
                    . "$right_read_seq\n";
            }
        }
        

        ## volcano spread
        for (my $i = 0; $i <= length($seq)/2; $i+=$spacing) {
                        
            my $left_read_seq = "";
            my $right_read_seq = "";
            my $ill_acc = $read_acc . "_Bp$i";
            

            my $left_start = $i;
            if ($left_start >= 0) {
                $left_read_seq = substr($seq, $left_start, $read_length);
            }

            my $right_start = length($seq)-$read_length -$i + 1;
            
            if ($left_start + $read_length >= $right_start) { next; } ## don't overlap them.

            if ($right_start + $read_length  <= length($seq)) {
                $right_read_seq = substr($seq, $right_start, $read_length);
            }
            

            if ($left_read_seq) {
                print ">$ill_acc/1\n"
                    . "$left_read_seq\n";    
            }
            if ($right_read_seq) {
                unless ($SS) {
                    $right_read_seq = &reverse_complement($right_read_seq);
                }
                print ">$ill_acc/2\n"
                    . "$right_read_seq\n";
            }
        }

    }
    

    print STDERR "\nDone.\n";
    
    exit(0);
}


####
sub process_cmd {
    my ($cmd) = @_;

    print STDERR "CMD: $cmd\n";

    my $ret = system($cmd);

    if ($ret) {
        die "Error, cmd: $cmd died with ret $ret";
    }

    return;
}


####
sub capture_kmer_cov_text {
    my ($kmer_cov_file) = @_;
        
    my %kmer_cov;
    
    my $acc = "";
    open (my $fh, $kmer_cov_file) or die "Error, cannt open file $kmer_cov_file";
    while (<$fh>) {
        chomp;
        if (/>(\S+)/) {
            $acc = $1;
        }
        else {
            $kmer_cov{$acc} .= " $_";
        }
    }
    close $fh;

    return(%kmer_cov);
}


####
sub avg {
    my (@vals) = @_;

    if (scalar(@vals) == 1) {
        return($vals[0]);
    }
    

    my $sum = 0;
    foreach my $val (@vals) {
        $sum += $val;
    }
    
    my $avg = $sum / scalar(@vals);


    return(int($avg+0.5));
}

