#!/usr/bin/env perl

use strict;
use warnings;
use Carp;
use Getopt::Long qw(:config no_ignore_case bundling);
use File::Basename;
use FindBin;

my $usage = <<__EOUSAGE__;

###################################################################################
#
# -K <int>          define K clusters via k-means algorithm
#
#  or, cut the hierarchical tree:
#
# --Ktree <int>     cut tree into K clusters
#
# --Ptree <float>   cut tree based on this percent of max(height) of tree 
#
# -R <string>  the filename for the store RData (file.all.RData)
#
###################################################################################


__EOUSAGE__

    ;


my $Kmeans;
my $Ktree;
my $help_flag = 0;
my $R_data_file;
my $pct_height = 0;

&GetOptions ( 'h' => \$help_flag,
              'K=i' => \$Kmeans,
              'Ktree=i' => \$Ktree,
              'Ptree=f' => \$pct_height,
              'R=s' => \$R_data_file,
              );


if ($help_flag) {
    die $usage;
}

unless (($Kmeans || $Ktree || $pct_height) && $R_data_file) {
    die $usage;
}

if ($pct_height && $pct_height < 1) {
    die "Error, specify --Ptree as percent value > 1\n\n";
}

main: {
    
    unless (-s $R_data_file) {
        die "Error, cannot find pre-existing R-session data as file: $R_data_file";
    }
    
    
    my $R_script = "__tmp_define_clusters.R";
    
    open (my $ofh, ">$R_script") or die "Error, cannot write to file $R_script";

    print $ofh "library(cluster)\n";
    print $ofh "library(gplots)\n";
    print $ofh "library(Biobase)\n";
    
    
    print $ofh "load(\"$R_data_file\")\n";
    
    
    my $core_filename;
    my $outdir;
    
    if ($Kmeans) {
        print $ofh "kmeans_clustering <- kmeans(data, centers=$Kmeans, iter.max=100, nstart=5)\n";
        $core_filename = "clusters_fixed_Kmeans_${Kmeans}.heatmap";
        $outdir = basename($R_data_file) . ".clusters_fixed_Kmeans_" . $Kmeans;
        print $ofh "gene_partition_assignments = kmeans_clustering\$cluster\n";
        
    }
    elsif ($Ktree) {
        print $ofh "gene_partition_assignments <- cutree(as.hclust(hc_genes), k=$Ktree)\n";
        $core_filename = "clusters_fixed_Ktree_${Ktree}.heatmap";
        $outdir = basename($R_data_file) . ".clusters_fixed_Ktree_" . $Ktree;
        
    } 
    else {
        print $ofh "gene_partition_assignments <- cutree(as.hclust(hc_genes), h=$pct_height/100*max(hc_genes\$height))\n";
        $core_filename = "clusters_fixed_P_${pct_height}.heatmap";
        $outdir = basename($R_data_file) . ".clusters_fixed_P_" . $pct_height;
        
    }
    print $ofh "max_cluster_count = max(gene_partition_assignments)\n";
    
    print $ofh "outdir = \"" . $outdir . "\"\n";
    print $ofh "dir.create(outdir)\n";
    
    # make another heatmap:
    print $ofh "partition_colors = rainbow(length(unique(gene_partition_assignments)), start=0.4, end=0.95)\n";
    print $ofh "gene_colors = partition_colors[gene_partition_assignments]\n";
    #print $ofh "postscript(file=\"$core_fileanme.heatmap.eps\", horizontal=FALSE, width=8, height=18, paper=\"special\");\n";
    print $ofh "pdf(\"$core_filename.heatmap.pdf\")\n";
    #print $ofh "heatmap.2(data, dendrogram='both', Rowv=as.dendrogram(hc_genes), Colv=as.dendrogram(hc_samples), col=myheatcol, RowSideColors=gene_colors, scale=\"none\", density.info=\"none\", trace=\"none\", key=TRUE, keysize=1.2, cexCol=2.5, margins=c(15,15), lhei=c(0.3,2), lwid=c(2.5,4))\n";
print $ofh "heatmap.2(data, dendrogram='both', Rowv=as.dendrogram(hc_genes), Colv=as.dendrogram(hc_samples), col=myheatcol, RowSideColors=gene_colors, scale=\"none\", density.info=\"none\", trace=\"none\", key=TRUE, cexCol=1, lmat=rbind(c(5,0,4,0),c(3,1,2,0)), lhei=c(1.5,5),lwid=c(1.5,0.2,2.5,2.5), margins=c(12,5))\n";
    print $ofh "dev.off()\n";
    
    print $ofh "gene_names = rownames(data)\n";
    print $ofh "num_cols = length(data[1,])\n";
    
    
    print $ofh "for (i in 1:max_cluster_count) {\n";
    print $ofh "    partition_i = (gene_partition_assignments == i)\n";
    
    print $ofh "    partition_data = data[partition_i,]\n";
    
    print $ofh "    # if the partition involves only one row, then it returns a vector instead of a table\n";
        ;
    print $ofh "    if (sum(partition_i) == 1) {\n";
    print $ofh "          dim(partition_data) = c(1,num_cols)\n";
    print $ofh "          colnames(partition_data) = colnames(data)\n";
    print $ofh "          rownames(partition_data) = gene_names[partition_i]\n";
    print $ofh "    }\n";
    
    
    print $ofh "    outfile = paste(outdir, \"/subcluster_\", i, \"_log2_medianCentered_fpkm.matrix\", sep='')\n";
    print $ofh "    write.table(partition_data, file=outfile, quote=F, sep=\"\\t\")\n";
    print $ofh "}\n";
    

    close $ofh;


    &process_cmd("R --vanilla -q < $R_script");

    
    ###################################################
    ## Generate the expression plots for each cluster
    ###################################################

    chdir $outdir or die "Error, cannot cd into $outdir";
    
    my $cmd = "$FindBin::Bin/plot_expression_patterns.pl subcluster\*fpkm.matrix";
    &process_cmd($cmd);
    
    


    exit(0);
    

}


####
sub process_cmd {
    my ($cmd) = @_;

    print STDERR "CMD: $cmd\n";
    my $ret = system($cmd);
    if ($ret) {
        die "Error, cmd $cmd died with ret $ret";
    }

    return;
}
