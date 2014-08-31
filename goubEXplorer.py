#!/bin/python
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
import argparse
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
	def __init__(self, fastq_files, number, number_of_sample, output_folder):
		self.number = int(number)
		self.sample_number = int(sample_number)
		self.output_folder = output_folder
		self.fastq_R1 = fastq_files[0]
		if len(fastq_files) == 1:
			self.paired = False
		else:
			self.fastq_R1 = fastq_files[1]
		self.tirages = list()
		self.get_sampled_id()

		files = list()
		for i in range(0, self.sample_number):
			self.sampling(self, self.fastq_R1, i)
			files.append("s"+str(i)+"_"+self.path_leaf(self.fastq_R1)+".fasta")
		if self.paired:
			for i in range(0, self.sample_number):
				self.sampling(self, self.fastq_R2, i)
				files.append("s"+str(i)+"_"+self.path_leaf(self.fastq_R2)+".fasta")
		return(files)

	def path_leaf(self, path) :
		head, tail = ntpath.split(path)
		return tail or ntpath.basename(head)

	def get_sampled_id(self):
		print( "number of reads to sample : ", self.number, "\nfastq : ", self.fastq_R1 )
		sys.stdout.write("counting reads number ...")
		sys.stdout.flush()
		with open(self.fastq_R1, 'r') as file1 :
			np = sum(1 for line in file1)

		np = int((np) / 4)
		sys.stdout.write("\rtotal number of reads : "+str(np)+"\n")
		sys.stdout.flush()

		population = range(1,np)
		self.tirages = random.sample(population, self.number)

		self.tirages.sort()
		i = 0
		while i < len(self.tirages) :
			self.tirages[i] = ((self.tirages[i]-1) * 4)
			i += 1

	def sampling(self, fastq_file, sample_number):
		sys.stdout.write(str(0)+"/"+str(self.number))
		sys.stdout.flush()
		with open(fastq_file, 'r') as fastq_handle :
			i = 0
			j = 0
			tag = "/s"+str(sample_number)+"_"
			with open(self.output_folder+tag+self.path_leaf(fastq_file)+".fasta", 'w') as output :
				for line in fastq_handle :
					if j < len(self.tirages) :
						if self.tirages[j] <= i and i <= (self.tirages[j]+3) :
							if i  == 1:
								output.write(">"+str(j+sample_number*self.number)+"\n")
							if i == 2:
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

class Trinity:
	def __init__(self, Trinity_path, Trinity_memory, cpu, output_folder, sample_files, sample_number):
		self.Trinity_path = str(Trinity_path)
		self.Trinity_memory = str(Trinity_memory)
		self.cpu = int(cpu)
		self.output_folder = str(output_folder)
		self.sample_files = sample_files
		self.sample_number = int(sample_number)
		print("\nGenomic repeats assembly/annotation/quantification pipeline using TRINITY - version 0.1\n")
		self.trinity_iteration(0)
		for i in range(1, self.sample_number):
			self.select_reads(i)
			self.trinity_iteration(i)
		self.new_version_correction()
		self.rename_output()

		def trinity_iteration(self, iteration):
			print("###################################")
			print("### TRINITY to assemble repeats ###")
			print("###################################\n")

			print("***** TRINITY iteration "+str(iteration+1)+" *****\n")
			if not os.path.exists(self.output_folder+"/Trinity_run"+str(iteration+1)):
				os.makedirs(self.output_folder+"/Trinity_run"+str(iteration+1))
			trinity = self.Trinity_path+" --seqType fa --JM "+str(self.Trinity_memory)+" --single "+self.output_folder+"/"+self.sample_files[iteration]+" --CPU "+str(self.cpu)+" --min_glue 0 --output "+self.output_folder+"/Trinity_run"+str(iteration+1)
			trinityProcess = subprocess.Popen(str(trinity), shell=True)
			trinityProcess.wait()
			print("Trinity iteration "+str(iteration+1)+" Done'")

		def select_reads(self, iteration):
			print("Selecting reads for Trinity iteration number "+str(iteration+1)+"...")
			select_reads = "awk '{print $2; print $4}' "+self.output_folder+"/Trinity_run"+str(iteration)+"/chrysalis/readsToComponents.out.sort | sed 's/>/>run1_/g' > "+self.output_folder+"/reads_run"+str(iteration)+".fasta && cat "+self.output_folder+"/reads_run"+str(iteration)+".fasta >> "+self.output_folder+"/"+self.sample_files[iteration]
			select_readsProcess = subprocess.Popen(str(select_reads), shell=True)
			select_readsProcess.wait()
			print("Done\n")

		def new_version_correction(self):
			trinity = self.Trinity_path+" -version"
			proc = subprocess.Popen(str(trinity), stdout=subprocess.PIPE)
			out = proc.communicate()[0]
			year = re.search('\d{4}', out).group(0)
			if int(year) >= 2014:
				trinity_correction = "sed -i 's/>c/>comp/g' "+self.output_folder+"/Trinity_run"+str(self.sample_number+1)+"/Trinity.fasta"
				trinity_correctionProcess = subprocess.Popen(str(trinity_correction), shell=True)
				trinity_correctionProcess.wait()

		def renaming_output(self):
			print("renaming Trinity output...")
			rename_output = "awk '{print $1}' "+self.output_folder+"/Trinity_run"+str(self.sample_number+1)+"/Trinity.fasta > "+self.output_folder+"/Trinity.fasta"
			rename_outputProcess = subprocess.Popen(str(rename_output), shell=True)
			rename_outputProcess.wait()
			print("done")



class RepeatMasker:
	def __init__(self, RepeatMasker_path, RM_library, cpu, output_folder):
		self.RepeatMasker_path = str(RepeatMasker_path)
		self.RM_library = str(RM_library)
		self.cpu =  int(cpu)
		self.output_folder = str(output_folder)
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
		bestHit = "cat $2/Trinity.fasta.out | sed 's/(//g' | sed 's/)//g' | sort -k 5,5 -k 1,1nr | awk 'BEGIN {prev_query = \"\"} {if($5 != prev_query) {{print($5 \"\t\"  sqrt(($7-$6)*($7-$6))/(sqrt(($7-$6)*($7-$6))+$8) \"\t\"$10 \"\t\" $11 \"\t\" sqrt(($13-$12)*($13-$12))/(sqrt(($13-$12)*($13-$12))+$14))}; prev_query = $5}}' > $2/Annotation/one_RM_hit_per_Trinity_contigs && cat $2/Annotation/one_RM_hit_per_Trinity_contigs | awk '{if($2>=0.8 && $5>=0.8){print$0}}' > $2/Annotation/Best_RM_annot_80-80 && cat $2/Annotation/one_RM_hit_per_Trinity_contigs | awk '{if($2>=0.8 && $5<0.8){print$0}}' > $2/Annotation/Best_RM_annot_partial"
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
		annotation += "cat "+self.output_folder+"/Annotation/*_annoted.fasta > "+self.output_folder+"/Annotation/annoted.fasta && "
		annotationProcess = subprocess.Popen(str(annotation), shell=True)
		annotationProcess.wait()
		print("Done\n")

class Blast:
	def __init__(self, Blast_path):
		self.Blast_path = str(Blast_path)

	delf blast_run(self):
		

sample_files = FastqSamplerToFasta(args.input, config['DEFAULT']['Sample_size'], config['DEFAULT']['Sample_number'], args.output_folder)
Trinity(config['DEFAULT']['Trinity'], config['DEFAULT']['Trinity_memory'], args.cpu, args.output_folder, sample_files, config['DEFAULT']['Sample_number'])
RepeatMasker(config['DEFAULT']['RepeatMasker'], config['DEFAULT']['RepeatMasker_library'], args.cpu, args.output_folder)
Blast(config['DEFAULT']['Blast_folder'])