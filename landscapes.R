#!/usr/bin/Rscript

library(ggplot2)

#read the table with reads and identity selected for landscape analysis
Args = commandArgs()

file1 = Args[6]
file2 = Args[7]
file3 = Args[8]

land = read.table(file1)
ttl = read.table(file3)
ttl = ttl[1]

#read.table("reads_landscape")->land
names(land)=c("id", "annot", "fam1", "fam")
land$div=100-land$id

#read the corresponding factor order and color table
fac_col = read.table(file2)

#print(head(land))
#print(fac_col)

#order factors and colors
land$fam1=factor(land$fam1, levels=as.character(fac_col$V1))
#print(as.numeric(ttl))

#plot the landscape graph
ggplot(land, aes(div, fill=fam1))+geom_histogram(binwidth=1.1)+labs(list(x="Divergence from dnaPipeTE contig (%)", y="Genome percent"))+coord_cartesian(xlim = c(0, 35))+scale_fill_manual(values=as.character(fac_col$V3))+guides(fill=guide_legend(ncol=3))+theme(legend.direction ="vertical",legend.position = "bottom")+scale_y_continuous(labels=function(x)signif(x/as.numeric(ttl)*100, 3))
ggsave("landscape.pdf", height=12, width=6)
