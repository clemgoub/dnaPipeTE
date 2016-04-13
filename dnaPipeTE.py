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
import gzip

config = configparser.ConfigParser()
if not os.path.isfile('config.ini'):
	print("'config.ini' file not found, writing default one.")
	config['DEFAULT'] = {'Trinity': os.path.dirname(os.path.realpath(sys.argv[0]))+'/bin/trinityrnaseq_r2013_08_14/Trinity.pl',
						'Trinity_memory': '10G',
						'RepeatMasker': os.path.dirname(os.path.realpath(sys.argv[0]))+'/bin/RepeatMasker/RepeatMasker',
						'RepeatMasker_library': '',
						'TRF': os.path.dirname(os.path.realpath(sys.argv[0]))+'/bin/trf',
						'Blast_folder': os.path.dirname(os.path.realpath(sys.argv[0]))+'/bin/ncbi-blast-2.2.28+/bin/', 
						'Parallel': os.path.dirname(os.path.realpath(sys.argv[0]))+'/bin/parallel',
						'Sample_size': 500000,
						'RM_species' : "All",
						'Sample_number': 2,
						'Trinity_glue' : 1}
	with open('config.ini', 'w') as configfile:
		config.write(configfile)
config.read('config.ini')

print( "                  _             _____ _         _______ ______                   ")
print( "                 | |           |  __ (_)       |__   __|  ____|                  ")
print( "               __| |_ __   __ _| |__) | _ __   ___| |  | |__                     ")
print( "              / _` | '_ \ / _` |  ___/ | '_ \ / _ \ |  |  __|                    ")
print( "             | (_| | | | | (_| | |   | | |_) |  __/ |  | |____                   ")
print( "              \__,_|_| |_|\__,_|_|   |_| .__/ \___|_|  |______|                  ")
print( "                                       | |                                       ")
print( "                                       |_|                                       ")
print( "                                                                                 ")
print( "     De Novo Anssembly and Annotation PIPEline for Transposable Elements         ")
print( "                              v.1.2_04-2016                                      ")
print( "                                                                                 ")
print( "                                                                                                                                                                       ")                                          
print( "   	                                                        ") 
print( "                                                 :@@@@'     ")
print( "                                               ,@@@@@@@@;   ")
print( "                                              +@@@@@@@@@@,  ")
print( "                                            .@@@@@@@@@@@@#  ")
print( "                                    +@#.   '@@@@@@@@@@@@@#  ")
print( "                                   #@@@@+`@@@@@@@@@@@@@@@,  ")
print( "                                   '@@@@@@@@@@@@@@@@@@@@'   ")
print( "                                    :@@@@@@@@@@@@@@@@@@.    ")
print( "                                     :@@@@@@@@@@@@@@@+      ")
print( "                                    #@@@@@@@@@;@@@@@,       ")
print( "                                  ,@@@#`.@@@@@@#,@#         ")
print( "                                 +@@@:    +@@@@@@,          ")
print( "                               .@@@@       #@@@@@@#         ")
print( "                              '@@@;       '@@@@@@@@@        ")
print( "                            `@@@@`      `@@@@`:@@@@@        ")
print( "                           ;@@@'       ;@@@'    +@+         ")
print( "                          @@@@.       @@@@.                 ")
print( "                        :@@@#       :@@@#                   ")
print( "                       #@@@,       #@@@,                    ")
print( "                     ,@@@#`@@'   ,@@@#                      ")
print( "                    +@@@:'@@@@@:+@@@:                       ")
print( "                  .@@@@`@@@@@@@@@@@                         ")
print( "                 '@@@;:@@@@@@@@@@;                          ")
print( "                #@@@`#@@@@@@@@@@`                           ")
print( "               ,@@@;@@@@@@@@@@+                             ")
print( "               #@@@@@@@@@@@@@.                              ")
print( "               @@@@@@@@@@@@#                                ")
print( "              .@@@@@@@@@@@,                                 ")
print( "             +@@@@@@@@@@#                                   ")
print( "             @@@@@@#+;.                                     ")
print( "              +@@;                                          ")                                                
print( "                                                            ")   
print( "           Let's go !!!                                     ")
print( "                                                            ")                                   
                                             

parser = argparse.ArgumentParser(prog='dnaPipeTE.py')
parser.add_argument('-input', action='store', dest='input_file', help='input fastq files (two files for paired data)', nargs='*')
parser.add_argument('-output', action='store', dest='output_folder', help='output folder')
parser.add_argument('-cpu', action='store', default="1", dest='cpu', help='maximum number of cpu to use')
parser.add_argument('-sample_size', action='store', default=config['DEFAULT']['Sample_size'], dest='sample_size', help='number of reads to sample')
parser.add_argument('-sample_number', action='store', default=config['DEFAULT']['Sample_number'], dest='sample_number', help='number of sample to run')
parser.add_argument('-genome_size', action='store', default=0, dest='genome_size', help='size of the genome')
parser.add_argument('-genome_coverage', action='store', default=0.0, dest='genome_coverage', help='coverage of the genome')
parser.add_argument('-RM_lib', action='store', default=config['DEFAULT']['RepeatMasker_library'], dest='RepeatMasker_library', help='path to Repeatmasker library (if not set, the path from the config file is used. The default library is used by default)')
parser.add_argument('-species', action='store', default=config['DEFAULT']['RM_species'], dest='RM_species', help='default RepeatMasker library to use. Must be a valid NCBI for species or clade ex: homo, drosophila, "ciona savignyi". Default All is used')
parser.add_argument('-RM_t', action='store', default=0.0, dest='RM_threshold', help='minimal percentage of query hit on repeat to keep anotation')
#parser.add_argument('-lib', action='store', defaut=config['DEFAULT']['RepeatMasker_library'], dest='RM_library',)
parser.add_argument('-Trin_glue', action='store',default=config['DEFAULT']['Trinity_glue'], dest='Trinity_glue', help='number of reads to join Inchworm (k-mer) contigs')
parser.add_argument('-keep_Trinity_output', action='store_true', default=False, dest='keep_Trinity_output', help='keep Trinity output at the end of the run')

print("Start time: "+time.strftime("%c"))

args = parser.parse_args()

class FastqSamplerToFasta:
	def __init__(self, fastq_files, number, genome_size, genome_coverage, sample_number, output_folder, blast):
		self.number = int(number)
		self.genome_size = int(genome_size)
		self.genome_coverage = float(genome_coverage)
		self.use_coverage = False
		self.fastq_total_size = 0
		if self.genome_size != 0 and self.genome_coverage > 0.0:
			self.use_coverage = True
			self.genome_base = int(float(self.genome_size) * self.genome_coverage)
		self.sample_number = int(sample_number)
		self.output_folder = output_folder
		if not os.path.exists(self.output_folder):
			os.makedirs(self.output_folder)
		self.fastq_R1 = fastq_files[0]
		self.blast_sufix = ""
		if blast:
			self.blast_sufix = "_blast"
		if len(fastq_files) == 1:
			self.paired = False
		else:
			self.fastq_R1 = fastq_files[1]
		self.R1_gz = False
		self.R2_gz = False
		if self.fastq_R1[-3:] == ".gz":
			print("gz compression detected for "+self.fastq_R1)
			self.R1_gz = True
			self.fastq_R1 = self.fastq_R1[:-3]

		if self.paired:
			if self.fastq_R2[-3:] == ".gz":
				print("gz compression detected for "+self.fastq_R2)
				self.R2_gz = True
				self.fastq_R2 = self.fastq_R2[:-3]
		
		self.files = list()
		if not self.test_sampling(blast):
			self.get_sampled_id(self.fastq_R1)
			print("sampling "+str(self.sample_number)+" samples of max "+str(self.number)+" reads to reach coverage...")
			for i in range(self.sample_number):
				if self.R1_gz:
					self.sampling_gz(self.fastq_R1, i)
				else:
					self.sampling(self.fastq_R1, i)
				self.files.append("s"+str(i)+"_"+self.path_leaf(self.fastq_R1)+str(self.blast_sufix)+".fasta")
			if self.paired:
				for i in range(self.sample_number):
					if self.R2_gz:
 						self.sampling_gz(self.fastq_R2, i)
					else:
						self.sampling(self.fastq_R2, i)
					self.files.append("s"+str(i)+"_"+self.path_leaf(self.fastq_R2)+str(self.blast_sufix)+".fasta")
	
	def result(self):
		return(self.files)

	def path_leaf(self, path) :
		head, tail = ntpath.split(path)
		return tail or ntpath.basename(head)

	def get_sampled_id(self, file_name):
		self.tirages = list()
		tirages = list()
		sys.stdout.write("counting reads number...")
		sys.stdout.flush()
		if self.use_coverage:
			np = 0
			size_min = 10 ** 30
			if self.R1_gz:
				with gzip.open(file_name+".gz", 'rt') as file1 :
					for line in file1:
						np += 1
						if np % 4 == 0:
							self.fastq_total_size += len(str(line))
							if len(str(line)) < size_min:
								size_min = len(str(line))
			else:
				with open(file_name, 'r') as file1 :
					for line in file1:
						np += 1
						if np % 4 == 0:
							self.fastq_total_size += len(str(line))
							if len(str(line)) < size_min:
								size_min = len(str(line))
		else:
			if self.R1_gz:
				with gzip.open(file_name+".gz", 'rt') as file1 :
					np = sum(1 for line in file1)
			else:
				with open(file_name, 'r') as file1 :
					np = sum(1 for line in file1)
		np = int((np) / 4)
		sys.stdout.write("\rtotal number of reads: "+str(np)+"\n")
		sys.stdout.flush()
		if self.use_coverage:
			if self.fastq_total_size <= self.genome_base:
				sys.exit("not enought base to sample "+str(self.fastq_total_size)+" vs "+str(self.genome_base)+" to sample")
			self.number = int(float(self.genome_base)/float(size_min))
			if int(self.number)*int(self.sample_number) > np:
				self.number = int(float(np)/float(self.sample_number))
		print( "maximum number of reads to sample: ", str(int(self.number)*int(self.sample_number)), "\nfastq : ", file_name )
		tirages = random.sample(range(np), self.number*self.sample_number)
		for i in range(self.sample_number):
			tirages_sample = tirages[(self.number*i):(self.number*(i+1))]
			tirages_sample.sort()
			self.tirages.extend(tirages_sample)

	def sampling(self, fastq_file, sample_number):
		sys.stdout.write(str(0)+"/"+str(self.number))
		sys.stdout.flush()
		with open(fastq_file, 'r') as fastq_handle :
			self.sampling_sub(fastq_file, fastq_handle, sample_number)

	def sampling_gz(self, fastq_file, sample_number):
		sys.stdout.write(str(0)+"/"+str(self.number))
		sys.stdout.flush()
		with gzip.open(fastq_file+".gz", 'rt') as fastq_handle :
			self.sampling_sub(fastq_file, fastq_handle, sample_number)

	def sampling_sub(self, fastq_file, fastq_handle, sample_number):
		i = 0
		j = self.number*sample_number
		tag = "/s"+str(sample_number)+"_"
		with open(self.output_folder+tag+self.path_leaf(fastq_file)+str(self.blast_sufix)+".fasta", 'w') as output :
			base_sampled = 0
			for line in fastq_handle :
				if (i-1) % 4 == 0 and (i-1)/4 == self.tirages[j]: # if we are at the sequence line in fastq of the read number self.tirages[j]
					output.write(">"+str(j+sample_number*self.number)+"\n"+str(line)) # we write the fasta sequence corresponding
					if self.use_coverage:
						base_sampled += len(str(line))
				if (i-1)/4 == self.tirages[j]:
					j += 1 # we get the number of the next line
					if j % 100 == 0:
						sys.stdout.write("\r"+str(j)+"/"+str(self.number*self.sample_number))
						sys.stdout.flush()
				i += 1
				if self.use_coverage:
					if base_sampled >= self.genome_base:
						break
					if base_sampled >= self.fastq_total_size:
						sys.exit("not enought base to sample "+str(self.fastq_total_size)+" vs "+str(self.genome_base)+" to sample")
				if j >= len(self.tirages):
					break
			sys.stdout.write("\r"+str(base_sampled)+" bases sampled in "+str(j)+" reads \n")
		sys.stdout.write("s_"+self.path_leaf(fastq_file)+str(self.blast_sufix)+" done.\n")

	def test_sampling(self, blast):
		sampling_done = True
		for sample_number in range(self.sample_number):
			tag = "/s"+str(sample_number)+"_"
			if not os.path.isfile(self.output_folder+tag+self.path_leaf(self.fastq_R1)+".fasta") or not os.path.getsize(self.output_folder+tag+self.path_leaf(self.fastq_R1)+".fasta") > 0:
				sampling_done = False
			if self.paired:
				if not os.path.isfile(self.output_folder+tag+self.path_leaf(self.fastq_R2)+".fasta") or not os.path.getsize(self.output_folder+tag+self.path_leaf(self.fastq_R2)+".fasta") > 0:
					sampling_done = False
		for i in range(self.sample_number):
			self.files.append("s"+str(i)+"_"+self.path_leaf(self.fastq_R1)+".fasta")
		if self.paired:
			for i in range(self.sample_number):
				self.files.append("s"+str(i)+"_"+self.path_leaf(self.fastq_R2)+".fasta")
		if sampling_done:
			print("sampling file found, skipping sampling...")
		else:
			self.files = list()
		if blast:
			return False
		return sampling_done

class Trinity:
	def __init__(self, Trinity_path, Trinity_memory, cpu, Trinity_glue, output_folder, sample_files, sample_number):
		self.Trinity_path = str(Trinity_path)
		self.Trinity_memory = str(Trinity_memory)
		self.cpu = int(cpu)
		self.output_folder = str(output_folder)
		self.sample_files = sample_files
		self.sample_number = int(sample_number)
		self.trin_glue = int(Trinity_glue)
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
		trinity = self.Trinity_path+" --seqType fa --JM "+str(self.Trinity_memory)+" --single "+self.output_folder+"/"+self.sample_files[iteration]+" --CPU "+str(self.cpu)+" --min_glue "+str(self.trin_glue)+" --output "+self.output_folder+"/Trinity_run"+str(iteration+1)
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
		if not os.path.isfile(self.output_folder+"/Trinity.fasta") or (os.path.isfile(self.output_folder+"/Trinity.fasta") and not os.path.getsize(self.output_folder+"/Trinity.fasta") > 0):
			trinnity_done = False
		if trinnity_done:
			print("Trinity files found, skipping assembly...")
		return trinnity_done

class RepeatMasker:
	def __init__(self, RepeatMasker_path, RM_library, RM_species, cpu, output_folder, RM_threshold):
		self.RepeatMasker_path = str(RepeatMasker_path)
		self.RM_library = str(RM_library)
		self.cpu =  int(cpu)
		self.output_folder = str(output_folder)
		self.RM_threshold = float(RM_threshold)
		self.RM_species = str(RM_species)
		if not self.test_RepeatMasker():
			self.repeatmasker_run()
			self.contig_annotation()

	def repeatmasker_run(self):
		print("#######################################")
		print("### REPEATMASKER to anotate contigs ###")
		print("#######################################\n")
		repeatmasker = self.RepeatMasker_path+" -pa "+str(self.cpu)+" -s "
		if self.RM_library != "":
			repeatmasker += "-lib "+self.RM_library
		else:
			repeatmasker += "-species "+self.RM_species
		repeatmasker += " "+self.output_folder+"/Trinity.fasta"
		repeatmaskerProcess = subprocess.Popen(str(repeatmasker), shell=True)
		repeatmaskerProcess.wait()
		if not os.path.exists(self.output_folder+"/Annotation"):
			os.makedirs(self.output_folder+"/Annotation")
		line_number = 0
		trinity_out = list()
		with open(self.output_folder+"/Trinity.fasta.out", 'r') as trinity_handle:
			for line in trinity_handle:
				line_number += 1
				if line_number > 3:
					line = line.split()
					# we swap the start and left column if we are revese
					if line[8] == "C":
						tmp = line[13]
						line[13] = line[11][1:-1]
						line[11] = tmp
					else:
						line[13] = line[13][1:-1]
					trinity_out_line = list()
					trinity_out_line.append(line[4])
					# size of the dnaPipeTE contig
					trinity_out_line.append(int(line[6]) + int(line[7][1:-1]))
					# percent of hit on the query
					trinity_out_line.append(float(int(line[6]) - int(line[5])) / float(int(line[6]) + int(line[7][1:-1])))
					# ET name
					trinity_out_line.append(line[9])
					# class name
					trinity_out_line.append(line[10])
					# target size
					trinity_out_line.append(int(line[12]) + int(line[13]))
					# query position
					trinity_out_line.append("["+line[11]+"-"+line[12]+"]")
					# percent of hit on the target
					trinity_out_line.append(float(int(line[12]) - int(line[11])) / float(int(line[12]) + int(line[13])))
					trinity_out_line.append(int(line[0]))
					trinity_out.append(list(trinity_out_line))
		print(str(line_number)+" line read, sorting...")
		trinity_out = sorted(trinity_out, key=lambda x: (x[0], -x[8]))
		prev_contig = ""
		print("sort done, filtering...")
		with open(self.output_folder+"/Annotation/one_RM_hit_per_Trinity_contigs", 'w') as output, open(self.output_folder+"/Annotation/Best_RM_annot_80", 'w') as output_80_80, open(self.output_folder+"/Annotation/Best_RM_annot_partial", 'w') as output_partial:
			line_number = 0
			line_number_80 = 0
			line_number_partial = 0
			for trinity_out_line in trinity_out:
				if trinity_out_line[0] != prev_contig:
					prev_contig = trinity_out_line[0]
					if float(trinity_out_line[2]) >= float(self.RM_threshold) :
						for i in trinity_out_line[:-1]:
							output.write(str(i)+"\t")
						output.write("\n")
						line_number += 1
						if float(trinity_out_line[2]) >= 0.80:
							if float(trinity_out_line[7]) >= 0.80:
								for i in trinity_out_line[:-1]:
									output_80_80.write(str(i)+"\t")
								output_80_80.write("\n")
								line_number_80 += 1
							if float(trinity_out_line[7]) < 0.80:
								for i in trinity_out_line[:-1]:
									output_partial.write(str(i)+"\t")
								output_partial.write("\n")
								line_number_partial += 1
		print(str(line_number)+" lines in one_RM_hit_per_Trinity_contigs")
		print(str(line_number_80)+" lines in Best_RM_annot_80")
		print(str(line_number_partial)+" lines in Best_RM_annot_partial")
		print("Done")

	def contig_annotation(self):
		print("#########################################")
		print("### Making contigs annotation from RM ###")
		print("#########################################")

		annotation = ""
		for super_familly in ["LTR", "LINE", "SINE", "DNA","MITE","Low_complexity","Satellite","Helitron", "Simple_repeat", "rRNA"] :
			# fais une liste de fichier headers pour aller récupérer les contigs
			annotation += "awk '{print $1 \"\\t\" $5}' "+self.output_folder+"/Annotation/one_RM_hit_per_Trinity_contigs | grep '"+super_familly+"' | awk '{print$1}' > "+self.output_folder+"/Annotation/"+super_familly+".headers && "
			# récupère et annote les contigs de Trinity.fasta selon les meilleurs hits RM
			annotation += "perl -ne 'if(/^>(\S+)/){$c=$i{$1}}$c?print:chomp;$i{$_}=1 if @ARGV' "+self.output_folder+"/Annotation/"+super_familly+".headers "+self.output_folder+"/Trinity.fasta | sed 's/>comp/>"+super_familly+"_comp/g' > "+self.output_folder+"/Annotation/"+super_familly+"_annoted.fasta && "
		annotation += "grep -v 'LTR\|LINE\|SINE\|DNA\|Low_complexity\|Satellite\|Helitron\|Simple_repeat\|rRNA\|MITE' "+self.output_folder+"/Annotation/one_RM_hit_per_Trinity_contigs | awk '{print$1}' > "+self.output_folder+"/Annotation/others.headers && "
		annotation += "perl -ne 'if(/^>(\S+)/){$c=$i{$1}}$c?print:chomp;$i{$_}=1 if @ARGV' "+self.output_folder+"/Annotation/others.headers "+self.output_folder+"/Trinity.fasta | sed 's/>comp/>others_comp/g' >"+self.output_folder+"/Annotation/others_annoted.fasta && "
		annotation += "cat "+self.output_folder+"/Annotation/*.headers > "+self.output_folder+"/Annotation/all_annoted.head && "
		annotation += "perl -ne 'if(/^>(\S+)/){$c=!$i{$1}}$c?print:chomp;$i{$_}=1 if @ARGV' "+self.output_folder+"/Annotation/all_annoted.head "+self.output_folder+"/Trinity.fasta | sed 's/>comp/>na_comp/g' > "+self.output_folder+"/Annotation/unannoted.fasta && "
		annotation += "cat "+self.output_folder+"/Annotation/*_annoted.fasta > "+self.output_folder+"/Annotation/annoted.fasta"
		annotationProcess = subprocess.Popen(str(annotation), shell=True)
		annotationProcess.wait()
		print("Done\n")
		print("")
		print("Making blast sample...")

	def test_RepeatMasker(self):
		files = [self.output_folder+"/Annotation/one_RM_hit_per_Trinity_contigs", 
			self.output_folder+"/Annotation/Best_RM_annot_80-80", 
			self.output_folder+"/Annotation/Best_RM_annot_partial"]
		repeatmasker_done = True
		for output in files:
			if not os.path.isfile(output) or (os.path.isfile(output) and not os.path.getsize(output) > 0):
				print(output)
				repeatmasker_done = False
		if repeatmasker_done:
			print("RepeatMasker files found, skipping Repeatmasker...")
		return repeatmasker_done

class Blast:
	def __init__(self, Blast_path, Parallel_path, cpu, output_folder, sample_number, sample_files, genome_coverage, genome_size):
		self.Blast_path = str(Blast_path)
		self.Parallel_path = str(Parallel_path)
		self.cpu =  int(cpu)
		self.output_folder = str(output_folder)
		self.sample_number = int(sample_number)
		self.sample_files = sample_files
		self.genome_coverage = float(genome_coverage)
		self.genome_size = int(genome_size)
		self.genome_base = int(float(self.genome_size) * self.genome_coverage)
		self.blast1_run()
		self.blast2_run()
		self.blast3_run()
		self.count()

	def blast1_run(self):
		print("#######################################################")
		print("### Blast 1 : raw reads against all repeats contigs ###")
		print("#######################################################")
		if not os.path.isfile(self.output_folder+"/Reads_to_components_Rtable.txt") or not os.path.isfile(self.output_folder+"/blast_out/sorted.reads_vs_Trinity.fasta.blast.out") or (os.path.isfile(self.output_folder+"/Reads_to_components_Rtable.txt") and not os.path.getsize(self.output_folder+"/Reads_to_components_Rtable.txt") > 0) or (os.path.isfile(self.output_folder+"/blast_out/sorted.reads_vs_Trinity.fasta.blast.out") and not os.path.getsize(self.output_folder+"/blast_out/sorted.reads_vs_Trinity.fasta.blast.out") > 0):
			if not os.path.exists(self.output_folder+"/blast_out"):
				os.makedirs(self.output_folder+"/blast_out")
			print("blasting...")		
			blast = "cat "
			# for i in range(0,self.sample_number):
			# 	blast += self.output_folder+"/"+self.sample_files[i]+" "
			blast += self.output_folder+"/"+self.sample_files[0]
			blast += " > "+self.output_folder+"/renamed.blasting_reads.fasta && "
			blast += "grep -c '>' "+self.output_folder+"/renamed.blasting_reads.fasta > "+self.output_folder+"/blast_reads.counts && "
			blast += self.Blast_path+"/makeblastdb -in "+self.output_folder+"/Trinity.fasta -out "+self.output_folder+"/Trinity.fasta -dbtype 'nucl' && "
			blast += "cat "+self.output_folder+"/renamed.blasting_reads.fasta | "+self.Parallel_path+" -j "+str(self.cpu)+" --block 100k --recstart '>' --pipe "+self.Blast_path+"/blastn -outfmt 6 -task dc-megablast -db "+self.output_folder+"/Trinity.fasta -query - > "+self.output_folder+"/blast_out/reads_vs_Trinity.fasta.blast.out"
			blastProcess = subprocess.Popen(str(blast), shell=True)
			blastProcess.wait()
			print("Paring blast1 output...")
			blast = "cat "+self.output_folder+"/blast_out/reads_vs_Trinity.fasta.blast.out | sort -k1,1 -k12,12nr -k11,11n | sort -u -k1,1 > "+self.output_folder+"/blast_out/sorted.reads_vs_Trinity.fasta.blast.out && "
			
			blast += "cat "+self.output_folder+"/blast_out/sorted.reads_vs_Trinity.fasta.blast.out | awk '{print $2\"\\t\"$3\"\\t\"$4}' | sed 's/_/\t/g' > "+self.output_folder+"/Reads_to_components_Rtable.txt"
			blastProcess = subprocess.Popen(str(blast), shell=True)
			blastProcess.wait()
		else:
			print("Blast 1 files found, skipping Blast 1 ...")

	def blast2_run(self):
		print("###################################################")
		print("### Blast 2 : raw reads against annoted repeats ###")
		print("###################################################")
		if not os.path.isfile(self.output_folder+"/blast_out/unmatching_reads1.fasta") or (os.path.isfile(self.output_folder+"/blast_out/unmatching_reads1.fasta") and not os.path.getsize(self.output_folder+"/blast_out/unmatching_reads1.fasta") > 0):
			if not os.path.exists(self.output_folder+"/blast_out"):
				os.makedirs(self.output_folder+"/blast_out")
			print("blasting...")
			blast = "cat "+self.output_folder+"/Annotation/annoted.fasta "+os.path.dirname(os.path.realpath(sys.argv[0]))+"/bin/RepeatMasker/Libraries/2*/root/specieslib > "+self.output_folder+"/blast_out/blast2_db.fasta && "  #merge annotated contigs and repbase if speciedslib has been generated by a default run of RepeatMasker
			blast += self.Blast_path+"/makeblastdb -in "+self.output_folder+"/blast_out/blast2_db.fasta -out "+self.output_folder+"/blast_out/blast2_db.fasta -dbtype 'nucl' && "
			blast += "cat "+self.output_folder+"/renamed.blasting_reads.fasta | "+self.Parallel_path+" -j "+str(self.cpu)+" --block 100k --recstart '>' --pipe "+self.Blast_path+"/blastn -outfmt 6 -task dc-megablast -db "+self.output_folder+"/blast_out/blast2_db.fasta -query - > "+self.output_folder+"/blast_out/reads_vs_annoted.blast.out"
			blastProcess = subprocess.Popen(str(blast), shell=True)
			blastProcess.wait()
			print("Paring blast2 output...")
			blast = "sort -k1,1 -k12,12nr -k11,11n "+self.output_folder+"/blast_out/reads_vs_annoted.blast.out > "+self.output_folder+"/blast_out/int.reads_vs_annoted.blast.out"
			blastProcess = subprocess.Popen(str(blast), shell=True)
			blastProcess.wait()
			sortblast = "python3 ./blast_sorter.py --input_dir "+self.output_folder+"/blast_out/int.reads_vs_annoted.blast.out > "+self.output_folder+"/blast_out/s.reads_vs_annoted.blast.out" + " ; rm " +self.output_folder+"/blast_out/int.reads_vs_annoted.blast.out &&"
			sortblast += "awk '/comp/ {print $0; next} /#/ {gsub(\".*#\",\"\",$2); gsub(\"/\",\"_comp_\",$2); print $0 }' "+self.output_folder+"/blast_out/s.reads_vs_annoted.blast.out > "+self.output_folder+"/blast_out/sorted.reads_vs_annoted.blast.out"+" ; rm " +self.output_folder+"/blast_out/s.reads_vs_annoted.blast.out" #rename repbase hit to fit for counting
			sortBlastProcess = subprocess.Popen(str(sortblast),shell=True)
			sortBlastProcess.wait()
			print("Selecting non-matching reads for blast3")
			blast = "awk '{print$1}' "+self.output_folder+"/blast_out/sorted.reads_vs_annoted.blast.out > "+self.output_folder+"/blast_out/matching_reads.headers && "
			blast += "perl -ne 'if(/^>(\S+)/){$c=!$i{$1}}$c?print:chomp;$i{$_}=1 if @ARGV' "+self.output_folder+"/blast_out/matching_reads.headers "+self.output_folder+"/renamed.blasting_reads.fasta > "+self.output_folder+"/blast_out/unmatching_reads1.fasta"
			blastProcess = subprocess.Popen(str(blast), shell=True)
			blastProcess.wait()
		else:
			print("Blast 2 files found, skipping Blast 2 ...")

	def blast3_run(self):
		print("#####################################################")
		print("### Blast 3 : raw reads against unannoted repeats ###")
		print("#####################################################")
		if not os.path.isfile(self.output_folder+"/blast_out/sorted.reads_vs_unannoted.blast.out") or (os.path.isfile(self.output_folder+"/blast_out/sorted.reads_vs_unannoted.blast.out") and not os.path.getsize(self.output_folder+"/blast_out/sorted.reads_vs_unannoted.blast.out") > 0):
			if not os.path.exists(self.output_folder+"/blast_out"):
				os.makedirs(self.output_folder+"/blast_out")
			print("blasting...")
			blast = ""
			if os.path.isfile(self.output_folder+"/Annotation/unannoted_final.fasta") and os.path.getsize(self.output_folder+"/Annotation/unannoted_final.fasta") > 0:
				blast += self.Blast_path+"/makeblastdb -in "+self.output_folder+"/Annotation/unannoted_final.fasta -out "+self.output_folder+"/blast_out/blast3_db.fasta -dbtype 'nucl' && "
			else:
				blast += self.Blast_path+"/makeblastdb -in "+self.output_folder+"/Annotation/unannoted.fasta -out "+self.output_folder+"/blast_out/blast3_db.fasta -dbtype 'nucl' && "
			blast += "cat "+self.output_folder+"/blast_out/unmatching_reads1.fasta | "+self.Parallel_path+" -j "+str(self.cpu)+" --block 100k --recstart '>' --pipe "+self.Blast_path+"/blastn -outfmt 6 -task dc-megablast -db "+self.output_folder+"/blast_out/blast3_db.fasta -query - > "+self.output_folder+"/blast_out/reads_vs_unannoted.blast.out"
			blastProcess = subprocess.Popen(str(blast), shell=True)
			blastProcess.wait()
			print("Paring blast3 output...")
			blast = "sort -k1,1 -k12,12nr -k11,11n "+self.output_folder+"/blast_out/reads_vs_unannoted.blast.out > "+self.output_folder+"/blast_out/int.reads_vs_unannoted.blast.out"
			blastProcess = subprocess.Popen(str(blast), shell=True)
			blastProcess.wait()
			sortblast = "python3 ./blast_sorter.py --input_dir "+self.output_folder+"/blast_out/int.reads_vs_unannoted.blast.out > "+self.output_folder+"/blast_out/sorted.reads_vs_unannoted.blast.out" + " ; rm " +self.output_folder+"/blast_out/int.reads_vs_annoted.blast.out"
			sortBlastProcess = subprocess.Popen(str(sortblast),shell=True)
			sortBlastProcess.wait()
		else:
			print("Blast 3 files found, skipping Blast 3 ...")

	def count(self):
		print("#######################################################")
		print("### Estimation of Repeat content from blast outputs ###")
		print("#######################################################")
		count = dict()
		if self.genome_size != "":
			with open(self.output_folder+"/blast_out/sorted.reads_vs_annoted.blast.out", "r") as counts2_file:
				for line in counts2_file:
					to_add = int(line.split()[3])
					#takes first part before the "_"
					line = line.split()[1].split("_")[0]
					if line[0:3] == "comp":
						#replaces column 2 by "comp"
						line = "comp"
					if line in count:
						count[line] += to_add
					else:
						count[line] = to_add
			count["na"] = 0
			with open(self.output_folder+"/blast_out/sorted.reads_vs_unannoted.blast.out", "r") as counts2_file:
				for line in counts2_file:
					to_add = int(line.split()[3])
					count["na"] += to_add
			with open(self.output_folder+"/Counts.txt", "w") as counts1_file:
				for super_familly in ["LTR", "LINE", "SINE", "DNA", "MITE", "Helitron","rRNA", "Low_Complexity", "Satellite", "Tandem_repeats", "Simple_repeat", "others", "na"]:
					if super_familly.split("_")[0] in count:
						counts1_file.write(super_familly+"\t"+str(count[super_familly.split("_")[0]])+"\n")
					else:
						counts1_file.write(super_familly+"\t0\n")
				if "comp" in count:
					counts1_file.write("Others\t"+str(count["comp"])+"\n")
				else:
					counts1_file.write("Others\t0\n")
				# with open(self.output_folder+"/blast_reads.counts", "r") as counts2_file:
				# 	line = counts2_file.readline()
					countbase_command = "awk 'NR%2 == 0 {basenumber += length($0)} END {print basenumber}' "+self.output_folder+"/renamed.blasting_reads.fasta"
					countbase = subprocess.check_output(str(countbase_command), shell=True)
					# decode string to urf-8
					countbase = countbase.decode('utf8')
					counts1_file.write("Total\t"+str(countbase)+"\n")
		else:
			with open(self.output_folder+"/blast_out/sorted.reads_vs_annoted.blast.out", "r") as counts2_file:
				for line in counts2_file:
					line = line.split()[1].split("_")[0]
					if line[0:3] == "comp":
						line = "comp"
					if line in count:
						count[line] += 1
					else:
						count[line] = 1
			count["na"] = 0
			with open(self.output_folder+"/blast_out/sorted.reads_vs_unannoted.blast.out", "r") as counts2_file:
				for line in counts2_file:
					count["na"] += 1
			with open(self.output_folder+"/Counts.txt", "w") as counts1_file:
				for super_familly in ["LTR", "LINE", "SINE", "DNA", "MITE", "Helitron","rRNA", "Low_Complexity", "Satellite", "Tandem_repeats", "Simple_repeat", "others", "na"]:
					if super_familly.split("_")[0] in count:
						counts1_file.write(super_familly+"\t"+str(count[super_familly.split("_")[0]])+"\n")
					else:
						counts1_file.write(super_familly+"\t0\n")
				if "comp" in count:
					counts1_file.write("Others\t"+str(count["comp"])+"\n")
				else:
					counts1_file.write("Others\t0\n")
					with open(self.output_folder+"/blast_reads.counts", "r") as counts2_file:
						line = counts2_file.readline()
						counts1_file.write("Total\t"+str(line)+"\n")			
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
	def __init__(self, output_folder, genome_size, genome_coverage):
		self.output_folder = str(output_folder)
		self.genome_coverage = float(genome_coverage)
		self.genome_size = int(genome_size)
		self.genome_base = int(float(self.genome_size) * self.genome_coverage)
		self.run()

	def run(self):
		print("#########################################")
		print("### OK, lets build some pretty graphs ###")
		print("#########################################")
		print("Drawing graphs...")
		graph = os.path.dirname(os.path.realpath(sys.argv[0]))+"/graph.R "+self.output_folder+" Reads_to_components_Rtable.txt blast_reads.counts "+str(self.genome_base)+" && "
		graph += "cat "+self.output_folder+"/reads_per_component_sorted.txt | sort -k1,1 > "+self.output_folder+"/sorted_reads_per_component && "
		graph += "join -a1 -12 -21 "+self.output_folder+"/sorted_reads_per_component "+self.output_folder+"/Annotation/one_RM_hit_per_Trinity_contigs -o 1.3,1.5,1.1,2.2,2.4,2.5,2.3 | sort -k1,1nr > "+self.output_folder+"/reads_per_component_and_annotation && "
		graph += "rm "+self.output_folder+"/reads_per_component_sorted.txt "+self.output_folder+"/sorted_reads_per_component && "
		graph += os.path.dirname(os.path.realpath(sys.argv[0]))+"/pieChart.R "+self.output_folder+" Counts.txt "+os.path.dirname(os.path.realpath(sys.argv[0]))+"/pieColors && "
		graph += "cat "+self.output_folder+"/blast_out/sorted.reads_vs_Trinity.fasta.blast.out | sort -k2,2 > "+self.output_folder+"/Annotation/sorted_blast3 && "
		graph += "join -12 -21 "+self.output_folder+"/Annotation/sorted_blast3 "+self.output_folder+"/Annotation/one_RM_hit_per_Trinity_contigs -o 1.3,2.4,2.5 | awk '/LINE/ { print $0 \"\\t\" $3; next} /LTR/ {print $0 \"\\t\" $3; next} /SINE/ {print $0 \"\\tSINE\"; next} /DNA/ {print $0 \"\\tDNA\"; next} /MITE/ {print $0 \"\\tMITE\";next} {print $0 \"\\tOther\"}' | grep 'LINE\|SINE\|LTR\|DNA\|MITE\|Helitron' | sed 's/Unknow\//DNA\//g' > "+self.output_folder+"/reads_landscape && "
		graph += "cat "+self.output_folder+"/reads_landscape | awk '{print $3}' | sed 's/Unknow\//DNA\//g' | sort -u -k1,1 > "+self.output_folder+"/sorted_families && "
		graph += "sort -k 1,1 "+os.path.dirname(os.path.realpath(sys.argv[0]))+"/new_list_of_RM_superclass_colors_sortedOK >"+self.output_folder+"/colors &&"
		graph += "join -11 -21 "+self.output_folder+"/sorted_families "+self.output_folder+"/colors | awk '{print $1 \"\\t\" $2 \"\\t\\\"\"$3\"\\\"\"}' | sort -k2,2 > "+self.output_folder+"/factors_and_colors && "
		graph += os.path.dirname(os.path.realpath(sys.argv[0]))+"/landscapes.R "+self.output_folder+"/reads_landscape "+self.output_folder+"/factors_and_colors && "
		graph += "mv "+os.path.dirname(os.path.realpath(sys.argv[0]))+"/landscape.pdf "+self.output_folder+"/ && "
		graph += "rm "+os.path.dirname(os.path.realpath(sys.argv[0]))+"/Rplots.pdf &&"
		graph += "rm "+self.output_folder+"/colors"
		# print(graph)
		graphProcess = subprocess.Popen(str(graph), shell=True)
		graphProcess.wait()
		print("Done")

#program execution:
Sampler = FastqSamplerToFasta(args.input_file, args.sample_size, args.genome_size, args.genome_coverage, args.sample_number, args.output_folder, False)
sample_files = Sampler.result()
Trinity(config['DEFAULT']['Trinity'], config['DEFAULT']['Trinity_memory'], args.cpu, config['DEFAULT']['Trinity_glue'], args.output_folder, sample_files, args.sample_number)
RepeatMasker(config['DEFAULT']['RepeatMasker'], args.RepeatMasker_library, args.RM_species, args.cpu, args.output_folder, args.RM_threshold)
Sampler_blast = FastqSamplerToFasta(args.input_file, args.sample_size, args.genome_size, args.genome_coverage, 1, args.output_folder, True)
sample_files_blast = Sampler_blast.result()
Blast(config['DEFAULT']['Blast_folder'], config['DEFAULT']['Parallel'], args.cpu, args.output_folder, 1, sample_files_blast, args.genome_coverage, args.genome_size)
Graph(args.output_folder, args.genome_size, args.genome_coverage)

if not args.keep_Trinity_output:
	print("Removing Trinity runs files...")
	cleaning = "find "+str(args.output_folder)+"/Trinity_run* -delete"
	cleaningProcess = subprocess.Popen(str(cleaning), shell=True)
	cleaningProcess.wait()
	print("done")
print("Finishin time: "+time.strftime("%c"))
print("########################")
print("#   see you soon !!!   #")
print("########################")
