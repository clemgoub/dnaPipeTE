#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib ("$FindBin::Bin/../../PerlLibAdaptors", "$FindBin::Bin/../../PerlLibAdaptors/LSF_perl_lib");
use Run_Bsub;
use BroadInstGridRunner;
use List::Util qw (shuffle);

use Getopt::Long qw(:config no_ignore_case bundling);

my $usage = <<_EOUSAGE_;

################################################################
# Required:
#
#  -c <string>        file containing list of commands
#  
# Optional:
#
#  -q <string>        grid submissions queue (defaults to 'broad')
#  -M <int>           memory to reserve (default: 4, which means 4 G)
#
#  --cmds_per_node <int>   commands for each grid node to process (recommend leaving this alone).
#  --mount_test            directory for grid nodes to check for existence of (and proper mounting)
#  --group <string>        group to submit to LSF under (eg. 'gscidfolk', 'flowerfolk', 'aprodfolk')
#  --ParaFly               any grid-failed commands are run directly  using ParaFly
#  --max_nodes <int>       no more than this number of nodes will be in play at any point in time.
#  
#
####################################################################

_EOUSAGE_

	;


my $help_flag;
my ($cmd_file, $cmds_per_node, $mount_test, $parafly, $max_nodes);

my $memory = 4;

my $queue = 'week';

my $group;

if ($mount_test && ! -e $mount_test ) {
	die "Error, can't locate $mount_test ";
}

&GetOptions ( 'h' => \$help_flag,
			  'c=s' => \$cmd_file,
			  'q=s' => \$queue,
			  'M=i' => \$memory,
			  'cmds_per_node=i' => \$cmds_per_node,
			  'mount_test=s' => \$mount_test,
              'group=s' => \$group,
              'ParaFly' => \$parafly,
              'max_nodes=i' => \$max_nodes,
              );


unless ($cmd_file) { 
	die $usage;
}
if ($help_flag) {
	die $usage;
}


## add Parafly to path
$ENV{PATH} .= ":" . "$FindBin::Bin/../trinity-plugins/parafly/bin/";


main: {

	my $uname = `uname -n`;
	chomp $uname;

	print "SERVER: $uname, PID: $$\n";
	
    
    open (my $fh, $cmd_file) or die "Error, cannot open $cmd_file";
    my @cmds;

    while (<$fh>) {
        chomp;
        if (/\w/) {
            push (@cmds, $_);
        }
    }
    close $fh;

    @cmds = shuffle @cmds;  ## to even out load on grid nodes.  Some may topload their jobs!

    if ($cmds_per_node) {
        $Run_Bsub::CMDS_PER_NODE = $cmds_per_node;
    }
    
    if ($max_nodes) {
        &Run_Bsub::set_max_nodes($max_nodes);
    }

	if ($queue) {
		&Run_Bsub::set_queue($queue);
	}
 
	if ($memory) {
		&Run_Bsub::set_memory($memory);
	}

	if ($mount_test) {
		&Run_Bsub::set_mount_test($mount_test);
	}
	
    if ($group) {
        &Run_Bsub::set_group($group);
    }
    
	my @failed_cmds;

    if ($parafly) {
        
        &BroadInstGridRunner::run_on_grid(@cmds);
        
    }
    else {
        @failed_cmds = &Run_Bsub::run(@cmds);
    }
    

    if (@failed_cmds) {
        exit(1);
    }
    else {
        ## all good
        exit(0);
    }
}



    
    
