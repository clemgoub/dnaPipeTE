#!/usr/bin/perl
#
# assemblathon_stats.pl
#
# A script to calculate a basic set of metrics from a genome assembly
#
# Author: Keith Bradnam, Genome Center, UC Davis
# This work is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
# 
# Last updated by: $Author: keith $
# Last updated on: $Date: 2011/10/13 00:07:00 $

use strict;
use warnings;
use FAlite;
use Getopt::Long;
use List::Util qw(sum max min);

###############################################
# 
#  C o m m a n d   l i n e   o p t i o n s
#
###############################################

my $limit;       # limit processing of data to first $limit sequences (for quick testing)
my $graph;       # produce some output ready for Excel or R
my $csv;         # produce CSV output file of results
my $n_limit;     # how many N characters should be used to split scaffolds into contigs
my $genome_size; # estimated or known genome size (will be used for some stats)
 
GetOptions ("limit=i"       => \$limit,
			"csv"           => \$csv, 
			"graph"         => \$graph,
			"n=i"           => \$n_limit,
			"genome_size=i" => \$genome_size);

# set defaults
$limit = 1000000000 if (!$limit);
$n_limit = 25       if (!$n_limit);


# check we have a suitable input file
my $usage = "Usage: assemblathon_stats.pl <assembly_scaffolds_file>
options:
	-limit <int> limit analysis to first <int> sequences (useful for testing)
	-csv         produce a CSV output file of all results
	-graph       produce a CSV output file of NG(X) values (NG1 through to NG99), suitable for graphing
	-n <int>     specify how many consecutive N characters should be used to split scaffolds into contigs
	-genome_size <int> estimated or known genome size
";

die "$usage" unless (@ARGV == 1);
my ($file) = @ARGV;

###############################################
# 
#  S o m e   G l o b a l   v a r i a b l e s
#
###############################################

my $scaffolded_contigs = 0;				# how many contigs that are part of scaffolds (sequences must have $n_limit consecutive Ns)
my $scaffolded_contig_length = 0;		# total length of all scaffolded contigs
my $unscaffolded_contigs = 0;			# how many 'orphan' contigs, not part of a scaffold
my $unscaffolded_contig_length = 0;		# total length of all contigs not part of scaffold
my $w = 60;								# formatting width for output
my %data;								# data structure to hold all sequence info key is either 'scaffold', 'contig' or intermediate', values are seqs & length arrays
my (@results, @headers);				# arrays to store results (for use with -csv option)
	
	
	
# make first loop through file, capture some basic info and add sequences to arrays
process_FASTA($file);

print "\n---------------- Information for assembly \'$file\' ----------------\n\n";

if(defined($genome_size)){
	my $mbp_size = sprintf("%.2f", $genome_size / 1000000);
	printf "%${w}s %10s\n", "Assumed genome size (Mbp)", $mbp_size;
}

# produce scaffold statistics
sequence_statistics('scaffold');

# produce a couple of intermediate statistics based on scaffolded contigs vs unscaffolded contigs
sequence_statistics('intermediate');	

# finish with contig stats
sequence_statistics('contig');

# produce CSV output if required
write_csv($file) if ($csv);

exit(0);



##########################################
#
#
#    S  U  B  R  O  U  T  I  N  E  S
#
#
##########################################


##########################################
#    M A I N  loop through FASTA file
##########################################

sub process_FASTA{
	
	my ($seqs) = @_;
	
	my $input;
	
	# if dealing with gzip file, treat differently
	if($seqs =~ m/\.gz$/){
		open($input, "gunzip -c $seqs |") or die "Can't open a pipe to $seqs\n";
	} else{
		open($input, "<", "$seqs") or die "Can't open $seqs\n";
	}

	my $fasta = new FAlite(\*$input);

	# want to keep track of various contig + scaffold counts
	my $seq_count = 0;

	while(my $entry = $fasta->nextEntry){
	    my $seq = uc($entry->seq);
		my $length = length($seq);
		$seq_count++;

		# everything gets pushed to scaffolds array
		push(@{$data{scaffold}{seqs}},$seq);	
		push(@{$data{scaffold}{lengths}},$length);	
		
		# if there are not at least 25 consecutive Ns in the sequence we need to split it into contigs
		# otherwise the sequence must be a contig itself and it still needs to be put in @contigs array
		if ($seq =~ m/N{$n_limit}/){
			
			# add length to $scaffolded_contig_length
			$scaffolded_contig_length += $length;
			
			# loop through all contigs that comprise the scaffold
			foreach my $contig (split(/N{25,}/, $seq)){
				$scaffolded_contigs++;
				my $length = length($contig);				
				push(@{$data{contig}{seqs}},$contig);	
				push(@{$data{contig}{lengths}},$length);	
			}
		} else {
			# must be here if the scaffold is actually just a contig (or is a scaffold with < 25 Ns)
			$unscaffolded_contigs++;
			$unscaffolded_contig_length += $length;
			push(@{$data{contig}{seqs}},$seq);	
			push(@{$data{contig}{lengths}},$length);	
		}	
		# for testing, just use a few sequences
		last if ($seq_count >= $limit);
		
	}
	close($input);
}


##########################################
#    Calculate basic assembly metrics
##########################################

sub sequence_statistics{
	my ($type) = @_;
	
	print "\n";
	
	# need descriptions of each result
	my $desc;
	
	# there are just a couple of intermediate level statistics to print
	if($type eq 'intermediate'){
		my $total_size = sum(@{$data{scaffold}{lengths}});
		
		# now calculate percentage of assembly that is accounted for by scaffolded contigs
		my $percent = sprintf("%.1f",($scaffolded_contig_length / $total_size) * 100);
		$desc = "Percentage of assembly in scaffolded contigs";
		printf "%${w}s %10s\n", $desc, "$percent%";		
		store_results($desc, $percent) if ($csv);

		# now calculate percentage of assembly that is accounted for by unscaffolded contigs
		$percent = sprintf("%.1f",($unscaffolded_contig_length / $total_size) * 100);
		$desc = "Percentage of assembly in unscaffolded contigs";
		printf "%${w}s %10s\n", $desc, "$percent%";
		store_results($desc, $percent) if ($csv);


		# statistics that describe N regions that join contigs in scaffolds

		# get number of breaks
		my $contig_count = scalar(@{$data{contig}{lengths}});
		my $scaffold_count = scalar(@{$data{scaffold}{lengths}});
		my $average_contigs_per_scaffold = sprintf("%.1f",$contig_count / $scaffold_count);
		$desc = "Average number of contigs per scaffold";
		printf "%${w}s %10s\n", $desc, $average_contigs_per_scaffold;
		store_results($desc, $average_contigs_per_scaffold) if ($csv);
		
		# now calculate average length of break between contigs
		# just find all runs of Ns in scaffolds (>=25) and calculate average length
		my @contig_breaks;
		foreach my $scaffold (@{$data{scaffold}{seqs}}){
			while($scaffold =~ m/(N{25,})/g){
				push(@contig_breaks, length($1));
			}
		}	
		# set break size to zero if there are no Ns in scaffolds
		my $average_break_length;
		
		if(@contig_breaks == 0){
			$average_break_length = 0;
		} else{			
			$average_break_length = sum(@contig_breaks) / @contig_breaks;
		}
		$desc = "Average length of break (>25 Ns) between contigs in scaffold";
		printf "%${w}s %10d\n", $desc, $average_break_length;
		store_results($desc, $average_break_length) if ($csv);
		return();
	}
	
	
	# n
	my $count = scalar(@{$data{$type}{lengths}});
	$desc = "Number of ${type}s";
	printf "%${w}s %10d\n", $desc, $count;
	store_results($desc, $count) if ($csv);
	
	
	
	# more contig details (only for contigs)
	if ($type eq 'contig'){
		$desc = "Number of contigs in scaffolds";
		printf "%${w}s %10d\n",$desc, $scaffolded_contigs;
		store_results($desc, $scaffolded_contigs) if ($csv);
		
		$desc = "Number of contigs not in scaffolds";
		printf "%${w}s %10d\n", $desc,$unscaffolded_contigs;
		store_results($desc, $unscaffolded_contigs) if ($csv);
	}


	# total size of sequences
	my $total_size = sum(@{$data{$type}{lengths}});
	$desc = "Total size of ${type}s";
	printf "%${w}s %10d\n", $desc, $total_size;
	store_results($desc, $total_size) if ($csv);


	# For scaffold data only, can caluclate the percentage of known genome size 
	if ($type eq 'scaffold' && defined($genome_size)){		
		my $percent = sprintf("%.1f",($total_size / $genome_size) * 100);
		$desc = "Total scaffold length as percentage of assumed genome size";
		printf "%${w}s %10s\n", $desc, "$percent%";
		store_results($desc, $percent) if ($csv);		
	}
		
	
	# longest and shortest sequences
	my $max = max(@{$data{$type}{lengths}});
	$desc = "Longest $type";
	printf "%${w}s %10d\n", $desc, $max;
	store_results($desc, $max) if ($csv);

	my $min = min(@{$data{$type}{lengths}});		
	$desc = "Shortest $type";
	printf "%${w}s %10d\n", $desc, $min;
	store_results($desc, $min) if ($csv);

	
	# find number of sequences above certain sizes
	my %sizes_to_shorthand = (1000     => '1K',
							  10000    => '10K',
							  100000   => '100K',
							  1000000  => '1M',
							  10000000 => '10M');

	foreach my $size qw(1000 10000 100000 1000000 10000000){
		my $matches = grep { $_ > $size } @{$data{$type}{lengths}};
		my $percent = sprintf("%.1f", ($matches / $count) * 100);

		$desc = "Number of ${type}s > $sizes_to_shorthand{$size} nt";
		printf "%${w}s %10d %5s%%\n", $desc, $matches, $percent;
		store_results($desc, $matches)  if ($csv);

		$desc = "Percentage of ${type}s > $sizes_to_shorthand{$size} nt";
		store_results($desc, $percent)  if ($csv);	}
	
	
	# mean sequence size
	my $mean = sprintf("%.0f",$total_size / $count);
	$desc = "Mean $type size";
	printf "%${w}s %10d\n", $desc, $mean;
	store_results($desc, $mean) if ($csv);

	# median sequence size
    my $median = (sort{$a <=> $b} @{$data{$type}{lengths}})[$count/2];
	$desc = "Median $type size";
	printf "%${w}s %10d\n", $desc, $median;
	store_results($desc, $median) if ($csv);
	
	
	
	##################################################################################
 	# 
	# N50 values
	#
	# Includes N(x) values, NG(x) (using assumed genome size)
	# and L(x) values (number of sequences larger than or equal to N50 sequence size)
	##################################################################################

	# keep track of cumulative assembly size (starting from smallest seq)
	my $running_total = 0;
	
	# want to store all N50-style values from N1..N100. First target size to pass is N1
	my $n_index = 1;
	my @n_values;
	my $n50_length = 0;

	my $i = 0;

	my $x = $total_size * 0.5;
	# start with longest lengths scaffold/contig
	foreach my $length (reverse sort{$a <=> $b} @{$data{$type}{lengths}}){
		$i++;
		$running_total += $length;

		# check the current sequence and all sequences shorter than current one
		# to see if they exceed the current NX value
		while($running_total > int (($n_index / 100) * $total_size)){	
			if ($n_index == 50){
				$n50_length = $length;
				$desc = "N50 $type length";
				printf "%${w}s %10d\n", $desc, $length;
				store_results($desc, $length) if ($csv);

				# L50 = number of scaffolds/contigs that are longer than or equal to the N50 size
				$desc = "L50 $type count";				
				printf "%${w}s %10d\n","L50 $type count", $i;
				store_results($desc, $i) if ($csv);
			}
			$n_values[$n_index] = $length;
			$n_index++;
		}		
	}
	
	my @ng_values;

	# do we have an estimated/known genome size to work with?
	if(defined($genome_size)){
		my $ng_index = 1;
		my $ng50_length = 0;
		
		$running_total = 0;
		$i = 0;
		
		foreach my $length (reverse sort{$a <=> $b} @{$data{$type}{lengths}}){
			$i++;
			$running_total += $length;
		
			# now do the same for NG values, using assumed genome size
			while($running_total > int (($ng_index / 100) * $genome_size)){	
				if ($ng_index == 50){
					$ng50_length = $length;
					$desc = "NG50 $type length";
					printf "%${w}s %10d\n", $desc, $length;
					store_results($desc, $length) if ($csv);
		
					$desc = "LG50 $type count";				
					printf "%${w}s %10d\n", $desc, $i;				
					store_results($desc, $i) if ($csv);
				}
				$ng_values[$ng_index] = $length;
				$ng_index++;
			}		
		}
		
		
		my $n50_diff = abs($ng50_length - $n50_length);
		$desc = "N50 $type - NG50 $type length difference";
		printf "%${w}s %10d\n", $desc, $n50_diff;
		store_results($desc, $n50_diff) if ($csv);
	}
	# add final value to @n_values and @ng_values which will just be the shortest sequence
#	$n_values[100] = $min;
#	$ng_values[100] = $min;
	

	# base frequencies
	my %bases;

    my $seq = join('',@{$data{$type}{seqs}});  
	my $length = length($seq);

    # count mononucleotide frequencies
    $bases{A} = ($seq =~ tr/A/A/); 
    $bases{C} = ($seq =~ tr/C/C/); 
    $bases{G} = ($seq =~ tr/G/G/); 
    $bases{T} = ($seq =~ tr/T/T/); 
    $bases{N} = ($seq =~ tr/N/N/);
	
	my $base_count = 0;
	foreach my $base qw (A C G T N){
		my $percent = sprintf("%.2f", ($bases{$base} / $length) * 100);
		$desc = "$type %$base";
		printf "%${w}s %10s\n", $desc, $percent;
		store_results($desc, $percent) if ($csv);
		$base_count += $bases{$base};
	}
	
    # calculate remainder ('other) in case there are other characters present
	my $other = $length - $base_count;
	my $percent = sprintf("%.2f", ($other / $length) * 100);
	$desc = "$type %non-ACGTN";
	printf "%${w}s %10s\n",$desc, $percent;
	store_results($desc, $percent) if ($csv);

	$desc = "Number of $type non-ACGTN nt";
	printf "%${w}s %10d\n",$desc, $other;
	store_results($desc, $other) if ($csv);


	# anything to dump for graphing?
	if($graph){
		
		# create new output file name
		my $file_name = $file;
		$file_name =~ s/\.gz$//;
		$file_name =~ s/\.(fa|fasta)$//;
		$file_name .= ".${type}.NG50.csv";
		
		open(my $out, ">", "$file_name") or die "Can't create $file_name\n";
		print $out join (',',"Assembly",1..99), "\n";
	
		# make some guesses of what might constitute the unique assembly ID
		my $assembly_ID = $file;
		($assembly_ID) = $file =~ m/^([A-Z]\d{1,2})_/ if ($file =~ m/^[A-Z]\d{1,2}_/);
		($assembly_ID) = $file =~ m/^((bird|snake|fish)_\d+(C|E))_/ if ($file =~ m/^(bird|snake|fish)_\d+C|E_/);
			
		# CSV file, with filename in first column
		print $out "$assembly_ID";

		for (my $i = 1; $i < 100; $i++){
			# higher NG values might not be present if assembly is poor
			if (defined $ng_values[$i]){
				print $out ",$ng_values[$i]";	
			} else{
				print $out ",0";
			}
		}
		print $out "\n";
		close($out);
	}
}

# simple routine to add results to a pair of arrays that will be used for printing results later on
# if -csv option is used
sub store_results{
	my ($desc, $result) = @_;
	
	push(@headers,$desc);
	push(@results,$result);
}

sub write_csv{
	my ($file) = @_;
	
	# create new output file name
	my $output = $file;
	$output =~ s/\.gz$//;
	$output =~ s/\.(fa|fasta)$//;
	$output .= ".csv";
	
	# make some guesses of what might constitute the unique assembly ID
	my $assembly_ID = $file;
	($assembly_ID) = $file =~ m/^([A-Z]\d{1,2})_/ if ($file =~ m/^[A-Z]\d{1,2}_/);
	($assembly_ID) = $file =~ m/^((bird|snake|fish)_\d+(C|E))_/ if ($file =~ m/^(bird|snake|fish)_\d+C|E_/);

	open(my $out, ">", $output) or die "Can't create $output\n";

	print $out "Assembly,";
	foreach my $header (@headers){
		print $out "$header,";
	}
	print $out "\n";
	
	print $out "$assembly_ID,";
	foreach my $result (@results){
		print $out "$result,";
	}
	print $out "\n";
	
	
	close($out);
}
