#!/usr/bin/env perl

use strict;
use warnings;

use lib ($ENV{EUK_MODULES});
use Fasta_reader;
use FindBin;


my $usage = "usage: $0 file.fasta\n\n";

my $fasta_file = $ARGV[0] or die $usage;

main: {

    my $sim_out_dir = "sim_data";
    unless (-d $sim_out_dir) {
        mkdir $sim_out_dir or die $!;
    }

    my $fasta_reader = new Fasta_reader($fasta_file);

    while (my $seq_obj = $fasta_reader->next()) {

        my $acc = $seq_obj->get_accession();
        my $sequence = $seq_obj->get_sequence();

        my $outdir = $acc;
        $outdir =~ s/\W/_/g;
        
        
        mkdir ("$sim_out_dir/$outdir") or die $!;
        
        my $template_file = "$sim_out_dir/$outdir/$outdir.template.fa";
        open (my $ofh, ">$template_file") or die "Error, cannot write to $template_file";
        print $ofh ">$acc\n$sequence\n";
        close $ofh;
        
        my $outfile = "$sim_out_dir/$outdir/$outdir.reads.fa";
        
        my $cmd = "$FindBin::Bin/../simulate_illuminaPE_from_transcripts.pl --transcripts $template_file --SS > $outfile";
        &process_cmd($cmd);

    }

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


