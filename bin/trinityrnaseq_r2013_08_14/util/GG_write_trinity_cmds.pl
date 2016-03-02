#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use Getopt::Long qw(:config no_ignore_case bundling pass_through);

my $usage = <<__EOUSAGE__;

####################################################################################
#
# Required:
#
# --reads_list_file <string>      file containing list of filenames corresponding 
#                                  to the reads.fasta
#
# Optional:
#
# --paired                        reads are paired (default: not paired)
#
# --SS                            strand-specific  (reads are already oriented
#
# --jaccard_clip                  run jaccard clip
#
# --bfly_opts <string>            options to pass on to butterfly
#
#####################################################################################


__EOUSAGE__

    ;


my $reads_file;
my $paired_flag = 0;
my $SS_flag = 0;
my $jaccard_clip = 0;

my $bfly_opts;
my $help_flag;

&GetOptions (
             'reads_list_file=s' => \$reads_file,
             'paired' => \$paired_flag,
             'SS' => \$SS_flag,
             'jaccard_clip' => \$jaccard_clip,
             'bfly_opts=s' => \$bfly_opts,
             
             'h' => \$help_flag,
             
             );


if ($help_flag) {
    die $usage;
}

unless ($reads_file && -s $reads_file) {
    die $usage;
}


open (my $fh, $reads_file) or die "Error, cannot open file $reads_file";
while (<$fh>) {
	my $file = $_;
	chomp $file;
    
    my $cmd = "$FindBin::Bin/../Trinity.pl --seqType fa --single \"$file\" --JM 2G --CPU 4 --output \"$file.out\" --genome_guided ";
    
    if ($paired_flag) {
        $cmd .= " --run_as_paired ";
    }
    if ($SS_flag) {
        $cmd .= " --SS_lib_type F ";
    }

    if ($jaccard_clip) {
        $cmd .= " --jaccard_clip ";
    }
    
    if ($bfly_opts) {
        $cmd .= " --bfly_opts \"$bfly_opts\" ";
    }
    
	print "$cmd\n";
}

exit(0);




		
