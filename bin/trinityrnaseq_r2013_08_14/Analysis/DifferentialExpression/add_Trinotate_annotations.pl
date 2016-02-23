#!/usr/bin/env perl

use strict;
use warnings;

my $usage = "\n\nusage: $0 Trinotate.xls tab_output acc_column\n\nNOTE: acc_column where numbering starts at 1\n\n";

my $trinotate_xls = $ARGV[0] or die $usage;
my $tab_output = $ARGV[1] or die $usage;
my $column_no = $ARGV[2] or die $usage;

unless ($column_no > 0 && $column_no < 100) {
    die $usage;
}

main: {

    my %annots = &parse_annotations($trinotate_xls);
    
    open (my $fh, $tab_output) or die "Error, cannot open file $tab_output";
    my $header = <$fh>;
    print $header;

    while (<$fh>) {
        chomp;
        my $line = $_;
        my @x = split(/\t/);
        my $acc = $x[$column_no-1] or die "Error, cannot identify accession from $line at column $column_no";
        my $annot = $annots{$acc} || "";
        
        if ($annot) {
            my @annots = split(/\t/, $annot);
            my $blast_hit = $annots[2];
            unless ($blast_hit) { 
                die "Error, no blast hit extracted from $annot";
            }
            $blast_hit =~ s/^.*RecName: Full=//;
            my $name = substr($blast_hit, 0, 40);
            $acc = "$acc|$name";
            $acc =~ s/ /_/g;
            $x[0] = $acc;
        }
        print join("\t", @x) . "\n";
        #print "$line\t$annot\n";
    }
    
    exit(0);
    
    
    
    
}

####
sub parse_annotations {
    my ($xls_file) = @_;

    my %annotations;

    open (my $fh, $xls_file) or die $!;
    while (<$fh>) {
        chomp;
        my $line = $_;
        my @x = split(/\t/);
        my $acc_info = $x[1];
        my ($trin_acc, $rest) = split(/:/, $acc_info);
        $annotations{$trin_acc} = $line;

        if ($trin_acc =~ /^(comp\d+_c\d+)/) {
            my $component = $1;
            if (exists $annotations{$component}) {
                $line = "\t$line";
            }
            $annotations{$component} .= $line;
        }
    }
    close $fh;

    return(%annotations);
}
