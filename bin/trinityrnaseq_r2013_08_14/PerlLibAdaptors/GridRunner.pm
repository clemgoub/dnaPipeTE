package GridRunner;

## Abstract class:  subclass it and implement the run_on_grid() method.

use strict;
use warnings;
use Carp;

####
sub run_on_grid {
    my @cmds = @_;

    ## Implement this method based on your computing platform
    
    my $num_failed = 0; ## execute the commands, capture the number failed.

    confess "Abstract class, grid-runner not implemented";

    ## if all commands are successfully executed: return (0)
    ## if any fail, return the number that fail: return(num_cmds_failed)
    
    return($num_failed);
}



1;

