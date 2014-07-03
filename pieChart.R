#############################
# Plot TE classes pie chart #
#############################

read.table("Counts.txt")-> counts
names(counts)=c("class","reads")
Single_or_low_copy=counts$reads[9]-sum(counts$reads[1:8])
perc=signif(c(counts$reads[1:8]/counts$reads[9],Single_or_low_copy/counts$reads[9])*100,3)
#pie(c(counts$reads[1:8],Single_or_low_copy),paste(c(as.character(counts$class[-9]),"Single or low copy DNA"), perc, "%"), col=rainbow(9))
pal=c("firebrick1","darkorange1","forestgreen","dodgerblue3","darkmagenta","grey","chartreuse","gold","brown")
#pie(c(counts$reads[1:8],Single_or_low_copy),paste(c(as.character(counts$class[-9]),"Single or low copy DNA"), perc, "%"), col=pal)

png(file="TEs_piechart.png", width=1000, height=600)

pie(c(counts$reads[1:8],Single_or_low_copy),paste(perc, "%"), col=pal, clockwise=T)
legend(1,0.5,paste(c(as.character(counts$class[-9]),"Single or low copy DNA")),fill=pal)

dev.off()

pdf(file="TEs_piechart.pdf", width=16, height=10)

pie(c(counts$reads[1:8],Single_or_low_copy),paste(perc, "%"), clockwise=T, col=pal)
legend(1,0.5,paste(c(as.character(counts$class[-9]),"Single or low copy DNA")),fill=pal)

dev.off()
