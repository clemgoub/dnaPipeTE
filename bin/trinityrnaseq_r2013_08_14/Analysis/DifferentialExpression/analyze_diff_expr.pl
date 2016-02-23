#!/usr/bin/env perl

use strict;
use warnings;
use Carp;
use Getopt::Long qw(:config no_ignore_case bundling);


my $usage = <<__EOUSAGE__;

#################################################################################### 
#
# Required:
#
#  --matrix    matrix.normalized.FPKM
#
# Optional:
#
#  -P          p-value cutoff for FDR  (default: 0.001)
#
#  -C          min abs(log2(a/b)) fold change (default: 2  (meaning 2^(2) or 4-fold).
#
#  --output    prefix for output file (default: "diffExpr.P\${Pvalue}_C\${C})
#
#  Clustering methods:
#
#  --gene_dist <string>        euclidean, pearson, spearman,   (default: euclidean)
#                              maximum, manhattan, canberra, binary, minkowski
#
#  --gene_clust <string>       ward, single, complete, average, mcquitty, median, centroid (default: complete)
#
#
# Misc:
#
#  --max_DE_genes_per_comparison <int>    extract only up to the top number of DE features within each pairwise comparison.
#                                         This is useful when you have massive numbers of DE features but still want to make
#                                         useful heatmaps and other plots with more manageable numbers of data points.
#
#
####################################################################################


__EOUSAGE__

    ;


my $matrix_file;
my $p_value = 0.001;
my $log2_fold_change = 2;
my $output_prefix = "";
my $FORCE_FLAG = 0;
my $help_flag = 0;
my $DESeq_mode = 0;
my $gene_dist = "euclidean";
my $gene_clust = "complete";
my $max_DE_genes_per_comparison;

&GetOptions (  'h' => \$help_flag,
               
               'matrix=s' => \$matrix_file,
               'P=f' => \$p_value,
               'C=f' => \$log2_fold_change,
               'output=s' => \$output_prefix,
               'FORCE' => \$FORCE_FLAG, # for exploratory purposes.
               
               'gene_dist=s' => \$gene_dist,
               'gene_clust=s' => \$gene_clust,
               
               'max_DE_genes_per_comparison=i' => \$max_DE_genes_per_comparison,
               
               );


if ($help_flag) {
    die $usage;
}

unless ($gene_dist =~ /^(euclidean|pearson|spearman|maximum|manhattan|canberra|binary|minkowski)$/) {
    die "Error, do not recognize --gene_dist $gene_dist ";
}

unless ($gene_clust =~ /^(ward|single|complete|average|mcquitty|median|centroid)$/) {
    die "Error, do not recognize --gene_clust $gene_clust ";
}

unless ($matrix_file && -s $matrix_file) {
    die $usage;
}

unless ($output_prefix) {
    $output_prefix = "diffExpr.P${p_value}_C${log2_fold_change}";
}


main: {

    my @DE_result_files = <*.DE_results>;
    unless (@DE_result_files) {
        die "Error, no DE_results files!  This needs to be run in the edgeR or DESeq output directory";
    }

    my %column_header_to_index = &parse_column_headers($DE_result_files[0]);
    
    ## want P-value and log2(FC) columns
    
    my $pvalue_index = $column_header_to_index{padj}
    || $column_header_to_index{FDR}
    || die "Error, cannot identify FDR column from " . Dumper(\%column_header_to_index);
    

    my $log2FC_index = $column_header_to_index{log2FoldChange} 
    || $column_header_to_index{logFC} 
    || die "Error, cannot identify logFC column from " . Dumper(\%column_header_to_index);
    
    my $Mvalue_index = $column_header_to_index{baseMean}
    || $column_header_to_index{logCPM}
    || die "Error, cannot identify average counts column";
    
    
    my %read_count_rows;
    my $count_matrix_header;
    
    {
        open (my $fh, $matrix_file) or die "Error, cannot read file $matrix_file";
        $count_matrix_header = <$fh>;
        chomp $count_matrix_header;
        $count_matrix_header =~ s/^\s+//;
                
        while (<$fh>) {
            chomp;
            my @x = split(/\t/);
            my $acc = shift @x;
            $read_count_rows{$acc} = join("\t", @x);
        }
       
    }

    ## get list of genes that meet the criterion:
    my %diffExpr = &parse_result_files_find_diffExp(\@DE_result_files,
                                                    $p_value, $pvalue_index,
                                                    $log2_fold_change, $log2FC_index, \%read_count_rows, 
                                                    $count_matrix_header, $max_DE_genes_per_comparison);
    
    unless (%diffExpr) {
        die "Error, no differentially expressed transcripts identified at cuttoffs: P:$p_value, C:$log2_fold_change";
    }

    my $diff_expr_matrix = "$output_prefix.matrix";
    {
        open (my $ofh, ">$diff_expr_matrix") or die "Error, cannot write to file $diff_expr_matrix";
        print $ofh "\t$count_matrix_header\n";
        foreach my $acc (keys %diffExpr) {
            my $counts_row = $read_count_rows{$acc} or die "Error, no read counts row for $acc";
            print $ofh join("\t", $acc, $counts_row) . "\n";
        }
        close $ofh;
    }
    
    &cluster_diff_expressed_transcripts($diff_expr_matrix);
    

    print STDERR "\n\n** Found " . scalar(keys %diffExpr) . " features as differentially expressed.\n\n";

    exit(0);
    
}

####
sub cluster_diff_expressed_transcripts {
    my ($diff_expr_matrix_file) = @_;
    
    my $R_script = "$diff_expr_matrix_file.R";
    
    open (my $ofh, ">$R_script") or die "Error, cannot write to $R_script";
    
    print $ofh "library(cluster)\n";
    print $ofh "library(gplots)\n";
    print $ofh "library(Biobase)\n";
    print $ofh "library(ctc)\n";
    print $ofh "library(ape)\n";
    
    print $ofh "data = read.table(\"$diff_expr_matrix_file\", header=T, com=\'\', sep=\"\\t\")\n";
    print $ofh "rownames(data) = data[,1] # set rownames to gene identifiers\n";
        ;
    print $ofh "data = data[,2:length(data[1,])] # remove the gene column since its now the rowname value\n";
        ;
    print $ofh "data = as.matrix(data) # convert to matrix\n";
        ;
    ## generate correlation matrix
    print $ofh "cr = cor(data, method='spearman')\n";
    

    ## log2 transform, mean center rows
    print $ofh "data = log2(data+1)\n";
    print $ofh "centered_data = t(scale(t(data), scale=F)) # center rows, mean substracted\n";
        ;
    
    print $ofh "write.table(data, file=\"$diff_expr_matrix_file.centered\", sep=\"\t\", quote=F)\n"; 
    
    #print $ofh "hc_genes = agnes(data, diss=FALSE, metric=\"euclidean\") # cluster genes\n";
    
    
    if ($gene_dist =~ /spearman|pearson/) {
        if ($gene_dist eq "spearman") {
            print $ofh "gene_cor = cor(t(data), method='spearman')\n";
        }
        else {
            print $ofh "gene_cor = cor(t(data), method='spearman')\n";
        }
        print $ofh "gene_dist = as.dist(1-gene_cor)\n";
    }
    else {
        print $ofh "gene_dist = dist(data, method=\'$gene_dist\')\n";
    }

    print $ofh "hc_genes = hclust(gene_dist, method=\'$gene_clust\')\n";
    
    print $ofh "hc_samples = hclust(as.dist(1-cr), method=\"complete\") # cluster conditions\n";
    print $ofh "myheatcol = greenred(75)\n";
    print $ofh "gene_partition_assignments <- cutree(as.hclust(hc_genes), k=6);\n";
    print $ofh "partition_colors = rainbow(length(unique(gene_partition_assignments)), start=0.4, end=0.95)\n";
    print $ofh "gene_colors = partition_colors[gene_partition_assignments]\n";
    print $ofh "save(list=ls(all=TRUE), file=\"${R_script}.all.RData\")\n";
    
        
    
    print $ofh <<_EOTEXT;

    ordered_genes_file = paste("$diff_expr_matrix_file", ".ordered_gene_matrix", sep='');
    ordered_genes = data[hc_genes\$order,];
    write.table(ordered_genes, file=ordered_genes_file, quote=F, sep="\t");
    
    gene_tree = hc2Newick(hc_genes);
    gene_tree_filename = paste("$diff_expr_matrix_file", ".gene_tree", sep='');
    write(gene_tree, file=gene_tree_filename);

    # get rid of the distances since these can sometimes cause problems with other software tools. 
    gene_nodist_tree_filename = paste("$diff_expr_matrix_file", ".gene_nodist_tree", sep='');
    t = read.tree(text=gene_tree);
    t\$edge.length = NULL;
    write.tree(t, file=gene_nodist_tree_filename);
        
    sample_tree = hc2Newick(hc_samples);
    sample_tree_filename = paste("$diff_expr_matrix_file", ".sample_tree", sep='');
    write(sample_tree, file=sample_tree_filename);

_EOTEXT

        ;
    
    ## write plots
    
    #print $ofh "postscript(file=\"$diff_expr_matrix_file.heatmap.eps\", horizontal=FALSE, width=7, height=10, paper=\"special\");\n";
    

    print $ofh "quantBrks = quantile(data, c(0.03, 0.97))\n";

    print $ofh "pdf(\"$diff_expr_matrix_file.heatmap.pdf\")\n";
    
    print $ofh "heatmap.2(data, dendrogram='both', Rowv=as.dendrogram(hc_genes), Colv=as.dendrogram(hc_samples), col=myheatcol, RowSideColors=gene_colors, scale=\"none\", density.info=\"none\", trace=\"none\", key=TRUE, keysize=1.2, cexCol=1, lmat=rbind(c(5,0,4,0),c(3,1,2,0)), lhei=c(1.5,5),lwid=c(1.5,0.2,2.5,2.5), margins=c(12,5), breaks=seq(quantBrks[1], quantBrks[2], length=76))\n";
    
    #print $ofh "try(heatmap.2(cr, col = redgreen(75), scale='none', symm=TRUE, key=TRUE,density.info='none', trace='none', symkey=FALSE, Colv=TRUE,margins=c(10,10), cexCol=1, cexRow=1))\n";
    print $ofh "try(heatmap.2(cr, col = cm.colors(256), scale='none', symm=TRUE, key=TRUE,density.info='none', trace='none', symkey=FALSE, Colv=TRUE,margins=c(10,10), cexCol=1, cexRow=1))\n";


    print $ofh "dev.off()\n";
    
    
    close $ofh;
    
    eval {
        &process_cmd("R --vanilla -q < $R_script");
    };
    if ($@) {
        print STDERR "$@\n";
        ## keep on going...
    }
    

    return;
    

=notes from zehua regarding heatmap.2

you need to change the margin of the heatmap in the command heatmap.2:

margins=c(8,8),

The first number is the margin on the bottom (column name), and the second number is for the margin on the right (i.e., the row names). So you can increase the second number and you should get larger space for row names.

If you want to use a column order as you specified, then you can just turn off the ordering of the column by setting the following options in the heatmap.2 command:

dendrogram='row', Colv=FALSE

This will allow you to have a heatmap with column order from the data you provided.

=cut



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


####
sub parse_result_files_find_diffExp {
    my ($result_files_aref, 
        $max_p_value, $pvalue_index, 
        $min_abs_log2_fold_change, $log2FC_index, 
        $read_count_rows_href, $count_matrix_header, $max_DE_per_comparison) = @_;
    
    my %diff_expr;
    
    foreach my $result_file (@$result_files_aref) {
        
        open (my $fh, $result_file) or die "Error, cannot open file $result_file";
        open (my $ofh, ">$result_file.P${max_p_value}_C${min_abs_log2_fold_change}.subset") or die "Error, cannot write to $result_file.P${max_p_value}_C${min_abs_log2_fold_change}.subset";;
        

        my $count = 0;

        my $header = <$fh>;
        chomp $header;
        unless ($header =~ /^id\t/) {
            print $ofh "id\t";
        }
        print $ofh "$header\t$count_matrix_header\n";
        
        while (<$fh>) {
            if (/^\#/) { next; }
            chomp;
            my $line = $_;

            
            my @x = split(/\t/);
            my $log_fold_change = $x[$log2FC_index];
            my $fdr = $x[$pvalue_index];
            my $id = $x[0];
            
            if ($log_fold_change eq "NA") { next; }
            
            
            if ( ($log_fold_change =~ /inf/i || abs($log_fold_change) >= $min_abs_log2_fold_change)
                 &&
                 $fdr <= $max_p_value) {
                
                $count++;
                if ((! $max_DE_per_comparison) || ($max_DE_per_comparison &&  $count < $max_DE_per_comparison)) {
                    
                    $diff_expr{$id} = 1;
                    
                    my $matrix_counts = $read_count_rows_href->{$id} || die "Error, no counts from matrix for $id";
                    
                    print $ofh "$line\t$matrix_counts\n";
                }
            }
        }
        close $fh;
        close $ofh;
    }
    
    return(%diff_expr);
        
}


####
sub parse_column_headers {
    my ($DE_result_file) = @_;

    open (my $fh, $DE_result_file) or die "Error, cannot open file $DE_result_file";
    my $top_line = <$fh>;
    my $second_line = <$fh>;
    close $fh;

    chomp $top_line;
    my @columns = split(/\t/, $top_line);
    
    chomp $second_line;
    my @second_line_columns = split(/\t/, $second_line);
    if (scalar(@columns) == scalar(@second_line_columns) -1) {
        # weird R thing where the header can be off by one due to row.names
        unshift (@columns, "id");
    }
    
    my %indices;
    for (my $i = 0; $i <= $#columns; $i++) {
        $indices{$columns[$i]} = $i;
    }

    return(%indices);
}
    
