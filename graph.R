#!/usr/bin/Rscript
###############################################
# This script draws the reads/component graph #
###############################################


Args = commandArgs()
folder = Args[6]
file1 = Args[7]
file2 = Args[8]
reads.to.comp = read.table(paste(folder,file1,sep="/"))
names(reads.to.comp)=c("comp","contig","seq","identity")
reads.to.comp$comp = paste(reads.to.comp$comp, reads.to.comp$contig, reads.to.comp$seq, sep="_")
total = read.table(paste(folder,file2,sep="/"))

#reads per component
tapply(reads.to.comp$comp,reads.to.comp$comp,length)->rpc
as.data.frame(rpc)->rpc
cbind(row.names(rpc),rpc)->rpc
names(rpc)=c("component","reads")

#identity per component
tapply(reads.to.comp$identity,reads.to.comp$comp,mean)->idpc
as.data.frame(idpc)->idpc

cbind(rpc, idpc$idpc)->r_id_pc
names(r_id_pc)=c("component","reads","mean_id")

r_id_pc[order(r_id_pc$reads, decreasing=T),]->r_id_pc

write.table(r_id_pc, file=paste(folder,"reads_per_component_sorted.txt",sep="/"), quote=F)


#compute components threshold >= 0.01%
seuil=sum(subset(r_id_pc, r_id_pc$reads>=0.0001*total[1,1])$reads)/total[1,1]

#graphs 

pdf(file=paste(folder,"Reads_to_components.pdf",sep="/"))
barplot(r_id_pc$reads, r_id_pc$reads/total[1,1], xlim=c(0,1), ylim=c(0,max(r_id_pc$reads)+1000),xaxt='n', ylab="reads per component", xlab="genome proportion")
segments(0,0,1,0)
axis(1,c(0,0.25,0.5,0.75,1))
rect(c((sum(r_id_pc$reads/total[1,1])),(sum(r_id_pc$reads/total[1,1]))),c(0,0),c(1,1),c(max(r_id_pc$reads)+1000,max(r_id_pc$reads)+1000), col="#00FF0010")
rect(c(0,0),c(1,1),c(seuil,seuil),c(max(r_id_pc$reads)+1000,max(r_id_pc$reads)+1000), col="#FF000010")
rect(c(seuil,seuil),c(1,1),c((sum(r_id_pc$reads/total[1,1])),(sum(r_id_pc$reads/total[1,1]))),c(max(r_id_pc$reads)+1000,max(r_id_pc$reads)+1000), col="#FF000005")
axis(1,signif(sum(r_id_pc$reads/total[1,1]),3))
legend(0.75,max(r_id_pc$reads)*2/3, legend=c("repeats","rep < 0.01 %","single"),fill=c("#FF000024","#FF000014","#00FF0020"), bg="white")
dev.off()

png(file=paste(folder,"Reads_to_components.png",sep="/"), width=800, height=600)
barplot(r_id_pc$reads, r_id_pc$reads/total[1,1], xlim=c(0,1), ylim=c(0,max(r_id_pc$reads)+1000),xaxt='n', ylab="reads per component", xlab="genome proportion")
segments(0,0,1,0)
axis(1,c(0,0.25,0.5,0.75,1))
rect(c((sum(r_id_pc$reads/total[1,1])),(sum(r_id_pc$reads/total[1,1]))),c(0,0),c(1,1),c(max(r_id_pc$reads)+1000,max(r_id_pc$reads)+1000), col="#00FF0010")
rect(c(0,0),c(1,1),c(seuil,seuil),c(max(r_id_pc$reads)+1000,max(r_id_pc$reads)+1000), col="#FF000010")
rect(c(seuil,seuil),c(1,1),c((sum(r_id_pc$reads/total[1,1])),(sum(r_id_pc$reads/total[1,1]))),c(max(r_id_pc$reads)+1000,max(r_id_pc$reads)+1000), col="#FF000005")
axis(1,signif(sum(r_id_pc$reads/total[1,1]),3))
legend(0.75,max(r_id_pc$reads)*2/3, legend=c("repeats","rep < 0.01 %","single"),fill=c("#FF000024","#FF000014","#00FF0020"), bg="white")
dev.off()
