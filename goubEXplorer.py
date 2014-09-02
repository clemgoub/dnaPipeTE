#!/bin/python3
# -*-coding:Utf-8 -*

#Copyright (C) 2014 Clement Goubert and Laurent Modolo

#This program is free software; you can redistribute it and/or
#modify it under the terms of the GNU Lesser General Public
#License as published by the Free Software Foundation; either
#version 2.1 of the License, or (at your option) any later version.

#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
#Lesser General Public License for more details.

#You should have received a copy of the GNU Lesser General Public
#License along with this program; if not, write to the Free Software
#Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA

import argparse
import configparser
import os
import re
import subprocess
import time
import sys
import random
import ntpath

config = configparser.ConfigParser()
if not os.path.isfile('config.ini'):
	print("'config.ini' file not found, writing default one.")
	config['DEFAULT'] = {'Trinity': '/usr/remote/trinityrnaseq_r2013_08_14/Trinity.pl',
						'Trinity_memory': '10G',
						'RepeatMasker': '/panhome/goubert/RepeatMasker/RepeatMasker',
						'RepeatMasker_library': '/path_to/RM_library.fasta',
						'TRF': '/panhome/goubert/trf407b.linux64',
						'Blast_folder': '/usr/remote/ncbi-blast-2.2.29+/bin/', 
						'Parallel': '/panhome/goubert/bin/parallel',
						'Sample_size': 500000,
						'Sample_number': 2}
	with open('config.ini', 'w') as configfile:
		config.write(configfile)
config.read('config.ini')

print("   _____________________________________________________")
print("  /    _               _____ _         _______ ______   \ ")
print(" /    | |             |  __ (_)       |__   __|  ____|   \ ")
print("|   __| |_ __   __ _  | |__) | _ __   ___| |  | |__       \____________________________________________________________________")
print("|  / _\` | '_ \ / _\` | |  ___/ | '_ \ / _ \ |  |  __|        De Novo Anssembly and Annotation PIPEline for Transposable Elements\ ")
print("| | (_| | | | | (_| | | |   | | |_) |  __/ |  | |____      ____________________________________________________________________/ ")
print("|  \__,_|_| |_|\__,_| |_|   |_| .__/ \___|_|  |______|    / ")
print(" \                            | |                        / ")
print("  \___________________________|_|_______________________/ ")

parser = argparse.ArgumentParser(prog='goubEXplorer.py')
parser.add_argument('-input', action='store', dest='input_file', help='input fastq files (two files for paired data)', nargs='*')
parser.add_argument('-output', action='store', dest='output_folder', help='output folder')
parser.add_argument('-cpu', action='store', default="1", dest='cpu', help='maximum number of cpu to use')
args = parser.parse_args()


class FastqSamplerToFasta:
	def __init__(self, fastq_files, number, sample_number, output_folder):
		self.number = int(number)
		self.sample_number = int(sample_number)
		self.output_folder = output_folder
		if not os.path.exists(self.output_folder):
			os.makedirs(self.output_folder)
		self.fastq_R1 = fastq_files[0]
		if len(fastq_files) == 1:
			self.paired = False
		else:
			self.fastq_R1 = fastq_files[1]
		self.files = list()
		if not self.test_sampling():
			self.get_sampled_id(self.fastq_R1)
			print("sampling "+str(self.sample_number)+" sample of "+str(self.number)+" reads...")
			for i in range(0, self.sample_number):
				self.sampling(self.fastq_R1, i)
				self.files.append("s"+str(i)+"_"+self.path_leaf(self.fastq_R1)+".fasta")
			if self.paired:
				for i in range(0, self.sample_number):
					self.sampling(self.fastq_R2, i)
					self.files.append("s"+str(i)+"_"+self.path_leaf(self.fastq_R2)+".fasta")
	
	def result(self):
		return(self.files)

	def path_leaf(self, path) :
		head, tail = ntpath.split(path)
		return tail or ntpath.basename(head)

	def get_sampled_id(self, file_name):
		self.tirages = list()
		tirages = list()
		print( "number of reads to sample : ", self.number, "\nfastq : ", file_name )
		sys.stdout.write("counting reads number ...")
		sys.stdout.flush()
		with open(file_name, 'r') as file1 :
			np = sum(1 for line in file1)
		np = int((np) / 4)
		sys.stdout.write("\rtotal number of reads : "+str(np)+"\n")
		sys.stdout.flush()
		population = range(1,np)
		tirages = random.sample(population, self.number*self.sample_number)
		for j in range(0, self.sample_number):
			tirages_sample = tirages[self.number*j:self.number*(j+1)]
			tirages_sample.sort()
			i = 0
			while i < len(tirages_sample):
				tirages_sample[i] = ((tirages_sample[i]-1) * 4)
				i += 1
			self.tirages.extend(tirages_sample)

	def sampling(self, fastq_file, sample_number):
		sys.stdout.write(str(0)+"/"+str(self.number))
		sys.stdout.flush()
		with open(fastq_file, 'r') as fastq_handle :
			i = self.number*sample_number
			j = self.number*sample_number
			tag = "/s"+str(sample_number)+"_"
			with open(self.output_folder+tag+self.path_leaf(fastq_file)+".fasta", 'w') as output :
				for line in fastq_handle :
					if j < self.number*(sample_number+1) :
						if self.tirages[j] <= i and i <= (self.tirages[j]+3) :
							if i  == self.tirages[j]:
								output.write(">"+str(j+sample_number*self.number)+"\n")
							if i == self.tirages[j]+1:
								output.write(str(line))
						if i >= (self.tirages[j]+3) :
							j += 1
							if j % 100 == 0:
								sys.stdout.write("\r"+str(j)+"/"+str(self.number))
								sys.stdout.flush()
						i += 1
					else :
						break
		sys.stdout.write("\r"+"s_"+self.path_leaf(fastq_file)+" done.\n")

	def test_sampling(self):
		sampling_done = True
		for sample_number in range(0, self.sample_number):
			tag = "/s"+str(sample_number)+"_"
			if not os.path.isfile(self.output_folder+tag+self.path_leaf(self.fastq_R1)+".fasta"):
				sampling_done = False
			if self.paired:
				if not os.path.isfile(self.output_folder+tag+self.path_leaf(self.fastq_R2)+".fasta"):
					sampling_done = False
		for i in range(0, self.sample_number):
			self.files.append("s"+str(i)+"_"+self.path_leaf(self.fastq_R1)+".fasta")
		if self.paired:
			for i in range(0, self.sample_number):
				self.files.append("s"+str(i)+"_"+self.path_leaf(self.fastq_R2)+".fasta")
		if sampling_done:
			print("sampling file found, skipping sampling...")
		else:
			self.files = list()
		return sampling_done

class Trinity:
	def __init__(self, Trinity_path, Trinity_memory, cpu, output_folder, sample_files, sample_number):
		self.Trinity_path = str(Trinity_path)
		self.Trinity_memory = str(Trinity_memory)
		self.cpu = int(cpu)
		self.output_folder = str(output_folder)
		self.sample_files = sample_files
		self.sample_number = int(sample_number)
		print("\nGenomic repeats assembly/annotation/quantification pipeline using TRINITY - version 0.1\n")
		if not self.test_trinnity():
			self.trinity_iteration(0)
			for i in range(1, self.sample_number):
				self.trinity_iteration(i)
			self.new_version_correction()
			self.renaming_output()

	def trinity_iteration(self, iteration):
		print("###################################")
		print("### TRINITY to assemble repeats ###")
		print("###################################\n")
		print("***** TRINITY iteration "+str(iteration+1)+" *****\n")
		if not os.path.exists(self.output_folder+"/Trinity_run"+str(iteration+1)):
			os.makedirs(self.output_folder+"/Trinity_run"+str(iteration+1))
		self.select_reads(iteration)
		trinity = self.Trinity_path+" --seqType fa --JM "+str(self.Trinity_memory)+" --single "+self.output_folder+"/"+self.sample_files[iteration]+" --CPU "+str(self.cpu)+" --min_glue 0 --output "+self.output_folder+"/Trinity_run"+str(iteration+1)
		trinityProcess = subprocess.Popen(str(trinity), shell=True)
		trinityProcess.wait()
		print("Trinity iteration "+str(iteration+1)+" Done'")

	def select_reads(self, iteration):
		print("Selecting reads for Trinity iteration number "+str(iteration+1)+"...")
		select_reads = "awk '{print $2; print $4}' "+self.output_folder+"/Trinity_run"+str(iteration)+"/chrysalis/readsToComponents.out.sort | sed 's/>/>run1_/g' > "+self.output_folder+"/reads_run"+str(iteration)+".fasta && "
		select_reads += "cat "+self.output_folder+"/reads_run"+str(iteration)+".fasta >> "+self.output_folder+"/"+self.sample_files[iteration]
		select_readsProcess = subprocess.Popen(str(select_reads), shell=True)
		select_readsProcess.wait()
		print("Done\n")

	def new_version_correction(self):
		trinity = self.Trinity_path+" -version"
		proc = subprocess.Popen(str(trinity), shell=True, stdout=subprocess.PIPE)
		out = proc.communicate()[0]
		year = re.search('\d{4}', str(out)).group(0)
		if int(year) >= 2014:
			trinity_correction = "sed -i 's/>c/>comp/g' "+self.output_folder+"/Trinity_run"+str(self.sample_number)+"/Trinity.fasta"
			trinity_correctionProcess = subprocess.Popen(str(trinity_correction), shell=True)
			trinity_correctionProcess.wait()

	def renaming_output(self):
		print("renaming Trinity output...")
		rename_output = "awk '{print $1}' "+self.output_folder+"/Trinity_run"+str(self.sample_number)+"/Trinity.fasta > "+self.output_folder+"/Trinity.fasta"
		rename_outputProcess = subprocess.Popen(str(rename_output), shell=True)
		rename_outputProcess.wait()
		print("done")

	def test_trinnity(self):
		trinnity_done = True
		if not os.path.isfile(self.output_folder+"/Trinity.fasta"):
			trinnity_done = False
		if trinnity_done:
			print("Trinity files found, skipping assembly...")
		return trinnity_done

class RepeatMasker:
	def __init__(self, RepeatMasker_path, RM_library, cpu, output_folder):
		self.RepeatMasker_path = str(RepeatMasker_path)
		self.RM_library = str(RM_library)
		self.cpu =  int(cpu)
		self.output_folder = str(output_folder)
		if not self.test_RepeatMasker():
			self.repeatmasker_run()
			self.contig_annotation()

	def repeatmasker_run(self):
		print("#######################################")
		print("### REPEATMASKER to anotate contigs ###")
		print("#######################################\n")
		repeatmasker = self.RepeatMasker_path+" -pa "+str(self.cpu)+" -s -lib "+self.RM_library+" "+self.output_folder+"/Trinity.fasta"
		repeatmaskerProcess = subprocess.Popen(str(repeatmasker), shell=True)
		repeatmaskerProcess.wait()
		if not os.path.exists(self.output_folder+"/Annotation"):
			os.makedirs(self.output_folder+"/Annotation")
		bestHit = "cat "+self.output_folder+"/Trinity.fasta.out | sed 's/(//g' | sed 's/)//g' | sort -k 5,5 -k 1,1nr | awk 'BEGIN {prev_query = \"\"} {if($5 != prev_query) {{print($5 \"\\t\"  sqrt(($7-$6)*($7-$6))/(sqrt(($7-$6)*($7-$6))+$8) \"\\t\"$10 \"\\t\" $11 \"\\t\" sqrt(($13-$12)*($13-$12))/(sqrt(($13-$12)*($13-$12))+$14))}; prev_query = $5}}' > "+self.output_folder+"/Annotation/one_RM_hit_per_Trinity_contigs && "
		bestHit += "cat "+self.output_folder+"/Annotation/one_RM_hit_per_Trinity_contigs | awk '{if($2>=0.8 && $5>=0.8){print$0}}' > "+self.output_folder+"/Annotation/Best_RM_annot_80-80 && "
		bestHit += "cat "+self.output_folder+"/Annotation/one_RM_hit_per_Trinity_contigs | awk '{if($2>=0.8 && $5<0.8){print$0}}' > "+self.output_folder+"/Annotation/Best_RM_annot_partial"
		bestHitProcess = subprocess.Popen(str(bestHit), shell=True)
		bestHitProcess.wait()
		print("Done")

	def contig_annotation(self):
		print("#########################################")
		print("### Making contigs annotation from RM ###")
		print("#########################################")

		annotation = ""
		for super_familly in ["LTR", "LINE", "SINE", "ClassII", "Low_complexity", "Simple_repeat"] :
			# fais une liste de fichier headers pour aller récupérer les contigs
			annotation += "grep '"+super_familly+"' "+self.output_folder+"/Annotation/one_RM_hit_per_Trinity_contigs | awk '{print$1}' > "+self.output_folder+"/Annotation/"+super_familly+".headers && "
			# récupère et annote les contigs de Trinity.fasta selon les meilleurs hits RM
			annotation += "perl -ne 'if(/^>(\S+)/){$c=$i{$1}}$c?print:chomp;$i{$_}=1 if @ARGV' "+self.output_folder+"/Annotation/"+super_familly+".headers "+self.output_folder+"/Trinity.fasta | sed 's/>comp/>"+super_familly+"_comp/g' > "+self.output_folder+"/Annotation/"+super_familly+"_annoted.fasta && "
		annotation += "cat "+self.output_folder+"/Annotation/*.headers > "+self.output_folder+"/Annotation/all_annoted.head && "
		annotation += "perl -ne 'if(/^>(\S+)/){$c=!$i{$1}}$c?print:chomp;$i{$_}=1 if @ARGV' "+self.output_folder+"/Annotation/all_annoted.head "+self.output_folder+"/Trinity.fasta | sed 's/>comp/>na_comp/g' > "+self.output_folder+"/Annotation/unannoted.fasta && "
		annotation += "cat "+self.output_folder+"/Annotation/*_annoted.fasta > "+self.output_folder+"/Annotation/annoted.fasta"
		annotationProcess = subprocess.Popen(str(annotation), shell=True)
		annotationProcess.wait()
		print("Done\n")

	def test_RepeatMasker(self):
		files = [self.output_folder+"/Trinity.fasta.out", 
			self.output_folder+"/Annotation/Best_RM_annot_80-80", 
			self.output_folder+"/Annotation/Best_RM_annot_partial",
			self.output_folder+"/Annotation/unannoted.fasta",
			self.output_folder+"/Annotation/annoted.fasta"]
		for super_familly in ["LTR", "LINE", "SINE", "ClassII", "Low_complexity", "Simple_repeat"]:
			files.append(self.output_folder+"/Annotation/"+super_familly+"_annoted.fasta")
			files.append(self.output_folder+"/Annotation/"+super_familly+"_annoted.fasta")
		repeatmasker_done = True
		for output in files:
			if not os.path.isfile(output):
				print("file not found "+output)
				repeatmasker_done = False
		if repeatmasker_done:
			print("RepeatMasker files found, skipping Repeatmasker...")
		return repeatmasker_done

class Blast:
	def __init__(self, Blast_path, Parallel_path, cpu, output_folder, sample_number, sample_files):
		self.Blast_path = str(Blast_path)
		self.Parallel_path = str(Parallel_path)
		self.cpu =  int(cpu)
		self.output_folder = str(output_folder)
		self.sample_number = int(sample_number)
		self.sample_files = sample_files
		self.blast1_run()
		self.blast2_run()
		self.blast3_run()
		self.count()

	def blast1_run(self):
		if not os.path.exists(self.output_folder+"/blast_out"):
			os.makedirs(self.output_folder+"/blast_out")
		print("#######################################################")
		print("### Blast 1 : raw reads against all repeats contigs ###")
		print("#######################################################")
		print("blasting...")
		blast = "cat "
		for i in range(0,self.sample_number):
			blast += self.output_folder+"/"+self.sample_files[i]+" "
		blast += " > "+self.output_folder+"/renamed.blasting_reads.fasta && "
		blast += self.Blast_path+"/makeblastdb -in "+self.output_folder+"/Trinity.fasta -out "+self.output_folder+"/Trinity.fasta -dbtype 'nucl' && "
		blast += "cat "+self.output_folder+"/renamed.blasting_reads.fasta | "+self.Parallel_path+" -j "+str(self.cpu)+" --block 100k --recstart '>' --pipe "+self.Blast_path+"/blastn -outfmt 6 -task dc-megablast -db "+self.output_folder+"/Trinity.fasta -query - > "+self.output_folder+"/blast_out/reads_vs_Trinity.fasta.blast.out"
		blastProcess = subprocess.Popen(str(blast), shell=True)
		blastProcess.wait()
		print("Paring blast1 output...")
		blast = "cat "+self.output_folder+"/blast_out/reads_vs_Trinity.fasta.blast.out | sort -k1,1 -k12,12nr -k11,11n | sort -u -k1,1 > "+self.output_folder+"/blast_out/sorted.reads_vs_Trinity.fasta.blast.out && "
		blast += "cat "+self.output_folder+"/blast_out/sorted.reads_vs_Trinity.fasta.blast.out | awk '{print $2\"\\t\"$3}' | sed 's/_/\t/g' > "+self.output_folder+"/Reads_to_components_Rtable.txt"
		blastProcess = subprocess.Popen(str(blast), shell=True)
		blastProcess.wait()

	def blast2_run(self):
		if not os.path.exists(self.output_folder+"/blast_out"):
			os.makedirs(self.output_folder+"/blast_out")
		print("###################################################")
		print("### Blast 2 : raw reads against annoted repeats ###")
		print("###################################################")
		print("blasting...")
		blast = "ln -s "+self.output_folder+"/Annotation/annoted.fasta "+self.output_folder+"/blast_out/blast2_db.fasta && "
		blast += self.Blast_path+"/makeblastdb -in "+self.output_folder+"/blast_out/blast2_db.fasta -out "+self.output_folder+"/blast_out/blast2_db.fasta -dbtype 'nucl' && "
		blast += "cat "+self.output_folder+"/renamed.blasting_reads.fasta | "+self.Parallel_path+" -j "+str(self.cpu)+" --block 100k --recstart '>' --pipe "+self.Blast_path+"/blastn -outfmt 6 -task dc-megablast -db "+self.output_folder+"/blast_out/blast2_db.fasta -query - > "+self.output_folder+"/blast_out/reads_vs_annoted.blast.out"
		blastProcess = subprocess.Popen(str(blast), shell=True)
		blastProcess.wait()
		print("Paring blast2 output...")
		blast = "sort -k1,1 -k12,12nr -k11,11n "+self.output_folder+"/blast_out/reads_vs_annoted.blast.out | sort -u -k1,1 > "+self.output_folder+"/blast_out/sorted.reads_vs_annoted.blast.out"
		blastProcess = subprocess.Popen(str(blast), shell=True)
		blastProcess.wait()
		print("Selecting non-matching reads for blast3")
		blast = "awk '{print$1}' "+self.output_folder+"/blast_out/sorted.reads_vs_annoted.blast.out > "+self.output_folder+"/blast_out/matching_reads.headers && "
		blast += "perl -ne 'if(/^>(\S+)/){$c=!$i{$1}}$c?print:chomp;$i{$_}=1 if @ARGV' "+self.output_folder+"/blast_out/matching_reads.headers "+self.output_folder+"/renamed.blasting_reads.fasta > "+self.output_folder+"/blast_out/unmatching_reads1.fasta"
		blastProcess = subprocess.Popen(str(blast), shell=True)
		blastProcess.wait()

	def blast3_run(self):
		if not os.path.exists(self.output_folder+"/blast_out"):
			os.makedirs(self.output_folder+"/blast_out")
		print("#####################################################")
		print("### Blast 3 : raw reads against unannoted repeats ###")
		print("#####################################################")
		print("blasting...")
		blast = self.Blast_path+"/makeblastdb -in "+self.output_folder+"/Annotation/unannoted_final.fasta -out "+self.output_folder+"/blast_out/blast3_db.fasta -dbtype 'nucl' && "
		blast += "cat "+self.output_folder+"/blast_out/unmatching_reads1.fasta | "+self.Parallel_path+" -j "+str(self.cpu)+" --block 100k --recstart '>' --pipe "+self.Blast_path+"/blastn -outfmt 6 -task dc-megablast -db "+self.output_folder+"/blast_out/blast3_db.fasta -query - > "+self.output_folder+"/blast_out/reads_vs_unannoted.blast.out"
		blastProcess = subprocess.Popen(str(blast), shell=True)
		blastProcess.wait()
		print("Paring blast3 output...")
		blast = "sort -k1,1 -k12,12nr -k11,11n "+self.output_folder+"/blast_out/reads_vs_unannoted.blast.out | sort -u -k1,1 > "+self.output_folder+"/blast_out/sorted.reads_vs_unannoted.blast.out"
		blastProcess = subprocess.Popen(str(blast), shell=True)
		blastProcess.wait()

	def count(self):
		print("#######################################################")
		print("### Estimation of Repeat content from blast outputs ###")
		print("#######################################################")
		count = "rm "+self.output_folder+"/Count*.txt"
		print("LTR >> "+self.output_folder+"/Counts1.tx")
		count += "cat "+self.output_folder+"/blast_out/sorted.reads_vs_annoted.blast.out | grep -c 'LTR' >> "+self.output_folder+"/Counts2.txt && "
		print("LINE >> "+self.output_folder+"/Counts1.tx")
		count += "cat "+self.output_folder+"/blast_out/sorted.reads_vs_annoted.blast.out | grep -c 'LINE' >> "+self.output_folder+"/Counts2.txt && "
		print("SINE >> "+self.output_folder+"/Counts1.tx")
		count += "cat "+self.output_folder+"/blast_out/sorted.reads_vs_annoted.blast.out | grep -c 'SINE' >> "+self.output_folder+"/Counts2.txt && "
		print("ClassII >> "+self.output_folder+"/Counts1.tx")
		count += "cat "+self.output_folder+"/blast_out/sorted.reads_vs_annoted.blast.out | grep -c 'ClassII' >> "+self.output_folder+"/Counts2.txt && "
		print("Low_Complexity >> "+self.output_folder+"/Counts1.tx")
		count += "cat "+self.output_folder+"/blast_out/sorted.reads_vs_annoted.blast.out | grep -c 'LowComp' >> "+self.output_folder+"/Counts2.txt && "
		print("Simple_repeats >> "+self.output_folder+"/Counts1.tx")
		count += "cat "+self.output_folder+"/blast_out/sorted.reads_vs_annoted.blast.out | grep -c 'Simple_repeats' >> "+self.output_folder+"/Counts2.txt && "
		print("Tandem_repeats >> "+self.output_folder+"/Counts1.tx")
		count += "cat "+self.output_folder+"/blast_out/sorted.reads_vs_annoted.blast.out | grep -c 'Tandem_\|Satellite_\|MSAT' >> "+self.output_folder+"/Counts2.txt && "
		print("NAs >> "+self.output_folder+"/Counts1.tx")
		count += "cat "+self.output_folder+"/blast_out/sorted.reads_vs_unannoted.blast.out | wc -l >> "+self.output_folder+"/Counts2.txt && "
		print("Total >> "+self.output_folder+"/Counts1.tx")
		count += "cat "+self.output_folder+"/blast_reads.counts >> "+self.output_folder+"/Counts2.txt && "
		count += "paste "+self.output_folder+"/Counts1.txt  "+self.output_folder+"/Counts2.txt > "+self.output_folder+"/Counts.txt"
		countProcess = subprocess.Popen(str(count), shell=True)
		countProcess.wait()
		print("parsing blastout and adding RM annotations for each read...")
		count = "cat "+self.output_folder+"/blast_out/sorted.reads_vs_annoted.blast.out |  awk '{print $1\"\\t\"$2\"\\t\"$3}' |grep -v 'comp' > "+self.output_folder+"/blastout_RMonly && "
		count += "cat "+self.output_folder+"/blast_out/sorted.reads_vs_annoted.blast.out | sed 's/_comp/\\tcomp/g' | awk '{print $1\"\\t\"$3\"\\t\"$4}' | grep 'comp' > "+self.output_folder+"/join.blastout && "
		count += "cat "+self.output_folder+"/join.blastout | sort -k2,2 > "+self.output_folder+"/join.blastout.sorted && "
		count += "cat "+self.output_folder+"/Annotation/one_RM_hit_per_Trinity_contigs | sort -k1,1 > "+self.output_folder+"/contigsTrinityRM.sorted && "
		count += "join -a1 -12 -21 "+self.output_folder+"/join.blastout.sorted contigsTrinityRM.sorted > "+self.output_folder+"/blast_matching_w_annot_1 && "
		count += "cat "+self.output_folder+"/blast_matching_w_annot_1 | awk '{print $1 \"\\t\" $2 \"\\t\" $5 \"\\t\" $3}' > "+self.output_folder+"/blast_matching_w_annot_2 && "
		count += "cat "+self.output_folder+"/blastout_RMonly | sed 's/#/\t/g' | awk '{print \"Repbase-\\$2t\" $1 \"\\t\" $2 \"\\t\" $4}' > "+self.output_folder+"/blastout_RMonly_wMSAT && "
		count += "cat "+self.output_folder+"/blast_matching_w_annot_2 "+self.output_folder+"/blastout_RMonly_wMSAT > "+self.output_folder+"/blast_out/blastout_final_fmtd_annoted && "
		count += "rm "+self.output_folder+"/blastout_RMonly && "
		count += "rm "+self.output_folder+"/join.blastout && "
		count += "rm "+self.output_folder+"/join.blastout.sorted && "
		count += "rm "+self.output_folder+"/contigsTrinityRM.sorted && "
		count += "rm "+self.output_folder+"/blast_matching_w_annot_1 && "
		count += "rm "+self.output_folder+"/blastout_RMonly_wMSAT && "
		count += "rm "+self.output_folder+"/blast_contigs_1_fmtd"
		countProcess = subprocess.Popen(str(count), shell=True)
		countProcess.wait()
		print("Done, results in: blast_out/blastout_final_fmtd_annoted")

class Graph:
	def __init__(self, output_folder):
		self.output_folder = str(output_folder)
		self.run()

	def run(self):
		print("#########################################")
		print("### OK, lets build some pretty graphs ###")
		print("#########################################")
		print("Drawing graphs...")
		graph = "cp "+self.output_folder+"/blast_reads.counts . && "
		graph += "cp "+self.output_folder+"/Counts.txt . && "
		graph += "Rscript graph.R && "
		graph += "Rscript pieChart.R && "
		print("Done")
		graph += "rm single.fa.read_count && "
		graph += "mv Reads_to_components_Rtable.txt "+self.output_folder+"/ && "
		graph += "mv Reads_to_components.* "+self.output_folder+"/ && "
		graph += "mv TEs_piechart.* "+self.output_folder+"/ && "
		graph += "mv reads_per_component_sorted.txt "+self.output_folder+"/"
		graphProcess = subprocess.Popen(str(graph), shell=True)
		graphProcess.wait()
		print("########################")
		print("#   see you soon !!!   #")
		print("########################")

Sampler = FastqSamplerToFasta(args.input_file, config['DEFAULT']['Sample_size'], config['DEFAULT']['Sample_number'], args.output_folder)
sample_files = Sampler.result()
Trinity(config['DEFAULT']['Trinity'], config['DEFAULT']['Trinity_memory'], args.cpu, args.output_folder, sample_files, config['DEFAULT']['Sample_number'])
RepeatMasker(config['DEFAULT']['RepeatMasker'], config['DEFAULT']['RepeatMasker_library'], args.cpu, args.output_folder)
Blast(config['DEFAULT']['Blast_folder'], config['DEFAULT']['Parallel'], args.cpu, args.output_folder, config['DEFAULT']['Sample_number'], sample_files)
Graph(args.output_folder)