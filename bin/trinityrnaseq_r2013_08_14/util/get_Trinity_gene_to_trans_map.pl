#!/usr/bin/env perl

use strict;
use warnings;


while (<>) {
    if (/>(\S+)/) {
        my $acc = $1;
        if ($acc =~ /^(.*comp\d+_c\d+)(_seq\d+)/) {
            my $gene = $1;
            my $trans = $1 . $2;

            print "$gene\t$trans\n";
        }
        else {
            print STDERR "WARNING: cannot decipher accession $acc\n";
        }
    }
}

exit(0);

