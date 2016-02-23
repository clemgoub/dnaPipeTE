#!/usr/bin/env perl

use strict;
use warnings;

my $usage = "\n\nusage: $0 transcripts.fpkm\n\n";

my $transcript_fpkm = $ARGV[0] or die $usage;

main: {

    open (my $fh, $transcript_fpkm) or die "Error, cannot open file $transcript_fpkm";
    my $header = <$fh>;

    $header =~ /Total fragments mapped to \S+: (\d+)/ or die "Error, cannot parse total reads mapped from header: $header";
    my $total_reads_mapped = $1 or die "Error, cannot determine total num reads mapped";
    
    my $col_header = <$fh>;
    
    # retain header info
    $header =~ s/^transcript/gene/;
    print $header;
    print $col_header;

    

    my %gene_to_trans_info;
    
    while (<$fh>) {
        unless (/\w/) { next; }
        chomp;
        my @x = split(/\t/);
        my ($acc, $len, $eff_len, $count, $fraction, $fpkm, $percent_component_fpkm) = @x;

        my ($gene, $trans) = split(/::/, $acc);
       
        unless ($gene && $trans) {
            die "Error, cannot decipher gene :: trans from $acc, line: $_";
        }
        
        push (@{$gene_to_trans_info{$gene}}, { count => $count,
                                               length => $len,
                                               eff_len => $eff_len,
                                               fpkm => $fpkm,
              } );
        
    }
    close $fh;

    
    ## compute gene fpkm using a trans-fpkm-weighted length value.
    
    foreach my $gene (sort keys %gene_to_trans_info) {
        
        my @trans_info = @{$gene_to_trans_info{$gene}};
        
        my $sum_weighted_eff_length = 0;
        my $sum_weighted_length = 0;
        my $sum_length = 0;
        my $sum_eff_length = 0;
        my $sum_frags = 0;
        my $sum_fpkm = 0;
        
        foreach my $trans (@trans_info) {
            my $len = $trans->{length};
            my $fpkm = $trans->{fpkm};
            
            $sum_length += $len;
            $sum_weighted_length += $len * $fpkm;
            
            $sum_fpkm += $fpkm;
            
            my $eff_len = $trans->{eff_len};
            
            $sum_eff_length += $eff_len;
            $sum_weighted_eff_length += $eff_len * $fpkm;

            my $frags = $trans->{count};
            if ($frags ne "NA") {
                $sum_frags += $frags;
            }
        }
        
                
        my $weighted_length = ($sum_fpkm) ? ($sum_weighted_length / $sum_fpkm) : ($sum_length / scalar(@trans_info));
        
        $weighted_length = sprintf("%.1f", $weighted_length);
        
        my $weighted_eff_length = ($sum_fpkm) ? ($sum_weighted_eff_length / $sum_fpkm) : ($sum_eff_length / scalar(@trans_info));
        
        $weighted_eff_length = sprintf("%.1f", $weighted_eff_length);

        my $gene_fpkm = sprintf("%.2f", $sum_frags / ($weighted_length / 1e3) / ($total_reads_mapped / 1e6) );
        my $fraction = sprintf("%.2e", $sum_frags / $total_reads_mapped);
        

        print join("\t", $gene, $weighted_length, $weighted_eff_length, $sum_frags, $fraction, $gene_fpkm, 100) . "\n";
    }
    

    exit(0);
}
                         
