### This script annotate and order the contigs per read number ###

read.table("rtc_annoted", fill=T, sep=" ")->rtc
rtc$fusion=paste(rtc$V1, rtc$V4, rtc$V6, sep="_")
as.data.frame(tapply(rtc$fusion, rtc$fusion, length))->reads.per.component
names(reads.per.component)="reads"
as.data.frame(tapply(rtc$V3, rtc$fusion, mean))->id.per.component
names(id.per.component)="id"
as.data.frame(tapply(rtc$V3, rtc$fusion, var))->var.per.component
names(var.per.component)="var"
cbind(reads.per.component, id.per.component, var.per.component)->reads.id.per.comp
as.data.frame(reads.id.per.comp[order(reads.id.per.comp$reads, decreasing=T),])->reads.id.per.comp.sorted
names(reads.id.per.comp.sorted)="reads"
write.table(reads.id.per.comp.sorted, quote=FALSE, file="reads.id.per.comp_annoted")