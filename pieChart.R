#!/usr/bin/Rscript
#############################
# Plot TE classes pie chart #
#############################

Args = commandArgs()
folder = Args[6]
file = Args[7]
colors = Args[8]

counts = read.table(paste(folder,file, sep="/"))
names(counts)=c("class","reads")
palette = read.table(paste(colors, sep="/"))
names(palette)=c("class", "col")

subcounts = subset(counts, counts$reads > 0)
subpalette = subset(palette, palette$class %in% subcounts$class)



Single_or_low_copy=counts$reads[length(counts$reads)]-sum(counts$reads[1:(length(counts$reads)-1)])
perc=round(    c(      ((subcounts$reads[1:(length(subcounts$reads)-1)])/(counts$reads[length(counts$reads)]) )    , (Single_or_low_copy/(counts$reads[length(counts$reads)]))),   4      )


#pie(c(counts$reads[1:(length(counts$reads)-1),Single_or_low_copy),paste(c(as.character(counts$class[-length(counts$reads)]),"Single or low copy DNA"), perc, "%"), col=rainbow(9))
#pal=c("#33cc33ff","#6699ffff","#B966F4","salmon","dimgrey","chartreuse","gold","black","#d3d3d3ff")
#pie(c(counts$reads[1:(length(counts$reads)-1),Single_or_low_copy),paste(c(as.character(counts$class[-length(counts$reads)]),"Single or low copy DNA"), perc, "%"), col=pal)

png(file=paste(folder,"TEs_piechart.png",sep="/"), width=1000, height=600)

pie(c(subcounts$reads[1:(length(subcounts$reads)-1)], Single_or_low_copy), paste(perc*100, "%"), col=c(as.character(subpalette$col),"#d3d3d3ff"), clockwise=T, border="white")

legend(1,0.5,paste(c(as.character(subcounts$class[-length(subcounts$reads)]),"Single or low copy DNA")),fill=c(as.character(subpalette$col),"#d3d3d3ff"))

dev.off()

pdf(file=paste(folder,"TEs_piechart.pdf",sep="/"), width=16, height=10)

pie(c(subcounts$reads[1:(length(subcounts$reads)-1)], Single_or_low_copy), paste(perc*100, "%"), col=c(as.character(subpalette$col),"#d3d3d3ff"), clockwise=T, border="white")

legend(1,0.5,paste(c(as.character(subcounts$class[-length(subcounts$reads)]),"Single or low copy DNA")),fill=c(as.character(subpalette$col),"#d3d3d3ff"))

dev.off()
