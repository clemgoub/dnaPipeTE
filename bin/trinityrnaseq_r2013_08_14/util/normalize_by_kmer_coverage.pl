#!/usr/bin/env perl

use strict;
use warnings;
use threads;
no strict qw(subs refs);

use FindBin;
use lib ("$FindBin::Bin/../PerlLib");
use File::Basename;
use Cwd;
use Carp;
use Getopt::Long qw(:config no_ignore_case bundling pass_through);
use Fastq_reader;
use Fasta_reader;
use threads;

open (STDERR, ">&STDOUT");  ## capturing stderr and stdout in a single stdout stream


## Jellyfish
my $max_memory;

# Note: For the Trinity logo below the backslashes are quoted in order to keep
#   them from quoting the character than follows them.  "\\" keeps "\ " from occuring.

my $output_directory = "normalized_reads";
my $help_flag;
my $seqType;
my $left_file;
my $right_file;
my $left_list_file;
my $right_list_file;
my $single_file;
my $SS_lib_type;
my $JELLY_CPU = 2;
my $MIN_KMER_COV_CONST = 2;  ## DO NOT CHANGE
my $max_cov;
my $pairs_together_flag = 0;
my $max_pct_stdev = 100;
my $KMER_SIZE = 25;

my $__devel_report_kmer_cov_stats = 0;

my $PARALLEL_STATS = 0;

my $usage = <<_EOUSAGE_;


###############################################################################
#
# Required:
#
#  --seqType <string>      :type of reads: ( 'fq' or 'fa')
#  --JM <string>            :(Jellyfish Memory) number of GB of system memory to use for 
#                            k-mer counting by jellyfish  (eg. 10G) *include the 'G' char 
#
#  --max_cov <int>         :targeted maximum coverage for reads.
#
#
#  If paired reads:
#      --left  <string>    :left reads
#      --right <string>    :right reads
#
#  Or, if unpaired reads:
#      --single <string>   :single reads
#
#  Or, if you have read collections in different files you can use 'list' files, where each line in a list
#  file is the full path to an input file.  This saves you the time of combining them just so you can pass
#  a single file for each direction.
#      --left_list  <string> :left reads, one file path per line
#      --right_list <string> :right reads, one file path per line
#
####################################
##  Misc:  #########################
#
#  --pairs_together                :process paired reads by averaging stats between pairs and retaining linking info.
#
#  --SS_lib_type <string>          :Strand-specific RNA-Seq read orientation.
#                                   if paired: RF or FR,
#                                   if single: F or R.   (dUTP method = RF)
#                                   See web documentation.
#  --output <string>               :name of directory for output (will be
#                                   created if it doesn't already exist)
#                                   default( "${output_directory}" )
#
#  --JELLY_CPU <int>                     :number of threads for Jellyfish to use (default: 2)
#  --PARALLEL_STATS                :generate read stats in parallel for paired reads (Figure 2X Inchworm memory requirement)
#  --PE_reads_unordered            :set if the input paired-end reads are not identically ordered in the left.fq and right.fq files.
#
#  --KMER_SIZE <int>               :default 25
#
#  --max_pct_stdev <int>           :maximum pct of mean for stdev of kmer coverage across read (default: 100)
#
###############################################################################




_EOUSAGE_

    ;

my $ROOTDIR = "$FindBin::RealBin/../";
my $UTILDIR = "$ROOTDIR/util";
my $INCHWORM_DIR = "$ROOTDIR/Inchworm";
my $JELLYFISH_DIR = "$ROOTDIR/trinity-plugins/jellyfish";
my $FASTOOL_DIR = "$ROOTDIR/trinity-plugins/fastool";

unless (@ARGV) {
    die "$usage\n";
}

my $NO_FASTOOL = 0;
my $NO_CLEANUP = 0;
my $FULL_CLEANUP = 0;

my $PE_reads_unordered = 0;

&GetOptions( 
             
    'h|help' => \$help_flag,

    ## general opts
    "seqType=s" => \$seqType,
    "left=s" => \$left_file,
    "right=s" => \$right_file,
    "single=s" => \$single_file,
    
    "left_list=s" => \$left_list_file,
    "right_list=s" => \$right_list_file,
    
    "SS_lib_type=s" => \$SS_lib_type,
    "max_cov=i" => \$max_cov,
    "output=s" => \$output_directory,

    # Jellyfish
    'JM=s'          => \$max_memory, # in GB

    # misc
    'no_fastool' => \$NO_FASTOOL,
    'no_cleanup' => \$NO_CLEANUP,
    'KMER_SIZE=i' => \$KMER_SIZE,
    'JELLY_CPU=i' => \$JELLY_CPU,
    'PARALLEL_STATS' => \$PARALLEL_STATS,
    'kmer_size=i' => \$KMER_SIZE,
    'max_pct_stdev=i' => \$max_pct_stdev,
    'pairs_together' => \$pairs_together_flag,
    'PE_reads_unordered' => \$PE_reads_unordered,


     #devel
     '__devel_report_kmer_cov_stats' => \$__devel_report_kmer_cov_stats,

);



if ($help_flag) {
    die "$usage\n";
}

if (@ARGV) {
    die "Error, do not understand options: @ARGV\n";
}


my $USE_FASTOOL = 1; # by default, using fastool for fastq to fasta conversion
if ($NO_FASTOOL) {
    $USE_FASTOOL = 0;
}


if ($SS_lib_type) {
    unless ($SS_lib_type =~ /^(R|F|RF|FR)$/) {
        die "Error, unrecognized SS_lib_type value of $SS_lib_type. Should be: F, R, RF, or FR\n";
    }
}

unless ( ($left_file && $right_file) || ($left_list_file && $right_list_file) || $single_file ) {
    die "Error, need either options 'left' and 'right' or option 'single'\n";
}


unless ($max_cov && $max_cov >= 2) {
    die "Error, need to set --max_cov at least 2";
}



## keep the original 'xG' format string for the --JM option, then calculate the numerical value for max_memory
my $JM_string = $max_memory;    ## this one is used in the Chrysalis exec string
if ($max_memory) {
    $max_memory =~ /^([\d\.]+)G$/ or die "Error, cannot parse max_memory value of $max_memory.  Set it to 'xG' where x is a numerical value\n";
    
    $max_memory = $1;
    $max_memory *= 1024**3; # convert to from gig to bytes
}
else {
    die "Error, must specify max memory for jellyfish to use, eg.  --JM 10G \n";
}

if ($pairs_together_flag && ! ( ($left_file && $right_file) || ($left_list_file && $right_list_file) ) ) {
    die "Error, if setting --pairs_together, must use the --left and --right parameters.";
}


main: {
    
    my $start_dir = cwd();

    ## create complete paths for input files:
    $left_file = &create_full_path($left_file) if $left_file;
    $right_file = &create_full_path($right_file) if $right_file;
    $left_list_file = &create_full_path($left_list_file) if $left_list_file;
    $right_list_file = &create_full_path($right_list_file) if $right_list_file;
    $single_file = &create_full_path($single_file) if $single_file;
    $output_directory = &create_full_path($output_directory);
    
    unless (-d $output_directory) {
        
        mkdir $output_directory or die "Error, cannot mkdir $output_directory";
    }
    
    chdir ($output_directory) or die "Error, cannot cd to $output_directory";
    
    
    my $trinity_target_fa = ($single_file) ? "single.fa" : "both.fa"; 

    my @files_need_stats;
    
    if ( ($left_file && $right_file) || 
         ($left_list_file && $right_list_file) ) {
        
        my ($left_SS_type, $right_SS_type);
        if ($SS_lib_type) {
            ($left_SS_type, $right_SS_type) = split(//, $SS_lib_type);
        }

        print("Converting input files. (both directions in parallel)");

        my $thr1;
        my $thr2;
        
        if (! -s "left.fa") {
            if ( $left_list_file ) {
                my $left_files = read_list_file( $left_list_file );
                $thr1 = threads->create('prep_list_of_seqs', $left_files, $seqType, "left", $left_SS_type);
            } else {
                $thr1 = threads->create('prep_seqs', $left_file, $seqType, "left", $left_SS_type);
            }
        } else {
            $thr1 = threads->create(sub { print ("left file exists, nothing to do");});
        }
        
        if (! -s "right.fa") {
            if ( $right_list_file ) {
                my $right_files = read_list_file( $right_list_file );
                $thr2 = threads->create('prep_list_of_seqs', $right_files, $seqType, "right", $right_SS_type);
            } else {
                $thr2 = threads->create('prep_seqs', $right_file, $seqType, "right", $right_SS_type);
            }
        } else {
            $thr2 = threads->create(sub { print ("right file exists, nothing to do");});
        }
		
        $thr1->join();
		$thr2->join();

        if ($thr1->error() || $thr2->error()) {
            die "Error, conversion thread failed";
        }
        
		print("Done converting input files.");
        
        if ( $left_list_file && $right_list_file ) {
            push (@files_need_stats, 
                  [$left_list_file, "left.fa"], 
                  [$right_list_file, "right.fa"]);
        } else {
            push (@files_need_stats, 
                  [$left_file, "left.fa"], 
                  [$right_file, "right.fa"]);
        }
        
        
        &process_cmd("cat left.fa right.fa > $trinity_target_fa") unless (-s $trinity_target_fa);
        unless (-s $trinity_target_fa == ((-s "left.fa") + (-s "right.fa"))){
            die "$trinity_target_fa (".(-s $trinity_target_fa)." bytes) is different from the combined size of left.fa and right.fa (".((-s "left.fa") + (-s "right.fa"))." bytes)\n";
        }
        
    } elsif ($single_file) {
        &prep_seqs($single_file, $seqType, "single", $SS_lib_type);
        push (@files_need_stats, [$single_file, "single.fa"]);
        
    } else {
        die "not sure what to do. "; # should never get here.
    }

    my $kmer_file = &run_jellyfish($trinity_target_fa, $SS_lib_type);

    &generate_stats_files(\@files_need_stats, $kmer_file, $SS_lib_type);

    if ($pairs_together_flag) {
        &run_nkbc_pairs_together(\@files_need_stats, $kmer_file, $SS_lib_type, $max_cov, $max_pct_stdev);
    } else {
        &run_nkbc_pairs_separate(\@files_need_stats, $kmer_file, $SS_lib_type, $max_cov, $max_pct_stdev);
    }
    

    
    my @outputs;
    
    my @threads;
    foreach my $info_aref (@files_need_stats) {
        my ($orig_file, $converted_file, $stats_file, $selected_entries) = @$info_aref;

        ## do multi-threading

        my $normalized_filename_prefix = "$orig_file.normalized_K${KMER_SIZE}_C${max_cov}_pctSD${max_pct_stdev}";
        my $outfile;
        
        if ($seqType eq 'fq') {
            $outfile = "$normalized_filename_prefix.fq";
        }
        else {
            # fastA
            $outfile = "$normalized_filename_prefix.fa";
        }
        push (@outputs, $outfile);
        
        ## run in parallel
        my $thread;
        
        if ( $left_list_file && $right_list_file ) {
            $thread = threads->create('make_normalized_reads_file', $orig_file, "${seqType}list", $selected_entries, $outfile);
        } else {
            $thread = threads->create('make_normalized_reads_file', $orig_file, $seqType, $selected_entries, $outfile);
        }
        
        push (@threads, $thread);
    }
    
    my $num_fail = 0;
    foreach my $thread (@threads) {
        $thread->join();
        if ($thread->error()) {
            print STDERR "Error encountered with thread.\n";
            $num_fail++;
        }
    }
    if ($num_fail) {
        die "Error, at least one thread died";
    }
    

    print "Normalization complete. See outputs: " . join(", ", @outputs) . "\n";
    



    exit(0);
}


####
sub build_selected_index {
    my $file = shift;
    
    my %index = ();
    
    open(my $ifh, $file) || die "failed to read selected_entries file $file: $!";
    
    while (my $line = <$ifh> ) {
        chomp $line;
        next unless $line =~ /\S/;
        
        $index{$line} = 0;
    }
    
    return \%index;
}


####
sub make_normalized_reads_file {
    my ($source_file, $source_file_type, $selected_entries, $outfile) = @_;

    open (my $ofh, ">$outfile") or die "Error, cannot write to $outfile";

    my $seqType;
    my $source_files = [];
    if ( $source_file_type eq 'fqlist' ) {
        $source_files = read_list_file( $source_file );
        $seqType = 'fq';
    } elsif ( $source_file_type eq 'falist' ) {
        $source_files = read_list_file( $source_file );
        $seqType = 'fa';
    } else {
        push @$source_files, $source_file;
        $seqType = $source_file_type;
    }
    
    my $idx = build_selected_index( $selected_entries );
    
    for my $orig_file ( @$source_files ) {
        my $reader;
        
        # if we had a consistent interface for the readers, we wouldn't have to code this up separately below... oh well.
        ##  ^^ I enjoyed this lamentation, so I left it in the rewrite - JO
        if    ($seqType eq 'fq') { $reader = new Fastq_reader($orig_file) } 
        elsif ($seqType eq 'fa') { $reader = new Fasta_reader($orig_file) }
        else {  die "Error, do not recognize format: $seqType" }
        
        while ( my $seq_obj = $reader->next() ) {
        
            my $acc;
        
            if ($seqType eq 'fq') {
                $acc = $seq_obj->get_core_read_name();
            } elsif ($seqType eq 'fa') {
                $acc = $seq_obj->get_accession();
                $acc =~ s|/[12]$||;
            }
            
            if ( exists $$idx{$acc} ) {
                $$idx{$acc}++;
                my $record = '';
                
                if    ($seqType eq 'fq') { $record = $seq_obj->get_fastq_record() } 
                elsif ($seqType eq 'fa') { $record = $seq_obj->get_FASTA_format(fasta_line_len => -1) }
                
                print $ofh $record;
            }
        }
    }
    
    ## check and make sure they were all found
    my $not_found_count = 0;
    for my $k ( keys %$idx ) {
        $not_found_count++ if $$idx{$k} == 0;
    }
    
    if ( $not_found_count ) {
        die "Error, not all specified records have been retrieved (missing $not_found_count) from $source_file";
    }
    
    return;
}


####
sub run_jellyfish {
    my ($reads, $strand_specific_flag) = @_;
    
    my $jelly_kmer_fa_file = "jellyfish.K${KMER_SIZE}.min${MIN_KMER_COV_CONST}.kmers.fa";
    
    print STDERR "-------------------------------------------\n"
        . "----------- Jellyfish  --------------------\n"
        . "-- (building a k-mer catalog from reads) --\n"
        . "-------------------------------------------\n\n";
    
    my $jellyfish_checkpoint = "$jelly_kmer_fa_file.success";
    
    unless (-e $jellyfish_checkpoint) {


        my $read_file_size = -s $reads;
        
        my $jelly_hash_size = int( ($max_memory - $read_file_size)/7); # decided upon by Rick Westerman
        
        
        if ($jelly_hash_size < 100e6) {
            $jelly_hash_size = 100e6; # seems reasonable for a min hash size as 100M
        }
        
        my $cmd = "$JELLYFISH_DIR/bin/jellyfish count -t $JELLY_CPU -m $KMER_SIZE -s $jelly_hash_size ";
        
        unless ($SS_lib_type) {
            ## count both strands
            $cmd .= " --both-strands ";
        }
        
        $cmd .= " $reads";
        
        &process_cmd($cmd);
        
        my @kmer_db_files;
        
        if (-s $jelly_kmer_fa_file) {
            unlink($jelly_kmer_fa_file) or die "Error, cannot unlink $jelly_kmer_fa_file";
        }
        
        my @tmp_files;
        
        foreach my $file (<mer_counts_*>) {
            my $cmd = "$JELLYFISH_DIR/bin/jellyfish dump -L $MIN_KMER_COV_CONST $file >> $jelly_kmer_fa_file";
            
            &process_cmd($cmd);
            push (@tmp_files, $file); # don't retain the individual jelly kmer files.
        }
        
        
        foreach my $tmp_file (@tmp_files) {
            unlink($tmp_file);
        }
        
        &process_cmd("touch $jellyfish_checkpoint");
    }
    

    return($jelly_kmer_fa_file);
}


####  (from Trinity.pl)
## WARNING: this function appends to the target output file, so a -s check is advised
#   before you call this for the first time within any given script.
sub prep_seqs {
    my ($initial_file, $seqType, $file_prefix, $SS_lib_type) = @_;

    if ($seqType eq "fq") {
        # make fasta
        
        my $perlcmd = "$UTILDIR/fastQ_to_fastA.pl -I $initial_file ";
        my $fastool_cmd = "$FASTOOL_DIR/fastool";
        if ($SS_lib_type && $SS_lib_type eq "R") {
            $perlcmd .= " --rev ";
            $fastool_cmd .= " --rev ";
        }
        $fastool_cmd .= " --illumina-trinity --to-fasta $initial_file >> $file_prefix.fa";
        $perlcmd .= " >> $file_prefix.fa";  
        
       
        my $cmd = ($USE_FASTOOL) ? $fastool_cmd : $perlcmd;
        
        &process_cmd($cmd);
    }
    elsif ($seqType eq "fa") {
        if ($SS_lib_type && $SS_lib_type eq "R") {
            my $cmd = "$UTILDIR/revcomp_fasta.pl $initial_file >> $file_prefix.fa";
            &process_cmd($cmd);
        }
        else {
            ## just symlink it here:
            my $cmd = "ln -s $initial_file $file_prefix.fa";
            &process_cmd($cmd) unless (-e "$file_prefix.fa");
        }
    }
    elsif (($seqType eq "cfa") | ($seqType eq "cfq")) {
        # make double-encoded fasta
        my $cmd = "$UTILDIR/csfastX_to_defastA.pl -I $initial_file ";
        if ($SS_lib_type && $SS_lib_type eq "R") {
            $cmd .= " --rev ";
        }
        $cmd .= ">> $file_prefix.fa";
        &process_cmd($cmd);
  }
    return;
}



###
sub prep_list_of_seqs {
    my ($files, $seqType, $file_prefix, $SS_lib_type) = @_;
    
    for my $file ( @$files ) {
        prep_seqs( $file,  $seqType, $file_prefix, $SS_lib_type);
    }
    
    return 0;
}


###
sub create_full_path {
    my ($file) = @_;

    my $cwd = cwd();
    if ($file !~ m|^/|) { # must be a relative path
        $file = $cwd . "/$file";
    }
    
    return($file);
}


###
sub read_list_file {
    my ($file, $regex) = @_;
    
    my $files = [];
    
    open(my $ifh, $file) || die "failed to read input list file ($file): $!";
    
    while (my $line = <$ifh>) {
        chomp $line;
        next unless $line =~ /\S/;
        
        if ( defined $regex ) {
            if ( $line =~ /$regex/ ) {
                push @$files, $line;
            }
        } else {
            push @$files, $line;
        }
    }
    
    return $files;
}


####
sub process_cmd {
    my ($cmd) = @_;

    print "CMD: $cmd\n";

    my $start_time = time();
    my $ret = system($cmd);
    my $end_time = time();

    if ($ret) {
        die "Error, cmd: $cmd died with ret $ret";
    }
    
    print "CMD finished (" . ($end_time - $start_time) . " seconds)\n";    

    return;
}

####
sub generate_stats_files {
    my ($files_need_stats_aref, $kmer_file, $SS_lib_type) = @_;
    
    my @cmds;

    foreach my $info_aref (@$files_need_stats_aref) {
        my ($orig_file, $converted_fa_file) = @$info_aref;

        my $stats_filename = "$converted_fa_file.K$KMER_SIZE.stats";
        push (@$info_aref, $stats_filename);
        
        my $cmd = "$INCHWORM_DIR/bin/fastaToKmerCoverageStats --reads $converted_fa_file --kmers $kmer_file --kmer_size $KMER_SIZE  ";
        unless ($SS_lib_type) {
            $cmd .= " --DS ";
        }

        if ($__devel_report_kmer_cov_stats) {
            $cmd .= " --capture_coverage_info ";
        }
        
        $cmd .= " > $stats_filename";
    
        push (@cmds, $cmd) unless (-s $stats_filename);
    }
    
    if (@cmds) {
        if ($PARALLEL_STATS) {
            &process_cmds_parallel(@cmds);
        }
        else {
            &process_cmds_serial(@cmds);
        }
    }
    
    if ($PE_reads_unordered) {
        ## sort by read name
        print STDERR "-not trusting read ordering, sorting each stats file.\n";
        my @cmds;
        foreach my $info_aref (@$files_need_stats_aref) {
            my $stats_file = $info_aref->[-1];
            my $sorted_stats_file = $stats_file . ".sort";
            my $cmd = "sort -k5,5 -T . $stats_file > $sorted_stats_file";
            push (@cmds, $cmd) unless (-s $sorted_stats_file);
            $info_aref->[-1] = $sorted_stats_file;
        }
        
        if (@cmds) {
            if ($PARALLEL_STATS) {
                &process_cmds_parallel(@cmds);
            }
            else {
                &process_cmds_serial(@cmds);
            }
            
        }
    }
    
    return;
}


####
sub run_nkbc_pairs_separate {
    my ($files_need_stats_aref, $kmer_file, $SS_lib_type, $max_cov, $max_pct_stdev) = @_;

    my @cmds;

    foreach my $info_aref (@$files_need_stats_aref) {
        my ($orig_file, $converted_file, $stats_file) = @$info_aref;
                
        my $selected_entries = "$stats_file.C$max_cov.pctSD$max_pct_stdev.accs";
        my $cmd = "$UTILDIR/nbkc_normalize.pl $stats_file $max_cov $max_pct_stdev > $selected_entries";
        push (@cmds, $cmd);

        push (@$info_aref, $selected_entries);

    }


    &process_cmds_parallel(@cmds); ## low memory, all I/O - fine to always run in parallel.

    return;
        
}


####
sub run_nkbc_pairs_together {
    my ($files_need_stats_aref, $kmer_file, $SS_lib_type, $max_cov, $max_pct_stdev) = @_;

    my $left_stats_file = $files_need_stats_aref->[0]->[2];
    my $right_stats_file = $files_need_stats_aref->[1]->[2];
        
    my $pair_out_stats_filename = "pairs.K$KMER_SIZE.stats";
    
    my $cmd = "$UTILDIR/nbkc_merge_left_right_stats.pl --left $left_stats_file --right $right_stats_file ";
    if ($PE_reads_unordered) {
        $cmd .= " --sorted ";
    }
    $cmd .= " > $pair_out_stats_filename";
    
    &process_cmd($cmd) unless (-s $pair_out_stats_filename);
    
    my $selected_entries = "$pair_out_stats_filename.C$max_cov.pctSD$max_pct_stdev.accs";
    $cmd = "$UTILDIR/nbkc_normalize.pl $pair_out_stats_filename $max_cov $max_pct_stdev > $selected_entries";
    &process_cmd($cmd);
    
    push (@{$files_need_stats_aref->[0]}, $selected_entries);
    push (@{$files_need_stats_aref->[1]}, $selected_entries);
    
    
    return;
    
}



####
sub process_cmds_parallel {
    my @cmds = @_;


    my @threads;
    foreach my $cmd (@cmds) {
        # should only be 2 cmds max
        my $thread = threads->create('process_cmd', $cmd);
        push (@threads, $thread);
    }
                
    my $ret = 0;
    
    foreach my $thread (@threads) {
        $thread->join();
        if (my $error = $thread->error()) {
            print STDERR "Error, thread exited with error $error\n";
            $ret++;
        }
    }
    if ($ret) {
        die "Error, $ret threads errored out";
    }

    return;
}

####
sub process_cmds_serial {
    my @cmds = @_;

    foreach my $cmd (@cmds) {
        &process_cmd($cmd);
    }

    return;
}


    
