package BroadInstGridRunner;

use strict;
use warnings;
use Carp;
use base qw (GridRunner);  ## really just for aesthetics
use List::Util qw (shuffle);
use FindBin;

BEGIN {

    ## find the path to the LSF_perl_lib directory.
    foreach my $dir (@INC) {
        if (-d "$dir/LSF_perl_lib") {
            push (@INC, "$dir/LSF_perl_lib");
            last;
        }
    }
    
}

use Run_Bsub;
use Cwd;

####
sub run_on_grid {
    my @cmds = @_;

    @cmds = shuffle @cmds;

    &Run_Bsub::set_queue("hour -W 4:0"); # allow up to 4 hours per job; those that don't complete successfully will be run through ParaFly below
    &Run_Bsub::set_memory("4"); # 4 G of RAM
    &Run_Bsub::set_mount_test(cwd()); # only run on nodes with a verified mount
    
    my @failed_cmds = &Run_Bsub::run(@cmds);

    if (@failed_cmds) {
        
        my $num_failed_cmds = scalar(@failed_cmds);
        
        print STDERR "$num_failed_cmds commands failed during grid computing.\n";

        return(&run_parafly(@failed_cmds));
        
    }
    else {
        print "All commands completed successfully on the computing grid.\n";
        return(0);
    }
}

####
sub run_parafly {
    my (@cmds) = @_;

    my $cmds_file = "cmds_for_parafly.$$.txt";
    open (my $ofh, ">$cmds_file") or die "Error, cannot write to file $cmds_file";
    foreach my $cmd (@cmds) {
        print $ofh $cmd . "\n";
    }

    my $num_cpus = $ENV{OMP_NUM_THREADS} || 2;

    my $cmd = "$FindBin::Bin/trinity-plugins/parafly/bin/ParaFly -c $cmds_file -CPU $num_cpus -v -shuffle";
    
    my $ret = system($cmd);

    if ($ret) {
        die "Error, cmd: $cmd died with ret: $ret";
    }
    
    return(0);
}
    
1;

    

