#!/usr/bin/Rscript
#############################
# Plot TE classes pie chart #
#############################

Args = commandArgs()
folder = Args[6]
file = Args[7]
counts = read.table(paste(folder,file, sep="/"))
names(counts)=c("class","reads")
Single_or_low_copy=counts$reads[10]-sum(counts$reads[1:9])
perc=signif(c(counts$reads[1:9]/counts$reads[10],Single_or_low_copy/counts$reads[10])*100,3)
#pie(c(counts$reads[1:8],Single_or_low_copy),paste(c(as.character(counts$class[-9]),"Single or low copy DNA"), perc, "%"), col=rainbow(9))
pal=c("#33cc33ff","#6699ffff","#B966F4","salmon","dimgrey","chartreuse","black","gold","#d3d3d3ff")
#pie(c(counts$reads[1:8],Single_or_low_copy),paste(c(as.character(counts$class[-9]),"Single or low copy DNA"), perc, "%"), col=pal)

png(file=paste(folder,"TEs_piechart.png",sep="/"), width=1000, height=600)

pie(c(counts$reads[1:9],Single_or_low_copy),paste(perc, "%"), col=pal, clockwise=T, border="white")
legend(1,0.5,paste(c(as.character(counts$class[-10]),"Single or low copy DNA")),fill=pal)

dev.off()

pdf(file=paste(folder,"TEs_piechart.pdf",sep="/"), width=16, height=10)

pie(c(counts$reads[1:9],Single_or_low_copy),paste(perc, "%"), clockwise=T, col=pal, border="white")
legend(1,0.5,paste(c(as.character(counts$class[-10]),"Single or low copy DNA")),fill=pal)

dev.off()
