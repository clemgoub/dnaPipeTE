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
						'RepeatMasker': '/panhome/goubert/RepeatMasker/RepeatMasker',
						'TRF': '/panhome/goubert/trf407b.linux64',
						'Blast_folder': '/usr/remote/ncbi-blast-2.2.29+/bin/', 
						'Parallel': '/panhome/goubert/bin/parallel',
						'Sample_size': 500000}
	with open('config.ini', 'w') as configfile:
		config.write(configfile)
config.read('config.ini')

print("  _____                       _   ______            _                       ___           ")
print(" |  __ \                     | | |  ____|          | |                     |__ \          ")
print(" | |__) |___ _ __   ___  __ _| |_| |__  __  ___ __ | | ___  _ __ ___ _ __     ) |         ")
print(" |  _  // _ \ \''_ \ / _ \/ _` | __|  __| \ \/ / \''_ \| |/ _ \| \''__/ _ \ \''__|        ")
print(" | | \ \  __/ |_) |  __/ (_| | |_| |____ >  <| |_) | | (_) | | |  __/ |     / /_          ")
print(" |_|  \_\___| .__/ \___|\__,_|\__|______/_/\_\ .__/|_|\___/|_|  \___|_|    |____|         ")
print("            | |                              | |                                          ")
print("            |_|                              |_|      ")

parser = argparse.ArgumentParser(prog='goubEXplorer.py')
parser.add_argument('-input', action='store', dest='input_file', help='input fastq files (two files for paired data)', nargs='*')
parser.add_argument('-output', action='store', dest='output_folder', help='output folder')
parser.add_argument('-cpu', action='store', default="1", dest='cpu', help='maximum number of cpu to use')
parser.add_argument('-rm', action='store', dest='rm_library', help='/path_to/RM_library.fasta')
args = parser.parse_args()


class FastqSamplerToFasta:
	def __init__(self, fastq_files, number, output_folder):
		self.number = int(number)
		self.output_folder = output_folder
		self.fastq_R1 = fastq_files[0]
		if len(fastq_files) == 1:
			self.paired = False
		else:
			self.fastq_R1 = fastq_files[1]
		self.tirages = list()
		self.get_sampled_id()
		self.sampling(self, self.fastq_R1, 0)
		self.sampling(self, self.fastq_R1, 1)
		if self.paired:
			self.sampling(self, self.fastq_R2)
			return(list("s1_"+self.path_leaf(self.fastq_R1)+".fasta", "s1_"+self.path_leaf(self.fastq_R2)+".fasta", "s2_"+self.path_leaf(self.fastq_R1)+".fasta", "s2_"+self.path_leaf(self.fastq_R2)+".fasta"))
		else:
			return(list("s1_"+self.path_leaf(self.fastq_R1)+".fasta", "s2_"+self.path_leaf(self.fastq_R1)+".fasta"))

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
			if sample_number == 0:
				tag = "/s1_"
			else:
				tag = "/s2_"
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
	def __init__(self, Trinity_path, cpu, output_folder, sample_files):
		self.Trinity_path = str(Trinity_path)
		self.cpu = int(cpu)
		self.output_folder = str(output_folder)
		self.sample_files = sample_files
		print("\nGenomic repeats assembly/annotation/quantification pipeline using TRINITY - version 0.1\n")
		if not os.path.exists(self.output_folder+"/Trinity_run1"):
			os.makedirs(self.output_folder+"/Trinity_run1")
		self.trinity_iteration(1)
		self.select_reads()
		self.trinity_iteration(2)

		def trinity_iteration(self, iteration):
			print("###################################")
			print("### TRINITY to assemble repeats ###")
			print("###################################\n")
			print("***** TRINITY iteration "+str(iteration)+" *****\n")
			if iteration == 1:
				trinity = self.Trinity_path+" --seqType fa --JM 10G --single "+self.output_folder+"/"+self.sample_files[0]+" --CPU "+str(self.cpu)+" --min_glue 0 --output "+self.output_folder+"/Trinity_run1"
			else:
				trinity = self.Trinity_path+" --seqType fa --JM 10G --single "+self.output_folder+"/reads_run2.fasta --CPU "+str(self.cpu)+" --min_glue 0 --output "+self.output_folder
			trinityProcess = subprocess.Popen(str(trinity), shell=True)
			trinityProcess.wait()
			print("Trinity iteration "+str(iteration)+" Done'")

		def select_reads(self):
			print("Selecting reads for second Trinity iteration...")
			select_reads = "cat "+self.output_folder+"/Trinity_run1/chrysalis/readsToComponents.out.sort | awk '{print $2; print $4}' | sed 's/>/>run1_/g' > "+self.output_folder+"/reads_run1.fasta && cat "+self.output_folder+"/reads_run1.fasta "+self.output_folder+"/"+self.sample_files[2]+" > "+self.output_folder+"/reads_run2.fasta"
			select_readsProcess = subprocess.Popen(str(select_reads), shell=True)
			select_readsProcess.wait()
			print("Done\n")

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
		##########################################################################################################################
		# change sort to fit RM output instead of blast m8 output ! ##############################################################
		##########################################################################################################################
		bestHit = "sort -k 2,2 -k 12,12nr "+self.output_folder+"/Trinity.fasta.out | awk 'BEGIN {prev_query = \"\"} {if($2 != prev_query){print($0); prev_query = $2}}' > "+self.output_folder+"/Annotation/one_RM_hit_per_Trinity_contigs"
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
			annotation += "cat "+self.output_folder+"/Annotation/one_RM_hit_per_Trinity_contigs | grep '"+super_familly+"' | awk '{print$1}' > "+self.output_folder+"/Annotation/"+super_familly+".headers && "
			# récupère et annote les contigs de Trinity.fasta selon les meilleurs hits RM
			annotation += "perl -ne 'if(/^>(\S+)/){$c=$i{$1}}$c?print:chomp;$i{$_}=1 if @ARGV' "+self.output_folder+"/Annotation/"+super_familly+".headers "+self.output_folder+"/Trinity.fasta | sed 's/>comp/>"+super_familly+"_comp/g' > "+self.output_folder+"/Annotation/"+super_familly+"_annoted.fasta && "
		annotation += "cat "+self.output_folder+"/Annotation/*.headers > "+self.output_folder+"/Annotation/all_annoted.head && "
		annotation += "perl -ne 'if(/^>(\S+)/){$c=!$i{$1}}$c?print:chomp;$i{$_}=1 if @ARGV' "+self.output_folder+"/Annotation/all_annoted.head "+self.output_folder+"/Trinity.fasta | sed 's/>comp/>na_comp/g' > "+self.output_folder+"/Annotation/unannoted.fasta && "
		annotation += "cat "+self.output_folder+"/Annotation/*_annoted.fasta > "+self.output_folder+"/Annotation/annoted.fasta && "
		annotationProcess = subprocess.Popen(str(annotation), shell=True)
		annotationProcess.wait()
		print("Done\n")


sample_files = FastqSamplerToFasta(args.input, config['DEFAULT']['Sample_size'], args.output_folder)
Trinity(config['DEFAULT']['Trinity'], args.cpu, args.output_folder, sample_files)
RepeatMasker(config['DEFAULT']['RepeatMasker'], args.rm_library, args.cpu, args.output_folder)