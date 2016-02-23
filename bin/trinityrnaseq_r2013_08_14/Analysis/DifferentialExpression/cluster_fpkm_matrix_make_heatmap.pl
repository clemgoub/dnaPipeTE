#!/usr/bin/env perl

use strict;
use warnings;
use Carp;
use Getopt::Long qw(:config no_ignore_case bundling pass_through);
use FindBin;
use File::Basename;

my $min_rowSums = 10;
my $min_colSums = 10;

my $usage = <<__EOUSAGE__;

#################################################################################### 
#
#######################
# Inputs and Outputs: #
#######################
#
#  --matrix <string>        matrix.RAW.normalized.FPKM
#
#  Optional:
#
#  Sample groupings:
#
#  --samples_file <string>     tab-delimited text file indicating biological replicate relationships.
#                                   ex.
#                                        cond_A    cond_A_rep1
#                                        cond_A    cond_A_rep2
#                                        cond_B    cond_B_rep1
#                                        cond_B    cond_B_rep2
#
#
#  --output <string>        prefix for output file (default: "\${matrix_file}.heatmap")
#
#####################
#  Plotting Actions #
#####################
#
#  --compare_replicates        provide scatter, MA, QQ, and correlation plots to compare replicates.
#
#   
#
#  --barplot_sum_counts        generate a barplot that sums frag counts per replicate across all samples.
#
#  --boxplot_log2_dist <float>        generate a boxplot showing the log2 dist of counts where counts < min fpkm
#
#  --sample_cor_matrix         generate a sample correlation matrix plot
#
#  --gene_cor_matrix           generate a gene-level correlation matrix plot
#
#  --indiv_gene_cor <string>   generate a correlation matrix and heatmaps for '--top_cor_gene_count' to specified genes (comma-delimited list)
#      --top_cor_gene_count <int>   default: 20 (requires '--indiv_gene_cor with gene identifier specified')
#
#  --heatmap                   genes vs. samples heatmap plot
#
#  --gene_heatmaps <string>    generate heatmaps for just one or more specified genes
#                              Requires a comma-delimited list of gene identifiers.
#                              Plots one heatmap containing all specified genes, then separate heatmaps for each gene.

#  --prin_comp <int>           generate principal components, include <int> top components in heatmap  
#      --add_prin_comp_heatmaps <int>  draw heatmaps for the top <int> features at each end of the prin. comp. axis.
#                                      (requires '--prin_comp') 
#
########################################################
#  Data transformations, in order of operation below:  #
########################################################
#
#
#  --min_colSums <int>      min number of fragments, default: $min_colSums
#
#  --min_rowSums <int>      min number of fragments, default: $min_rowSums
#
#  --CPM                    convert to counts per million (uses sum of totals before filtering)
#
#  --top_genes <int>        use only the top number of most highly expressed transcripts
#
#  --log2
#
#  --Zscale_columns
#
#  --top_variable_genes <int>      Restrict to the those genes with highest coeff. of variability across samples (use median of replicates)
#
#      --var_gene_method <string>   method for ranking top variable genes ( 'coeffvar|anova', default: 'coeffvar' )
#
#
#  --center_rows            subtract row mean from each data point. (only used under '--heatmap' )
#
#
#########################
#  Clustering methods:  #
#########################
#
#  --gene_dist <string>        Setting used for --heatmap (samples vs. genes)
#                                  Options: euclidean, gene_cor
#                                           maximum, manhattan, canberra, binary, minkowski
#                                  (default: euclidean)  If using 'gene_cor', set method using '--gene_cor' below.
#
#  --gene_clust <string>       ward, single, complete, average, mcquitty, median, centroid (default: complete)
#  --sample_clust <string>     ward, single, complete, average, mcquitty, median, centroid (default: complete)
#
#  --gene_cor <string>             Options: pearson, spearman  (default: pearson)
#  --sample_cor <string>           Options: pearson, spearman  (default: pearson)
#
####################
#  Image settings: #
####################
#
#
#  --pdf_width <int>
#  --pdf_height <int>
#
################
# Misc. params #
################
#
#  --write_intermediate_data_tables         writes out the data table after each transformation.
#
#  --show_pipeline_flowchart                describe order of events and exit.
#
####################################################################################



__EOUSAGE__

    ;


my $matrix_file;
my $output_prefix = "";
my $LOG2_MEDIAN_CENTER = 0;
my $LOG2 = 0;


my $CENTER = 0;
my $CPM = 0;
my $top_genes;

my $top_variable_genes;
my $var_gene_method = "coeffvar";

my $Zscale_columns = 0;

my $gene_dist = "euclidean";
my $gene_clust = "complete";
my $sample_clust = "complete";

my $prin_comp = "";
my $prin_comp_heatmaps = 0;

my $help_flag = 0;

my $pdf_width;
my $pdf_height;


my $samples_file;
my $compare_replicates_flag = 0;

my $write_intermediate_data_tables_flag = 0;

my $barplot_sum_counts_flag = 0;
my $boxplot_log2_dist = 0;
my $sample_cor_matrix_flag = 0;
my $gene_cor_matrix_flag = 0;
my $heatmap_flag = 0;

my $show_pipeline_flowchart = 0;

my $indiv_gene_cor;
my $top_cor_gene_count = 20;

my $gene_cor = 'pearson';
my $sample_cor = 'pearson';

my $gene_heatmaps;


&GetOptions (  
    
    ## Inputs and outputs
    'matrix=s' => \$matrix_file,
    'samples_file=s' => \$samples_file, 
    'output=s' => \$output_prefix,

    ## Plotting actions:
    'compare_replicates' => \$compare_replicates_flag,
    'barplot_sum_counts' => \$barplot_sum_counts_flag,
    'boxplot_log2_dist=f' => \$boxplot_log2_dist,
    'sample_cor_matrix' => \$sample_cor_matrix_flag,
    'gene_cor_matrix' => \$gene_cor_matrix_flag,

    'indiv_gene_cor=s' => \$indiv_gene_cor,
    'top_cor_gene_count=i' => \$top_cor_gene_count,

    'heatmap' => \$heatmap_flag,
    'gene_heatmaps=s' => \$gene_heatmaps,
    
    'prin_comp=i' => \$prin_comp,
    'add_prin_comp_heatmaps=i' => \$prin_comp_heatmaps,           
               
    ## Data transformations, in order of operation
    'min_colSums=i' => \$min_colSums,
    'min_rowSums=i' => \$min_rowSums,
    'CPM' => \$CPM,
    'top_genes=i' => \$top_genes,
    'log2' => \$LOG2,
    'Zscale_columns' => \$Zscale_columns,
    'top_variable_genes=i' => \$top_variable_genes,
    'var_gene_method=s' => \$var_gene_method,
    'center_rows' => \$CENTER,
    
    ## Clustering methods:
               
    'gene_dist=s' => \$gene_dist,
    'gene_clust=s' => \$gene_clust,

    'gene_cor=s' => \$gene_cor,
    'sample_cor=s' => \$sample_cor,
    'sample_clust=s' => \$sample_clust,

    ## Image settings:
    'pdf_width=i' => \$pdf_width,
    'pdf_height=i' => \$pdf_height,
    
    
    ## Misc params
    'help|h' => \$help_flag,
    'write_intermediate_data_tables' => \$write_intermediate_data_tables_flag,
    
    'show_pipeline_flowchart' => \$show_pipeline_flowchart,

    );


if (@ARGV) {
    die "Error, don't understand parameters: @ARGV";
}

if ($help_flag) {
    die $usage;
}

if ($show_pipeline_flowchart) {
    &print_pipeline_flowcart();
    exit(1);
}


unless ($matrix_file) {
    die $usage;
}

if (@ARGV) {
    die "Error, do not recognize params: @ARGV ";
}

unless ($output_prefix) {
    $output_prefix = basename($matrix_file) . ".heatmap";
}

if ($var_gene_method && ! $var_gene_method =~ /^(coeffvar|anova)$/) {
    die "Error, do not recognize var_gene_method: $var_gene_method ";
}

main: {
    
    
    my $R_script_file = "$output_prefix.R";
        
    my $Rscript = "library(cluster)\n";
    $Rscript .= "library(gplots)\n";
    $Rscript .= "library(Biobase)\n";
    $Rscript .= "source(\"$FindBin::Bin/R/heatmap.3.R\")\n";
    $Rscript .= "source(\"$FindBin::Bin/R/misc_rnaseq_funcs.R\")\n";
    $Rscript .= "source(\"$FindBin::Bin/R/pairs3.R\")\n";
    
    $Rscript .= "data = read.table(\"$matrix_file\", header=T, com=\'\', sep=\"\\t\", row.names=1)\n";
    $Rscript .= "data = as.matrix(data)\n";


    if ($samples_file) {

        $Rscript .= "samples_data = read.table(\"$samples_file\", header=F)\n";
        $Rscript .= "sample_types = unique(samples_data[,1])\n";

        $Rscript .= "nsamples = length(sample_types)\n"
            . "sample_colors = rainbow(nsamples)\n"
            . "sample_type_list = list()\n"
            . "for (i in 1:nsamples) {\n"
            . "    samples_want = samples_data[samples_data[,1]==sample_types[i], 2]\n"
            . "    sample_type_list[[sample_types[i]]] = samples_want\n"
            . "}\n";

    }
    
    {
        ## set up the pdf output

        $Rscript .= "pdf(\"$output_prefix.pdf\"";
        if ($pdf_width) {
            $Rscript .= ", width=$pdf_width";
        }
        if ($pdf_height) {
            $Rscript .= ", height=$pdf_height";
        }
        
        $Rscript .= ")\n";
    }
    
    my $out_table = "$output_prefix";

    if ($barplot_sum_counts_flag) {

        $Rscript .= "op <- par(mar = c(10,10,10,10))\n"; 
        
        # raw frag conts
        $Rscript .= "barplot(colSums(data), las=2, main=paste(\"Sums of Frags\"), ylab='', cex.names=0.7)\n";
        
        $Rscript .= "par(op)\n";
   
    }

    if ($boxplot_log2_dist) {

        $Rscript .= "boxplot_data = data\n"
                 #.  "boxplot_data = apply(boxplot_data, 1:2, function(x) ifelse (x < $boxplot_log2_dist, NA, x))\n"
                 .  "boxplot_data[boxplot_data<$boxplot_log2_dist] = NA\n"
                 .  "boxplot_data = log2(boxplot_data+1)\n"
                 .  "num_data_points = apply(boxplot_data, 2, function(x) sum(! is.na(x)))\n"
                 .  "num_features_per_boxplot = 50\n"
                 .  "for(i in 1:ceiling(ncol(boxplot_data)/num_features_per_boxplot)) {\n"
                 .  "    from = (i-1)*num_features_per_boxplot+1; to = min(from+num_features_per_boxplot-1, ncol(boxplot_data));\n"
                 .  "    op <- par(mar = c(0,4,2,2), mfrow=c(2,1))\n"
                 .  "    boxplot(boxplot_data[,from:to], outline=F, main=paste('boxplot log2 <', $boxplot_log2_dist, ', reps:', from, '-', to), xaxt='n')\n"
                 .  "    par(mar = c(7,4,2,2))\n"
                 .  "    barplot(num_data_points[from:to], las=2, main=paste('Count of features < ', $boxplot_log2_dist, ', reps:', from, '-', to), cex.names=0.7)\n"
                 .  "    par(op)\n"
                 .  "}\n";
                     
    }
    

    if ($min_colSums > 0) {
        $Rscript .= "data = data\[,colSums\(data)>=" . $min_colSums . "]\n";
        $out_table .= ".minCol$min_colSums";
        $Rscript .= "write.table(data, file=\"$out_table.dat\", quote=F, sep=\"\t\")\n" if $write_intermediate_data_tables_flag;
    }
        
    if ($min_rowSums > 0) {
        $Rscript .= "data = data\[rowSums\(data)>=" . $min_rowSums . ",]\n";
        $out_table .= ".minRow$min_rowSums";
        $Rscript .= "write.table(data, file=\"$out_table.dat\", quote=F, sep=\"\t\")\n" if $write_intermediate_data_tables_flag;
    }
    

    if ($CPM) {

        $Rscript .= "cs = colSums(data)\n";
        $Rscript .= "data = t( t(data)/cs) * 1e6;\n";
        $out_table .= ".CPM";
        
    }
    
    if ($LOG2) {
        $Rscript .= "data = log2(data+1)\n";
        $out_table .= ".log2";
        $Rscript .= "write.table(data, file=\"$out_table.dat\", quote=F, sep=\"\t\")\n" if $write_intermediate_data_tables_flag;
    }
    
    if ($Zscale_columns) {
        $Rscript .= "for (i in 1:ncol(data)) {\n";
        $Rscript .= "    d = data[,i]\n";
        $Rscript .= "    q = quantile(d[d>0], c(0.15, 0.85))\n";
        $Rscript .= "    d2 = d[ d>=q[1] & d<=q[2] ]\n";
        $Rscript .= "    d2_mean = mean(d2)\n";
        $Rscript .= "    d = d - d2_mean\n";
        $Rscript .= "    d = d / sd(d2)\n";
        $Rscript .= "    data[,i] = d\n";
        $Rscript .= "}\n\n";
        
        $out_table .= ".Zscale";
        $Rscript .= "write.table(data, file=\"$out_table.dat\", quote=F, sep=\"\t\")\n" if $write_intermediate_data_tables_flag;
    }
    

    ## sample factoring
    $Rscript .= "sample_factoring = colnames(data)\n";
    
    if ($samples_file) {
        # sample factoring
        $Rscript .= "for (i in 1:nsamples) {\n"
                 .  "    sample_type = sample_types[i]\n"
                 .  "    replicates_want = sample_type_list[[sample_type]]\n"
                 .  "    sample_factoring[ colnames(data) \%in% replicates_want ] = sample_type\n"
                 .  "}\n";
    


        # generate the sample color-identification matrix
        $Rscript .= "sampleAnnotations = matrix(ncol=ncol(data),nrow=nsamples)\n";
        
        $Rscript .= "for (i in 1:nsamples) {\n"
                 .  "  sampleAnnotations[i,] = colnames(data) %in% sample_type_list[[sample_types[i]]]\n"
                 . "}\n";
        
        $Rscript .= "sampleAnnotations = apply(sampleAnnotations, 1:2, function(x) as.logical(x))\n";
        $Rscript .= "sampleAnnotations = sample_matrix_to_color_assignments(sampleAnnotations)\n";
        $Rscript .= "rownames(sampleAnnotations) = as.vector(sample_types)\n";
        $Rscript .= "colnames(sampleAnnotations) = colnames(data)\n";
        
    }
    
    
    if ($top_genes) {
        $Rscript .= "o = rev(order(rowSums(data)))\n";
        $Rscript .= "o = o[1:min($top_genes,length(o))]\n";
        $Rscript .= "data = data[o,]\n";
        # some columns might now have zero sums, remove those
        $Rscript .= "data = data[,colSums(data)>0]\n";
        $out_table .= ".top_${top_genes}";
        $Rscript .= "write.table(data, file=\"$out_table.dat\", quote=F, sep=\"\t\")\n" if $write_intermediate_data_tables_flag;
    }
    
    $Rscript .= "data = as.matrix(data) # convert to matrix\n";
        
        ;

    
    if ($top_variable_genes) {
        $Rscript .= &get_top_most_variable_features($top_variable_genes, $out_table, $samples_file, $var_gene_method);
        # note 'data' gets subsetted by rows (features) found most variable across samples.
        
        # some columns might now have zero sums, remove those
        $Rscript .= "data = data[,colSums(data)>0]\n";
        
        $out_table .= ".top_${top_variable_genes}_variable";
        $Rscript .= "write.table(data, file=\"$out_table.dat\", quote=F, sep=\"\t\")\n" if $write_intermediate_data_tables_flag;
        
    }
        
    if ($samples_file) {
        
    
        if ($compare_replicates_flag) {
            $Rscript .= &add_sample_QC_analysis_R();
        }
    }
    
        
    ## write modified data
    $Rscript .= "write.table(data, file=\"$out_table.dat\", quote=F, sep='\t');\n";


    if ($sample_cor_matrix_flag || $heatmap_flag || $gene_cor_matrix_flag) {
        $Rscript .= "sample_cor = cor(data, method=\'$sample_cor\')\n";
        $Rscript .= "hc_samples = hclust(as.dist(1-sample_cor), method=\"$sample_clust\") # cluster conditions\n";
    }
    
    
    if ($sample_cor_matrix_flag) {
        # sample correlation matrix
        
        $Rscript .= "heatmap.3(sample_cor, dendrogram='both', Rowv=as.dendrogram(hc_samples), Colv=as.dendrogram(hc_samples), col = greenred(75), scale='none', symm=TRUE, key=TRUE,density.info='none', trace='none', symkey=FALSE, margins=c(10,10), cexCol=1, cexRow=1, cex.main=0.75, main=paste(\"sample correlation matrix\n\", \"$out_table\"), side.height.fraction=0.2 ";
        
        if ($samples_file) {
            $Rscript .= ", ColSideColors=sampleAnnotations, RowSideColors=t(sampleAnnotations)";
        }
        
        $Rscript .= ")\n";
    }
    
    if ($prin_comp) {
        
        $Rscript .= "pc = princomp(data, cor=TRUE)\n";
        $Rscript .= "pc_pct_variance = (pc\$sdev^2)/sum(pc\$sdev^2)\n";
        $Rscript .= "def.par <- par(no.readonly = TRUE) # save default, for resetting...\n"
            .  "gridlayout = matrix(c(1:4),nrow=2,ncol=2, byrow=TRUE);\n"
            .  "layout(gridlayout, widths=c(1,1));\n";
        


        if ($samples_file) {

            $Rscript .= "for (i in 1:(max($prin_comp,2)-1)) {\n" # one plot for each n,n+1 component comparison.
                      . "    xrange = range(pc\$loadings[,i])\n"
                      . "    yrange = range(pc\$loadings[,i+1])\n"
                      . "    samples_want = rownames(pc\$loadings) \%in\% sample_type_list[[sample_types[1]]]\n"
                      . "    pc_i_pct_var = sprintf(\"(%.2f%%)\", pc_pct_variance[i]*100)\n"
                      . "    pc_i_1_pct_var = sprintf(\"(%.2f%%)\", pc_pct_variance[i+1]*100)\n"
                      . "    plot(pc\$loadings[samples_want,i], pc\$loadings[samples_want,i+1], xlab=paste('PC',i, pc_i_pct_var), ylab=paste('PC',i+1, pc_i_1_pct_var), xlim=xrange, ylim=yrange, col=sample_colors[1])\n"
                      . "    for (j in 2:nsamples) {\n"
                      . "        samples_want = rownames(pc\$loadings) \%in\% sample_type_list[[sample_types[j]]]\n"
                      . "        points(pc\$loadings[samples_want,i], pc\$loadings[samples_want,i+1], col=sample_colors[j], pch=j)\n"
                      . "    }\n"
                      . "    plot.new()\n"
                      . "    legend('topleft', as.vector(sample_types), col=sample_colors, pch=1:nsamples, ncol=2)\n"
                      . "}\n\n";
        }
        else {
            $Rscript .= "for (i in 1:($prin_comp-1)) {\n"
                      . "    pc_i_pct_var = sprintf(\"(%.2f%%)\", pc_pct_variance[i]*100)\n"
                      . "    pc_i_1_pct_var = sprintf(\"(%.2f%%)\", pc_pct_variance[i+1]*100)\n"
                      .  "   plot(pc\$loadings[,i], pc\$loadings[,i+1], xlab=paste('PC', i, pc_i_pct_var), ylab=paste('PC', i+1, pc_i_pct_var))\n"
                      .  "   plot.new()\n"
                      .  "}\n";
            
        }
        $Rscript .= "par(def.par)\n"; # reset
        
        #$Rscript .= "dev.off();stop('debug')\n";
        
        $Rscript .= "pcscore_mat_vals = pc\$scores[,1:$prin_comp]\n";
        $Rscript .= "pcscore_mat = matrix_to_color_assignments(pcscore_mat_vals, col=colorpanel(256,'purple','black','yellow'), by='row')\n";
        $Rscript .= "colnames(pcscore_mat) = paste('PC', 1:ncol(pcscore_mat))\n"; 
        
        if ($prin_comp_heatmaps) {
            
            $Rscript .= &add_prin_comp_heatmaps($prin_comp_heatmaps);
            
        }
        
    }
    
    $Rscript .= "gene_cor = NULL\n";

    if ($gene_cor_matrix_flag) {
        # gene correlation matrix
        
        {
            $Rscript .= "if (is.null(gene_cor)) \n"
                     . "     gene_cor = cor(t(data), method=\'$gene_cor\')\n";
                        
            $Rscript .= "heatmap.3(gene_cor, dendrogram='both', Rowv=as.dendrogram(hc_genes), Colv=as.dendrogram(hc_genes), col=colorpanel(256,'purple','black','yellow'), scale='none', symm=TRUE, key=TRUE,density.info='none', trace='none', symkey=FALSE, margins=c(10,10), cexCol=1, cexRow=1, cex.main=0.75, main=paste(\"feature correlation matrix\n\", \"$out_table\", side.height.fraction=0.2 ) ";
            if ($prin_comp) {
                
                $Rscript .= ", RowSideColors=pcscore_mat, ColSideColors=t(pcscore_mat)";
                
            }
            $Rscript .= ")\n";
            
        }
    }
    

    if ($indiv_gene_cor) {
        
        $Rscript .= "if (is.null(gene_cor)) \n"
                 .  "     gene_cor = cor(t(data), method=\'$gene_cor\')\n";
        
        my @indiv_genes = split(/,/, $indiv_gene_cor);
        foreach my $indiv_gene (@indiv_genes) {

            $Rscript .= &study_individual_gene_correlations($indiv_gene, $top_cor_gene_count);
            #last;
        }
    }

    if ($gene_heatmaps) {
        
        my @indiv_genes = split(/,/, $gene_heatmaps);
        $Rscript .= &gene_heatmaps(@indiv_genes);
        
        if (scalar @indiv_genes > 1) {
            
            foreach my $indiv_gene (@indiv_genes) {
                $Rscript .= &gene_heatmaps($indiv_gene);
            }
        }
    }
    
    

    if ($heatmap_flag) {
        
        ## generate Gene-level correlation matrix        
        if ($gene_dist =~ /gene_cor/) {
            
            $Rscript .= "if (is.null(gene_cor)) { gene_cor = cor(t(data), method=\'$gene_cor\') }\n";
                    
            $Rscript .= "gene_dist = as.dist(1-gene_cor)\n";
        }
        else {
            $Rscript .= "gene_dist = dist(data, method=\'$gene_dist\')\n";
        }
        
        $Rscript .= "hc_genes = hclust(gene_dist, method=\'$gene_clust\')\n";
        
        
        if ($CENTER) {
            $Rscript .= "myheatcol = greenred(75)\n";
            
            $Rscript .= "data = t(scale(t(data), scale=F)) # center rows, mean substracted\n";
            ;
            $out_table .= ".centered";
            
            $Rscript .= "write.table(data, file=\"$out_table.dat\", quote=F, sep='\t');\n";
            
        }
        else {
            ## use single gradient
            $Rscript .= "myheatcol = colorpanel(75, 'black', 'red')\n";
        }
        
                
        # sample vs. gene heatmap
        
        {
            $Rscript .= "heatmap.3(data, dendrogram='both', Rowv=as.dendrogram(hc_genes), Colv=as.dendrogram(hc_samples), col=myheatcol, scale=\"none\", density.info=\"none\", trace=\"none\", key=TRUE, keysize=1.2, cexCol=1, margins=c(12,5), cex.main=0.75, main=paste(\"samples vs. features\n\", \"$out_table\", side.height.fraction=.2 ) ";
            if ($prin_comp) {
                $Rscript .= ", RowSideColors=pcscore_mat";
            }
            if ($samples_file) {
                $Rscript .= ", ColSideColors=sampleAnnotations";
            }
            $Rscript .= ")\n";
        }
        
    } # end of sample vs. genes heatmap
    
    
    $Rscript .= "save(list=ls(all=TRUE), file=\"$output_prefix.RData\")\n";

    $Rscript .= "dev.off()\n";
    
        
    open (my $ofh, ">$R_script_file") or die "Error, cannot write to $R_script_file";    
    print $ofh $Rscript;
    close $ofh;
    
    &process_cmd("R --vanilla -q < $R_script_file");


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

####
sub add_sample_QC_analysis_R {
    
    my $Rscript = "MA_plot = function(x, y, ...) {\n"
                #. "    print(x); print(y);\n"
                . "    M = log( (exp(x) + exp(y)) / 2)\n"
                . "    A = x - y;\n"
                . "    res = list(x=M, y=A)\n"
                . "    return(res)\n"
                . "}\n";
    
    $Rscript .= "MA_color_fun = function(x,y) {\n"
             .  "    col = sapply(y, function(y) ifelse(abs(y) >= 1, 'red', 'black')) # color 2-fold diffs\n" 
             .  "    return(col)\n"
             .  "}\n";

    $Rscript .= "Scatter_color_fun = function(x,y) {\n"
             .  "    col = sapply(abs(x-y), function(z) ifelse(z >= 1, 'red', 'black')) # color 2-fold diffs\n"
             #.  "    print(col)\n"
             .  "    return(col)\n"
             .  "}\n";


       $Rscript .= "for (i in 1:nsamples) {\n"
                . "    sample_name = sample_types[[i]]\n"
                #. "    print(sample_name)\n"
                . "    samples_want = sample_type_list[[sample_name]]\n"
                #. "    print(samples_want)\n"
                . "    samples_want = colnames(data) \%in% samples_want\n"
                #. "    print(samples_want)\n"
                
                . "    if (sum(samples_want) > 1) {\n"
                . "        d = data[,samples_want]\n"
                . "        op <- par(mar = c(10,10,10,10))\n";

    if ($LOG2) {
        $Rscript .= "        barplot(colSums(2^(d-1)), las=2, main=paste(\"Sum of Frags for replicates of:\", sample_name), ylab='', cex.names=0.7)\n";
    }
    else {
        
        $Rscript .= "        barplot(colSums(d), las=2, main=paste(\"Sum of Frags for replicates of:\", sample_name), ylab='', cex.names=0.7)\n"
    }
    
    $Rscript  .= "        par(op)\n"
                . "        pairs3(d, pch='.', CustomColorFun=Scatter_color_fun, main=paste('Replicate Scatter:', sample_name)) # scatter plots\n"
                . "        pairs3(d, XY_convert_fun=MA_plot, CustomColorFun=MA_color_fun, pch='.', main=paste('Replicate MA:', sample_name)); # MA plots\n"
                . "        pairs3(d, XY_convert_fun=function(x,y) qqplot(x,y,plot.it=F), main=paste('Replicate QQplots:', sample_name)) # QQ plots\n" 
                . "        reps_cor = cor(d, method=\"spearman\")\n"
                . "        hc_samples = hclust(as.dist(1-reps_cor), method=\"complete\")\n"
                . "        heatmap.3(reps_cor, dendrogram='both', Rowv=as.dendrogram(hc_samples), Colv=as.dendrogram(hc_samples), col = cm.colors(256), scale='none', symm=TRUE, key=TRUE,density.info='none', trace='none', symbreaks=F, margins=c(10,10), cexCol=1, cexRow=1, main=paste('Replicate Correlations:', sample_name), side.height.fraction=0.2 )\n"
                . "    }\n"
                . "}\n";
    
    return($Rscript);
}

####
sub get_top_most_variable_features {
    my ($top_variable_genes, $out_table, $samples_file, $method) = @_;
    

    my $Rscript = "";
    
    if ($method eq "coeffvar") {
        $Rscript = &get_top_var_features_via_coeffvar($top_variable_genes, $out_table, $samples_file);
        
    }
    elsif ($method eq "anova") {
        $Rscript = &get_top_var_features_via_anova($top_variable_genes, $out_table, $samples_file);

    }
    else {
        confess "Error, get top var features for method: $method is not implemented";
    }
    

    return($Rscript);
}


####
sub get_top_var_features_via_anova {
    my ($top_variable_genes, $out_table, $samples_file) = @_;

    my $Rscript = "";
    
    if (! $samples_file) {
        $Rscript .= "print('WARNING: samples not grouped according to --samples_file, each column is treated as a different sample')\n";
    }
    
    $Rscript .= "anova_pvals = c()\n";

    $Rscript .= "for (j in 1:nrow(data)) {\n"
             .  "    feature_vals = data[j,]\n"
             .  "    data_for_anova = data.frame(y=feature_vals, group=factor(sample_factoring))\n"
             .  "    fit = lm(y ~ group, data_for_anova)\n"
             .  "    a = anova(fit)\n"
             .  "    p = a\$\"Pr(>F)\"[1]\n"
             .  "    anova_pvals[j] = p\n"
             #.  "    print(a)\n"
             .  "}\n";

    ## restrict to those with most significant P-values
    $Rscript .= "anova_ranking = order(anova_pvals)\n"
             .  "data = data[anova_ranking[1:$top_variable_genes],] # restrict to $top_variable_genes with anova sig P-value ranking\n";
    
    return($Rscript);
}




####
sub get_top_var_features_via_coeffvar {
    my ($top_variable_genes, $out_table, $samples_file) = @_;
    

    my $Rscript = "";

    if ($samples_file) {
        $Rscript .= "sample_medians_df = data.frame(row.names=rownames(data))\n"
                 .  "print(paste('colnames of data frame:', colnames(data)))\n"
                 .  "for (i in 1:nsamples) {\n"
                 .  "    sample_type = sample_types[i]\n"
                 .  "    print(sample_type)\n"
                 .  "    replicates_want = sample_type_list[[sample_type]]\n"
                 #.  "    print(paste('replicates wanted: ' , replicates_want))\n"
                 .  "    data_subset = as.data.frame(data[, colnames(data) \%in% replicates_want])\n"
                 .  "    print(paste('ncol(data_subset):', ncol(data_subset)))\n"
                 .  "    if (ncol(data_subset) >= 1) {\n"
                 .  "        sample_median_vals = apply(data_subset, 1, median)\n"
                 .  "        print(paste('Sample name: ', sample_type))\n"
                 #.  "        print(sample_median_vals)\n"
                 .  "        sample_medians_df[,toString(sample_type)] = sample_median_vals\n"
                 .  "    }\n"
                 .  "}\n"
                 .  "write.table(sample_medians_df, file=\"$out_table.sample_medians.dat\", quote=F, sep=\"\t\")\n";
    }
    else {
        $Rscript .= "sample_medians_df = data\n";
    }

    $Rscript .= "coeff_of_var_fun = function(x) ( sd(x+1)/mean(x+1) ) # adding a pseudocount\n"
             .  "gene_coeff_of_var = apply(sample_medians_df, 1, coeff_of_var_fun)\n"
             .  "gene_order_by_coeff_of_var_desc = rev(order(gene_coeff_of_var))\n"
             .  "gene_coeff_of_var = gene_coeff_of_var[gene_order_by_coeff_of_var_desc]\n"
             .  "write.table(gene_coeff_of_var, file=\"$out_table.sample_medians.coeff_of_var.dat\", quote=F, sep=\"\t\")\n"
             .  "data = data[gene_order_by_coeff_of_var_desc[1:$top_variable_genes],]\n";
    
    
    

    return($Rscript);
}

####
sub add_prin_comp_heatmaps {
    my ($num_top_genes_PC_extreme) = @_;

    my $Rscript = "## generate heatmaps for PC extreme vals\n"
                . "for (i in 1:$prin_comp) {\n"
                . "    ## get genes with extreme vals\n"
                . "    print(paste('range', range(pc\$scores[,i])))\n"
                . "    ordered_gene_indices = order(pc\$scores[,i])\n"
                . "    num_genes = length(ordered_gene_indices)\n"
                . "    extreme_ordered_gene_indices = c(1:$num_top_genes_PC_extreme, (num_genes-$num_top_genes_PC_extreme):num_genes)\n"
                . "    print(extreme_ordered_gene_indices)\n"
                . "    selected_gene_indices = ordered_gene_indices[extreme_ordered_gene_indices]\n"
                . "    print('selected gene indices');print(selected_gene_indices);\n"
                . "    print('PC scores:');print(pc\$scores[selected_gene_indices,i])\n"
                . "    selected_genes_matrix = data[selected_gene_indices,]\n"
                #. "    print(selected_genes_matrix)\n"
                . "    pc_color_bar_vals = pcscore_mat_vals[selected_gene_indices,i]\n"
                . "    print(pc_color_bar_vals)\n"
                . "    pc_color_bar = as.matrix(pcscore_mat[selected_gene_indices,i])\n";

    if (! $LOG2) {
        $Rscript .= "    selected_genes_matrix = log2(selected_genes_matrix+1)\n";
    }
    if ($CENTER) {
        $Rscript .= "    selected_genes_matrix = t(scale(t(selected_genes_matrix), scale=F))\n";
    }
    
    
    $Rscript .= "    heatmap.3(selected_genes_matrix, col=greenred(256), scale='none', density.info=\"none\", trace=\"none\", key=TRUE, keysize=1.2, cexCol=1, margins=c(12,5), cex.main=0.75, side.height.fraction=0.2, RowSideColors=pc_color_bar, cexRow=0.5, main=paste('heatmap for', $num_top_genes_PC_extreme, ' extreme of PC', i)";

    if ($samples_file) {
        $Rscript .= ", ColSideColors=sampleAnnotations";
    }
    $Rscript .= ")\n";
    $Rscript .= "}\n";
    
    return($Rscript);
}


####
sub print_pipeline_flowchart {
    
    print <<__EOTEXT__;

    Start.

    read data table
    read samples file (optional)

    ? plots: barplots for sum counts per replicate
    ? plots: boxplots for feature count distribution and barplots for number of features mapped.
    
    ? filter: min column sums
    ? filter: min row sums
    
    ? data_transformation: CPM
    ? data_transformation: log2
    ? data_transformation:  Z-scaling

    ? data_annotation: sample factoring
    ? data_annotation: sample coloring setup

    ? filter: top expressed genes
    ? filter: top variable genes (coeffvar|anova)

    ? plots: sample replicate comparisons

    ? output: resulting data table post-filtering and data transformations.

    ? plots: sample correlation matrix
    
    ? plots: principal components analysis
    ?       plots: heatmaps for features assigned extreme values in PCA

    ? plots: feature/gene correlation matrix

    ? plots: individual gene correlation plots and heatmaps

    ? plots: samples vs. features matrix

    End.

    
__EOTEXT__

    ;

    return;
}


####
sub study_individual_gene_correlations {
    my ($gene_id, $top_cor_genes) = @_;

    my $Rscript .= "if (! \"$gene_id\" \%in% colnames(gene_cor)) {\n"
             .  "      print(\"WARNING, $gene_id not included in correlation matrix, skipping...\")\n"
             .  "} else {\n"
             .  "    this_gene_cor = as.vector(gene_cor[\"$gene_id\",])\n"
             .  "    names(this_gene_cor) = colnames(gene_cor)\n"
             .  "    top_cor_gene_indices = rev(order(this_gene_cor))\n"
             .  "    top_cor_gene_names = names(this_gene_cor[top_cor_gene_indices])[1:$top_cor_genes]\n"
             .  "    this_gene_cor_matrix = gene_cor[top_cor_gene_names, top_cor_gene_names]\n";
    
    $Rscript .= "    gene_expr_submatrix = data[top_cor_gene_names,]\n";
    if (! $LOG2) {
        $Rscript .= "    gene_expr_submatrix = log2(gene_expr_submatrix+1)\n";
    }
    
    ## remove those samples summing to zero
    $Rscript .= "    gene_expr_submatrix = gene_expr_submatrix[,colSums(gene_expr_submatrix) > 0]\n";
    if ($samples_file) {
        ## adjust for possibly having removed some columns
        $Rscript .= "    these_sample_annotations = sampleAnnotations[,colnames(gene_expr_submatrix)]\n";
    }
    
    # gene correlation plot
    $Rscript .= "    this_gene_dist = as.dist(1-this_gene_cor_matrix)\n"
             .  "    this_hc_genes = hclust(this_gene_dist, method=\"$gene_clust\")\n";

    $Rscript .= "    this_sample_cor = cor(gene_expr_submatrix, method=\"$sample_cor\")\n"
             .  "    this_hc_samples = hclust(as.dist(1-this_sample_cor), method=\"$sample_clust\")\n";

    $Rscript .= "    heatmap.3(this_gene_cor_matrix, dendrogram='both', Rowv=as.dendrogram(this_hc_genes), Colv=as.dendrogram(this_hc_genes), col=colorpanel(256,'purple','black','yellow'), scale='none', symm=TRUE, key=TRUE,density.info='none', trace='none', symkey=FALSE, margins=c(10,10), cexCol=1, cexRow=1, cex.main=0.75, main=\"feature correlation matrix\n$gene_id\")\n";

    # gene vs. samples plot

    # center rows
    $Rscript .= "    gene_expr_submatrix = t(scale(t(gene_expr_submatrix), scale=F))\n";
    
    
    $Rscript .= "    heatmap.3(gene_expr_submatrix, col=greenred(256), Rowv=as.dendrogram(this_hc_genes), Colv=as.dendrogram(this_hc_samples), scale='none', density.info=\"none\", trace=\"none\", key=TRUE, keysize=1.2, cexCol=1, margins=c(12,5), cex.main=0.75, side.height.fraction=0.2, cexRow=0.5, main=paste('heatmap for', $top_cor_genes, 'most correlated to', \"$gene_id\")";

    if ($samples_file) {
        $Rscript .= ", ColSideColors=these_sample_annotations";
    }
    
    $Rscript .= ")\n";
    
    $Rscript .= "}\n\n";
    
    return($Rscript);
}

####
sub gene_heatmaps {
    my (@gene_ids) = @_;

    my $Rscript = "gene_list = c(\"" . join("\",\"", @gene_ids) . "\")\n";

    $Rscript .= "gene_submatrix = data[gene_list, ,drop=F]\n";

    if ($CENTER) {
        $Rscript .= "gene_submatrix = t(scale(t(gene_submatrix), scale=F))\n";
    }
    if ($samples_file) {
        $Rscript .= "gene_submatrix = gene_submatrix[,order(sample_factoring),drop=F]\n";
        $Rscript .= "coloring_by_sample = sampleAnnotations[,order(sample_factoring),drop=F]\n";
    }
    if (scalar(@gene_ids) == 1) {
        ## matrix must have multiple rows.  Just duplicate the last row
        $Rscript .= "gene_submatrix = rbind(gene_submatrix, gene_submatrix[1,])\n";
    }
    
    my $col = "greenred(75)";
    if ($CENTER) {
        $col = "colorpanel(75, 'black', 'red')";
    }

    
    $Rscript .= "heatmap.3(gene_submatrix, dendrogram='none', Rowv=F, Colv=F, col=$col, main='without clustering'";
    
    if ($samples_file) {
        $Rscript .= ", ColSideColors=coloring_by_sample";
    }
    
    $Rscript .= ")\n";

    { 
        ## Do it again and cluster too
    
        $Rscript .= "heatmap.3(gene_submatrix, col=$col, main='with clustering'";
        
        if ($samples_file) {
            $Rscript .= ", ColSideColors=coloring_by_sample";
        }
        
        $Rscript .= ")\n";
    }


    return($Rscript);
}
    
