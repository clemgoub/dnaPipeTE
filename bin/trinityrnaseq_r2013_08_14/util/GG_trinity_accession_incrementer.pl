#!/usr/bin/env perl

use strict;
use warnings;



my $counter = 0;

while (<>) {
    my $filename = $_;
    chomp $filename;
    unless (-e $filename) {
        print STDERR "ERROR, filename: $filename is indicated to not exist.\n";
        next;
    }
    if (-s $filename) {
        $counter++;
        open (my $fh, $filename) or die "Error, cannot open file $filename";
        while (<$fh>) {
            if (/>/) {
                s/>/>GG$counter\|/;
            }
            print;
        }
    }
}

exit(0);

