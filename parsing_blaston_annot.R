read.table("aeg_blastout_final_fmtd_annoted",sep="\t")->aeg_final
names(aeg_final)=c("contig", "read", "annot", "id")
cbind(as.data.frame(paste(aeg_final$contig,aeg_final$annot, sep="_")), aeg_final$read, aeg_final$id)->aeg_final_binded
names(aeg_final_binded)=c("contig", "read", "id")



as.data.frame(tapply(aeg_final_binded$contig, aeg_final_binded$contig, length))->aeg_reads_per_contig_annoted
names(aeg_reads_per_contig_annoted)="reads"

head(cbind(as.data.frame(paste(aeg_final$contig,aeg_final$annot, sep="_")), aeg_final$read, aeg_final$id))



as.data.frame(tapply(aeg_final$contig, aeg_final$annot, length))->aeg_reads_per_annotation
as.data.frame(tapply(aeg_final$contig, aeg_final$class, length))->aeg_reads_per_class  