#!/usr/bin/env perl

use strict;
use warnings;
use Carp;
use Getopt::Long qw(:config no_ignore_case bundling);
use Cwd;
use FindBin;
use File::Basename;
use lib ("$FindBin::Bin/../../PerlLib");
use Fasta_reader;
use Data::Dumper;

my $usage = <<__EOUSAGE__;


#################################################################################################
#
#  Required:
#
#  --matrix <string>               matrix of raw read counts (not normalized!)
#
#  --method <string>               edgeR|DESeq   (DESeq only supported here w/ bio replicates)
#
#
#  Optional:
#
#  --samples_file <string>         tab-delimited text file indicating biological replicate relationships.
#                                   ex.
#                                        cond_A    cond_A_rep1
#                                        cond_A    cond_A_rep2
#                                        cond_B    cond_B_rep1
#                                        cond_B    cond_B_rep2
#
#
#  General options:
#
#  --min_rowSum_counts <int>       default: 10  (only those rows of matrix meeting requirement will be tested)
#
#  --output|o                      aname of directory to place outputs (default: \$method.\$pid.dir)
#
###############################################################################################
#
#  ## EdgeR-related parameters
#  ## (no biological replicates)
#
#  --dispersion <float>            edgeR dispersion value (default: 0.1)   set to 0 for poisson (sometimes breaks...)
#
#  http://www.bioconductor.org/packages/release/bioc/html/edgeR.html
#
###############################################################################################
#
#  ## DE-Seq related parameters
#
#  --DESEQ_method <string>         "pooled", "pooled-CR", "per-condition", "blind" 
#  --DESEQ_sharingMode <string>    "maximum", "fit-only", "gene-est-only"   
#  --DESEQ_fitType <string>        fitType = c("parametric", "local")
#
#  ## (no biological replicates)
#        note: FIXED as: method=blind, sharingMode=fit-only
#       
#  http://www.bioconductor.org/packages/release/bioc/html/DESeq.html
#
################################################################################################



__EOUSAGE__


    ;


my $matrix_file;
my $method;
my $samples_file;
my $min_rowSum_counts = 10;
my $help_flag;
my $output_dir;
my $dispersion = 0.1;
my $GENE_EST_ONLY = 0;

my ($DESEQ_method, $DESEQ_sharingMode, $DESEQ_fitType);


&GetOptions ( 'h' => \$help_flag,
              'matrix=s' => \$matrix_file,              
              'method=s' => \$method,
              'samples_file=s' => \$samples_file,
              'output|o=s' => \$output_dir,
              'min_rowSum_counts=i' => \$min_rowSum_counts,
              'dispersion=f' => \$dispersion,
    
              'gene_est_only' => \$GENE_EST_ONLY,

              
              'DESEQ_method=s' => \$DESEQ_method,
              'DESEQ_sharingMode=s' => \$DESEQ_sharingMode,
              'DESEQ_fitType=s' => \$DESEQ_fitType,


    );



if ($help_flag) {
    die $usage;
}


unless ($matrix_file 
        && $method
    ) { 
    
    die $usage;
    
}

if ($matrix_file =~ /fpkm/i) {
    die "Error, be sure you're using a matrix file that corresponds to raw counts, and not FPKM values.\n"
        . "If this is correct, then please rename your file, and remove fpkm from the name.\n\n";
}


unless ($method =~ /^(edgeR|DESeq)$/) {
    die "Error, do not recognize method: [$method], only edgeR or DESeq currently.";
}

main: {

    
    
    my %sample_name_to_column = &get_sample_name_to_column_index($matrix_file);
    
    my %samples;
    if ($samples_file) {
        %samples = &parse_sample_info($samples_file);
    }
    else {
        foreach my $sample_name (keys %sample_name_to_column) {
            $samples{$sample_name} = [$sample_name];
        }
    }

    print Dumper(\%samples);

    
    if ($matrix_file !~ /^\//) {
        ## make full path
        $matrix_file = cwd() . "/$matrix_file";
    }
    
    unless ($output_dir) {
        $output_dir = "$method.$$.dir";
    }
    
    mkdir($output_dir) or die "Error, cannot mkdir $output_dir";
    chdir $output_dir or die "Error, cannot cd to $output_dir";
    

    my @sample_names = keys %samples;

    print "Samples to compare: " . Dumper(\@sample_names) . "\n";
    
    ## examine all pairwise comparisons.
    for (my $i = 0; $i < $#sample_names; $i++) {

        my $sample_i = $sample_names[$i];
        
        for (my $j = $i + 1; $j <= $#sample_names; $j++) {

            my $sample_j = $sample_names[$j];

            my ($sample_a, $sample_b) = sort ($sample_i, $sample_j);
            
            if ($method eq "edgeR") {
                &run_edgeR_sample_pair($matrix_file, \%samples, \%sample_name_to_column, $sample_a, $sample_b);
            
            }
            elsif ($method eq "DESeq") {
                &run_DESeq_sample_pair($matrix_file, \%samples, \%sample_name_to_column, $sample_a, $sample_b);
            }
        }
    }
    
        

    exit(0);
}

####
sub parse_sample_info {
    my ($sample_file) = @_;

    my %samples;

    open (my $fh, $sample_file) or die $!;
    while (<$fh>) {
        unless (/\w/) { next; }
        if (/^\#/) { next; } # allow comments
        chomp;
        s/^\s+//; # trim any leading ws
        my @x = split(/\s+/); # now ws instead of just tabs
        if (scalar @x < 2) { next; }
        my ($sample_name, $replicate_name, @rest) = @x;
        
        #$sample_name =~ s/^\s|\s+$//g;
        #$replicate_name =~ s/^\s|\s+$//g;
        
        push (@{$samples{$sample_name}}, $replicate_name);
    }
    close $fh;

    return(%samples);
}

####
sub get_sample_name_to_column_index {
    my ($matrix_file) = @_;

    my %column_index;

    open (my $fh, $matrix_file) or die "Error, cannot open file $matrix_file";
    my $header_line = <$fh>;

    $header_line =~ s/^\#//; # remove comment field.
    $header_line =~ s/^\s+|\s+$//g;
    my @samples = split(/\t/, $header_line);

    { # check for disconnect between header line and data lines
        my $next_line = <$fh>;
        my @x = split(/\t/, $next_line);
        print STDERR "Got " . scalar(@samples) . " samples, and got: " . scalar(@x) . " data fields.\n";
        print STDERR "Header: $header_line\nNext: $next_line\n";
        
        if (scalar(@x) == scalar(@samples)) {
            # problem... shift headers over, no need for gene column heading
            shift @samples;
            print STDERR "-shifting sample indices over.\n";
        }
    }
    close $fh;
            
    
    my $counter = 0;
    foreach my $sample (@samples) {
        $counter++;
        
        $sample =~ s/\.(isoforms|genes)\.results$//; 
        
        $column_index{$sample} = $counter;
    }

    use Data::Dumper;
    print STDERR Dumper(\%column_index);
    

    return(%column_index);
    
}


####
sub run_edgeR_sample_pair {
    my ($matrix_file, $samples_href, $sample_name_to_column_index_href, $sample_A, $sample_B) = @_;
         
    my $output_prefix = basename($matrix_file) . "." . join("_vs_", ($sample_A, $sample_B));
        
    my $Rscript_name = "$output_prefix.$sample_A.vs.$sample_B.EdgeR.Rscript";
    
    my @reps_A = @{$samples_href->{$sample_A}};
    my @reps_B = @{$samples_href->{$sample_B}};

    my $num_rep_A = scalar(@reps_A);
    my $num_rep_B = scalar(@reps_B);
    
    my @rep_column_indices;
    foreach my $rep_name (@reps_A, @reps_B) {
        my $column_index = $sample_name_to_column_index_href->{$rep_name} or die "Error, cannot determine column index for replicate name [$rep_name]" . Dumper($sample_name_to_column_index_href);
        push (@rep_column_indices, $column_index);
    }
        

    ## write R-script to run edgeR
    open (my $ofh, ">$Rscript_name") or die "Error, cannot write to $Rscript_name";
    
    print $ofh "library(edgeR)\n";

    print $ofh "\n";
    
    print $ofh "data = read.table(\"$matrix_file\", header=T, row.names=1, com='')\n";
    print $ofh "col_ordering = c(" . join(",", @rep_column_indices) . ")\n";
    print $ofh "rnaseqMatrix = data[,col_ordering]\n";
    print $ofh "rnaseqMatrix = round(rnaseqMatrix)\n";
    print $ofh "rnaseqMatrix = rnaseqMatrix[rowSums(rnaseqMatrix)>=$min_rowSum_counts,]\n";
    print $ofh "conditions = factor(c(rep(\"$sample_A\", $num_rep_A), rep(\"$sample_B\", $num_rep_B)))\n";
    print $ofh "\n";
    print $ofh "exp_study = DGEList(counts=rnaseqMatrix, group=conditions)\n";
    print $ofh "exp_study = calcNormFactors(exp_study)\n";
    
    if ($num_rep_A > 1 && $num_rep_B > 1) {
        print $ofh "exp_study = estimateCommonDisp(exp_study)\n";
        print $ofh "exp_study = estimateTagwiseDisp(exp_study)\n";
        print $ofh "et = exactTest(exp_study)\n";
    }
    else {
        print $ofh "et = exactTest(exp_study, dispersion=$dispersion)\n";
    }
    print $ofh "tTags = topTags(et,n=NULL)\n";
    print $ofh "write.table(tTags, file=\'$output_prefix.edgeR.DE_results\', sep='\t', quote=F, row.names=T)\n";

    ## generate MA and Volcano plots
    print $ofh "source(\"$FindBin::Bin/R/rnaseq_plot_funcs.R\")\n";
    print $ofh "pdf(\"$output_prefix.edgeR.DE_results.MA_n_Volcano.pdf\")\n";
    print $ofh "result_table = tTags\$table\n";
    print $ofh "plot_MA_and_Volcano(result_table\$logCPM, result_table\$logFC, result_table\$FDR)\n";
    print $ofh "dev.off()\n";
    
    close $ofh;

    ## Run R-script
    my $cmd = "R --vanilla -q < $Rscript_name";


    eval {
        &process_cmd($cmd);
    };
    if ($@) {
        print STDERR "$@\n\n";
        print STDERR "\n\nWARNING: This EdgeR comparison failed...\n\n";
        ## if this is due to data paucity, such as in small sample data sets, then ignore for now.
    }
    

    return;
}

sub run_DESeq_sample_pair {
    my ($matrix_file, $samples_href, $sample_name_to_column_index_href, $sample_A, $sample_B) = @_;
         
    my $output_prefix = basename($matrix_file) . "." . join("_vs_", ($sample_A, $sample_B));
        
    my $Rscript_name = "$output_prefix.DESeq.Rscript";
    
    my @reps_A = @{$samples_href->{$sample_A}};
    my @reps_B = @{$samples_href->{$sample_B}};

    my $num_rep_A = scalar(@reps_A);
    my $num_rep_B = scalar(@reps_B);
    
    
    my @rep_column_indices;
    foreach my $rep_name (@reps_A, @reps_B) {
        my $column_index = $sample_name_to_column_index_href->{$rep_name} or die "Error, cannot determine column index for replicate name [$rep_name]" . Dumper($sample_name_to_column_index_href);
        push (@rep_column_indices, $column_index);
    }
    

    ## write R-script to run edgeR
    open (my $ofh, ">$Rscript_name") or die "Error, cannot write to $Rscript_name";
    
    print $ofh "library(DESeq)\n";
    print $ofh "\n";

    print $ofh "data = read.table(\"$matrix_file\", header=T, row.names=1, com='')\n";
    print $ofh "col_ordering = c(" . join(",", @rep_column_indices) . ")\n";
    print $ofh "rnaseqMatrix = data[,col_ordering]\n";
    print $ofh "rnaseqMatrix = round(rnaseqMatrix)\n";
    print $ofh "rnaseqMatrix = rnaseqMatrix[rowSums(rnaseqMatrix)>=$min_rowSum_counts,]\n";
    print $ofh "conditions = factor(c(rep(\"$sample_A\", $num_rep_A), rep(\"$sample_B\", $num_rep_B)))\n";
    print $ofh "\n";
    print $ofh "exp_study = newCountDataSet(rnaseqMatrix, conditions)\n";
    print $ofh "exp_study = estimateSizeFactors(exp_study)\n";
    #print $ofh "sizeFactors(exp_study)\n";
    #print $ofh "exp_study = estimateVarianceFunctions(exp_study)\n";
    
    if ($num_rep_A == 1 && $num_rep_B == 1) {
        
        print STDERR "\n\n** Note, no replicates, setting method='blind', sharingMode='fit-only'\n\n";
        
        $DESEQ_method = "blind";
        $DESEQ_sharingMode = "fit-only";
        
    }

    # got bio replicates
    my $est_disp_cmd = "exp_study = estimateDispersions(exp_study";
    
    if ($DESEQ_method) {
        $est_disp_cmd .= ", method=\"$DESEQ_method\"";
    }
    
    if ($DESEQ_sharingMode) {
        $est_disp_cmd .= ", sharingMode=\"$DESEQ_sharingMode\"";
    }
    
    if ($DESEQ_fitType) {
        $est_disp_cmd .= ", fitType=\"$DESEQ_fitType\"";
    }
    
    $est_disp_cmd .= ")\n";
    
    print $ofh $est_disp_cmd;
    
    
    #print $ofh "str(fitInfo(exp_study))\n";
    #print $ofh "plotDispEsts(exp_study)\n";
    print $ofh "\n";
    print $ofh "res = nbinomTest(exp_study, \"$sample_A\", \"$sample_B\")\n";
    print $ofh "\n";
## output results
    print $ofh "write.table(res[order(res\$pval),], file=\'$output_prefix.DESeq.DE_results\', sep='\t', quote=FALSE, row.names=FALSE)\n";
    
    ## generate MA and Volcano plots
    print $ofh "source(\"$FindBin::Bin/R/rnaseq_plot_funcs.R\")\n";
    print $ofh "pdf(\"$output_prefix.DESeq.DE_results.MA_n_Volcano.pdf\")\n";
    print $ofh "plot_MA_and_Volcano(log2(res\$baseMean+1), res\$log2FoldChange, res\$padj)\n";
    print $ofh "dev.off()\n";

    close $ofh;
    


    ## Run R-script
    my $cmd = "R --vanilla -q < $Rscript_name";
    &process_cmd($cmd);
    
    return;
}
        
####
sub process_cmd {
    my ($cmd) = @_;

    print "CMD: $cmd\n";
    my $ret = system($cmd);

    if ($ret) {
        die "Error, cmd: $cmd died with ret ($ret) ";
    }

    return;
}

