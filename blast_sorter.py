#!/usr/bin/python3
#########################
# 12 avril 2016 Lyon ####
# Lannes Romain		#####
#########################

######################## IMPORT ################## 
import argparse

########################## ARGUMENTS ################## 
parser = argparse.ArgumentParser(description='sorting blast input \
keeping best score removing overlapping hit use redirection for output >')

parser.add_argument( '--input_dir', required=True, help='input directory')

args = parser.parse_args()

################## FUNCTION ######################
def match_overlap(line_split, liste):
	# return true if the line overlap previous match 
	# no need to check score sequence are sorted by score
	# transtypage because value are string....
	lineStart = int(line_split[6])
	lineEnd = int(line_split[7])
	for element in liste:
		elemStart = int(element[6])
		elemEnd = int(element[7])
		if elemStart > lineEnd:
			pass
		elif elemEnd < lineStart:
			pass
		else:
			return True
	return False
	
##################  MAIN ######################
# Opening the file on a with to avoid problem in case of problem

with open(args.input_dir, 'r') as blast:
	# init on first line if there is a header the script wont work 
	first_line = blast.readline()
	# init a list will contain all unoverlaping query for a taget
	liste_query = [first_line.split('\t')]
	# the first query
	query = first_line.split('\t')[0]

	for line in blast:
		ligne_split = line.split('\t')
		# if same query
		if ligne_split[0] == query:
			# test if overlap and add the line to liste_query if not 
			if match_overlap(line_split=ligne_split, liste=liste_query) == False:
				liste_query.append(ligne_split)
				
		else:
			# print result for this query
			for element in liste_query:
				print('\t'.join(element),end='')
			# new query 
			liste_query = [ligne_split]
			query = ligne_split[0]
			
