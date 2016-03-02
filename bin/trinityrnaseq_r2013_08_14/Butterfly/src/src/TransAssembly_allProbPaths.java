
//import java.util.Set;
import java.text.DecimalFormat;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Hashtable;
import java.util.Iterator;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.PriorityQueue;
import java.util.Queue;
import java.util.Set;
import java.util.TreeMap;
import java.util.Vector;

import edu.uci.ics.jung.algorithms.cluster.WeakComponentClusterer;
import edu.uci.ics.jung.algorithms.shortestpath.DijkstraDistance;
import edu.uci.ics.jung.algorithms.shortestpath.DijkstraDistanceWoVer;
import edu.uci.ics.jung.algorithms.shortestpath.DijkstraShortestPath;
import edu.uci.ics.jung.graph.DirectedSparseGraph;
import edu.uci.ics.jung.graph.util.Pair;
import gnu.getopt.Getopt;


import java.io.BufferedReader;
//import java.io.FileNotFoundException;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.IOException;
import java.io.PrintStream;
import java.io.File;
import gnu.getopt.*;

import jaligner.Alignment;

public class TransAssembly_allProbPaths {

	private static final boolean DEBUG = true;
	private static final SeqVertex ROOT = new SeqVertex(-1, "S",Integer.MAX_VALUE);
	private static final SeqVertex T_VERTEX = new SeqVertex(-2, "E");
	private static final int LINE_LEN = 60;

	private static int LAST_ID = -1;
	private static int LAST_REAL_ID = -1;
	private static int MAX_DEPTH = 0;

	private static double EDGE_THR = 0.05; // compares between each edge and its sister edges (u->v; vs all output of u, or all input of v)
	private static double FLOW_THR = 0.02;// compares between each edge and its flow of its vertices (u->v; vs all input of u, or all output of v)

	private static final int COMP_AVG_COV_THR = 1;
	private static final int INITIAL_EDGE_ABS_THR = 0;


	private static int MIN_READ_SUPPORT_THR = 2;
	private static int MIN_OUTPUT_SEQ;

	// Paths Too Similar Settings
	private static int MAX_DIFFS_SAME_PATH = 2;
	private static int DIFFS_WINDOW_SIZE = 100;
	private static int MAX_FINAL_DIFFS_IN_WINDOW = 5;
	private static float MIN_PERCENT_IDENTITY_SAME_PATH = 95.0f;
	private static int MAX_INTERNAL_GAP_SAME_PATH = 10; 


	// Path alignment settings
	//	private static int MAX_INTERNAL_GAP_LENGTH = 20; // minimum cassette exon size that might be skipped in an alt-splice variant.
	private static boolean SMITH_WATERMAN_ALIGN_FLAG = false;
	private static int MAX_SEQ_LEN_DP_ALIGN = 10000; 

	private static boolean MISO_OUTPUT = true;
	//private static boolean USE_PATH_ALIGNMENT = true;

	private static int VERBOSE_LEVEL = 1;
	private static int MAX_PAIR_DISTANCE = 0;
	private static int PATH_REINFORCEMENT_DISTANCE_PERCENT = 25; 
	private static int PATH_REINFORCEMENT_DISTANCE = 0;
	private static int MAX_NUM_PATHS_PER_NODE = 1000;
	private static final int MAX_MM_ALLOWED = 6;
	private static final int EXTREME_EDGE_FLOW_FACTOR = 200;

	// path extension alternative options
	private static final boolean USE_TRIPLETS = false; // do not use.  
	private static boolean ALL_POSSIBLE_PATHS = false; // most lenient form of path validation: all edge combinations allowed.
	private static boolean LENIENT_PATH_CHECKING = false; //  lenient: give benefit of doubt for connections that do not conflict

	// path reinforcement check options
	private static boolean ORIGINAL_PATH_EXTENSIONS = false; // examines paths from nodes to sinks
	private static int K = 0;
	private static boolean GENERATE_FULL_SEQ_GRAPH = false;
	private static boolean GENERATE_MIDDLE_DOT_FILES = false;
	private static boolean COLLAPSE_SNPs = true;
	private static boolean TRIPLET_LOCKING = false; 

	private static boolean FIND_ALSO_DIFF_PATHS = false;

	private static boolean USE_DEGENERATE_CODE = false;
	private static String[] LETTERS = new String[]{"A","C","G","T"};

	private static PrintStream ERR_STREAM;
	private static boolean USE_STDERR = false;
	private static boolean LOG_STDERR = false;

	private static boolean NO_CLEANUP = false; // if set to true, removes input files

	private static boolean RUN_ALL_VS_ALL_FILTER = false;
	private static int ALL_VS_ALL_MAX_DP_LEN = 1000;



	private static int MIN_LONG_READ_LENGTH = 500;
	private static HashMap<PairPath,ArrayList<String>> LONG_READ_PATH_MAP;  // PairPath => ArrayList(long_reads_names)
	private static HashMap<String, PairPath> LONG_READ_NAME_TO_PPath; // string => PairPath

	private static Map<String, String> DEGENERATE_CODE = new HashMap<String, String>() {
		private static final long serialVersionUID = 1L;

		{ 
			put("AG","R");
			put("CT","Y");
			put("CG","S");
			put("AT","W");
			put("GT","K");
			put("AC","M");
			put("CGT","B");
			put("AGT","D");
			put("ACT","H");
			put("ACG","V");
			put("ACGT","N");
		}
	};

	private static Map<String, String> DEGENERATE_CODE_REV = new HashMap<String, String>() {
		private static final long serialVersionUID = 1L;

		{ 
			put("R","AG");
			put("Y","CT");
			put("S","GC");
			put("W","AT");
			put("K","GT");
			put("M","AC");
			put("B","CGT");
			put("D","AGT");
			put("H","ACT");
			put("V","ACG");
			put("N","ACGT");
		}
	};

	//private static Map<String, AlignmentStats> NUM_MATCHES_HASH;
	private static Map<String, AlignmentStats> NUM_MISMATCHES_HASH;




	public static void main(String[] args) throws Exception 
	{
		long totalNumReads = 0;

		String file = "";
		boolean printUsage = false;
		LongOpt[] longopts = new LongOpt[100]; // big enough we don't have to keep incrementing it as our option list grows.
		longopts[0] = new LongOpt("help", LongOpt.NO_ARGUMENT, null, 'h');
		longopts[1] = new LongOpt("use-degenerate-code", LongOpt.OPTIONAL_ARGUMENT, null, 1); 
		longopts[2] = new LongOpt("dont-collapse-snps", LongOpt.OPTIONAL_ARGUMENT, null, 'S'); 
		longopts[3] = new LongOpt("generate-full-sequence-graphs", LongOpt.OPTIONAL_ARGUMENT, null, 'G');
		longopts[4] = new LongOpt("stderr", LongOpt.OPTIONAL_ARGUMENT, null, 2);

		StringBuffer sb = new StringBuffer(0);
		longopts[5] = new LongOpt("edge-thr", LongOpt.OPTIONAL_ARGUMENT, sb, 'E'); 
		longopts[6] = new LongOpt("flow-thr", LongOpt.OPTIONAL_ARGUMENT, sb, 'W'); 
		longopts[7] = new LongOpt("min_per_id_same_path", LongOpt.OPTIONAL_ARGUMENT, null, 3);
		longopts[8] = new LongOpt("max_number_of_paths_per_node", LongOpt.OPTIONAL_ARGUMENT, null, 4);
		longopts[9] = new LongOpt("min_per_align_same_path", LongOpt.OPTIONAL_ARGUMENT, null, 5);
		longopts[10] = new LongOpt("SW", LongOpt.NO_ARGUMENT, null, 6); //SMITH_WATERMAN_ALIGNMENT_FLAG

		longopts[11] = new LongOpt("all_possible_paths", LongOpt.NO_ARGUMENT, null, 7); // hidden option, testing only
		longopts[12] = new LongOpt("lenient_path_extension", LongOpt.NO_ARGUMENT, null, 8); // hidden for now

		longopts[13] = new LongOpt("path_reinforcement_distance", LongOpt.OPTIONAL_ARGUMENT, null, 9);

		longopts[14] = new LongOpt("original_path_extension", LongOpt.OPTIONAL_ARGUMENT, null, 10);
		longopts[15] = new LongOpt("ZIPPER", LongOpt.NO_ARGUMENT, null, 11); // hidden for now
		longopts[16] = new LongOpt("NO_MISO_OUTPUT", LongOpt.NO_ARGUMENT, null, 12); // hidden for now
		longopts[17] = new LongOpt("max_diffs_same_path", LongOpt.OPTIONAL_ARGUMENT, null, 13);
		longopts[18] = new LongOpt("max_internal_gap_same_path", LongOpt.OPTIONAL_ARGUMENT, null, 14);
		longopts[19] = new LongOpt("generate_intermediate_dot_files", LongOpt.NO_ARGUMENT, null, 15);
		longopts[20] = new LongOpt("triplet-lock", LongOpt.NO_ARGUMENT, null, 16);
		longopts[21] = new LongOpt("max_seq_len_DP_align", LongOpt.OPTIONAL_ARGUMENT, null, 17);
		longopts[22] = new LongOpt("no_cleanup", LongOpt.NO_ARGUMENT, null, 18);
		longopts[23] = new LongOpt("log_stderr", LongOpt.NO_ARGUMENT, null, 19);
		longopts[24] = new LongOpt("__REDUCE", LongOpt.NO_ARGUMENT, null, 20); // deprecated
		longopts[25] = new LongOpt("diffs_window_size", LongOpt.OPTIONAL_ARGUMENT, null, 21);
		longopts[26] = new LongOpt("max_final_diffs_in_window", LongOpt.OPTIONAL_ARGUMENT, null, 22);

		Getopt g = new Getopt("TransAssembly", args, "L:F:N:C:V:SGDhO:R:",longopts);
		int c;


		if (MAX_SEQ_LEN_DP_ALIGN < ALL_VS_ALL_MAX_DP_LEN) {
			ALL_VS_ALL_MAX_DP_LEN = MAX_SEQ_LEN_DP_ALIGN;
		}

		while ((c = g.getopt()) != -1)
		{
			switch(c)
			{
			case 1:
				USE_DEGENERATE_CODE = true;
				break;
			case 2:
				USE_STDERR = true;
				break;
			case 3:
				MIN_PERCENT_IDENTITY_SAME_PATH = Float.parseFloat(g.getOptarg());
				break;
			case 4:
				MAX_NUM_PATHS_PER_NODE = Integer.parseInt(g.getOptarg());
				break;
			case 5:
				// no op
				break;
			case 6:
				SMITH_WATERMAN_ALIGN_FLAG = true;
				break;
			case 7:
				ALL_POSSIBLE_PATHS = true;
				break;
			case 8:
				LENIENT_PATH_CHECKING = true;
				break;
			case 9:
				PATH_REINFORCEMENT_DISTANCE = Integer.parseInt(g.getOptarg());
				break;
			case 10:
				ORIGINAL_PATH_EXTENSIONS = true;
				break;
			case 11:
				// available
				break;
			case 12:
				MISO_OUTPUT = false; // hidden option, that will output in MISO format
				break;
			case 13:
				MAX_DIFFS_SAME_PATH = Integer.parseInt(g.getOptarg());
				break;
			case 14:
				MAX_INTERNAL_GAP_SAME_PATH = Integer.parseInt(g.getOptarg());
				break;
			case 15:
				GENERATE_MIDDLE_DOT_FILES = true;
				break;
			case 16:
				TRIPLET_LOCKING = true;
				break;
			case 17:
				MAX_SEQ_LEN_DP_ALIGN = Integer.parseInt(g.getOptarg());
				break;
			case 18:
				NO_CLEANUP = true;
				break;
			case 19:
				LOG_STDERR = true;
				break;
			case 20:
				//RUN_ALL_VS_ALL_FILTER = true;
				break;
			case 21:
				DIFFS_WINDOW_SIZE = Integer.parseInt(g.getOptarg());
				break;
			case 22:
				MAX_FINAL_DIFFS_IN_WINDOW = Integer.parseInt(g.getOptarg());
				break;

			case 'S':
				COLLAPSE_SNPs = false;
				break;
			case 'G':
				GENERATE_FULL_SEQ_GRAPH = true;
				break;

			case 'h':
				printUsage = true;
				break;
			case 'L':
				MIN_OUTPUT_SEQ = Integer.parseInt(g.getOptarg());
				break;

			case 'F':
				MAX_PAIR_DISTANCE = Integer.parseInt(g.getOptarg());
				break;

			case 'N':
				totalNumReads = Long.parseLong(g.getOptarg());
				break;
			case 'V':
				VERBOSE_LEVEL = Integer.parseInt(g.getOptarg());
				break;
			case 'C':
				file = g.getOptarg();
				break;
			case 'D':
				FIND_ALSO_DIFF_PATHS = true;
				break;
			case 'O':
				PATH_REINFORCEMENT_DISTANCE_PERCENT = Integer.parseInt(g.getOptarg());
				break;
			case 'R':
				MIN_READ_SUPPORT_THR = Integer.parseInt(g.getOptarg());
				break;


			case 0:
				switch(Integer.parseInt(sb.toString()))
				{
				case 'E':
					// compares between each edge and its sister edges (u->v; vs all output of u, or all input of v)
					EDGE_THR = Double.parseDouble(g.getOptarg());
					break;

				case 'W':
					// compares between each edge and its flow of its vertices (u->v; vs all input of u, or all output of v)
					FLOW_THR = Double.parseDouble(g.getOptarg());
					break;
				}
				break;
			case '?':
				printUsage = true;
				break; 
				//
			default:
				printUsage = true;
			}
		}

		if (LOG_STDERR)
			ERR_STREAM = new PrintStream(new FileOutputStream(file + ".err"));

		debugMes("Started",10);


		debugMes("using Path alignment for path comparisons", 5);
		debugMes("combine paths if (identity=(numberOfMatches/shorterLen) > " + MIN_PERCENT_IDENTITY_SAME_PATH+"%" +
				" or if we have <= " + MAX_DIFFS_SAME_PATH+ " mismatches) "
				+ "and if we have internal gap lengths <= " + MAX_INTERNAL_GAP_SAME_PATH
				, 5); 


		int path_checking_opt_count = 0;
		if (LENIENT_PATH_CHECKING) {
			debugMes("Path extension mode: lenient.", 5);
			path_checking_opt_count++;
		}
		if (ORIGINAL_PATH_EXTENSIONS) {
			debugMes("Path extension mode: original path extension.", 5);
			path_checking_opt_count++;
		}
		if (ALL_POSSIBLE_PATHS) {
			debugMes("Path extension mode: all possible paths.", 5);
			path_checking_opt_count++;
		}

		if (path_checking_opt_count > 1) {
			System.err.println("Error, cannot enable more than one path checking option.");
			printUsage = true;
		}


		printUsage = printUsage 
				|| file.equals("") 
				|| totalNumReads==0 
				|| MAX_PAIR_DISTANCE == 0 
				|| MIN_READ_SUPPORT_THR < 1;

		if (printUsage)
		{
			System.err.println("");
			System.err.println("########################################################################################");
			System.err.println("#");
			System.err.println("# Required:");
			System.err.println("#  -N  <int>     total number of reads or fragment pairs");
			System.err.println("#  -L  <int>     min length for an assembled sequence to be reported");
			System.err.println("#  -F  <int>     maximum fragment length (extreme dist between paired ends)");
			System.err.println("#  -C  <string>  prefix for component/reads file");
			System.err.println("#  ");
			System.err.println("#  ");
			System.err.println("#  ");
			System.err.println("# Optional:");

			System.err.println("#  ");
			System.err.println("# Graph compaction:");
			System.err.println("#  --edge-thr=<double>                sets the threshold for keeping the edge (u->v), compared to all *output* of u, or all *input* of v");
			System.err.println("#                                        (default: 0.05).");
			System.err.println("#  --flow-thr=<double>                sets the threshold for keeping the edge (u->v), compared to all *input* of u, or all *output* of v");
			System.err.println("#                                        (default: 0.02).");
			System.err.println("#  --use-degenerate-code              use degenerate DNA code ");
			System.err.println("#                                        (default: don't use degenerate DNA code).");
			System.err.println("#  --dont-collapse-snps               don't collapse SNPs into a single letter ");
			System.err.println("#                                        (default: collapse SNPs into a single letter).");
			System.err.println("#  ");

			System.err.println("# Path extension modes:  (default, uses entire graph for validation, which can be slow)");
			System.err.println("      The following options are ordered by decreasing stringency.");
			System.err.println("#  --original_path_extension          examines paths from nodes to sinks, can be very slow");
			System.err.println("#   /compatible_path_extension/       *DEFAULT MODE* read (pair) must be compatible and contain defined minimum extension support for path reinforcement.");
			System.err.println("#  --lenient_path_extension           only the terminal node pair(v-u) require read support");
			System.err.println("#  --all_possible_paths               all edges are traversed, regardless of long-range read path support");
			System.err.println("#  ");

			System.err.println("# Path extension reinforcement requirements");
			System.err.println("#  -R <int>                           minimum read support threshold. Default: 2");
			System.err.println("#  -O <int>                           path reinforcement 'backwards overlap' percent of -F.  Default: (" + PATH_REINFORCEMENT_DISTANCE_PERCENT + ") Not used in --lenient_path_extension mode.");
			System.err.println("#      or");
			System.err.println("#  --path_reinforcement_distance=<int>  path reinforcement distance specified directly instead of computing it based on the -O value above.");
			System.err.println("#  --triplet-lock                     lock in local (triplet) paths at nodes where read paths are supported. (increases stringency)");
			System.err.println("#  ");

			System.err.println("# Similar path reduction criteria:");
			System.err.println("#  --SW                                use Smith-Waterman local alignment mode (by default, uses Needleman-Wunsch global alignment)");
			System.err.println("#  --max_diffs_same_path=<int>         max allowed differences encountered between path sequences to combine them. (default: " + MAX_DIFFS_SAME_PATH + ")");
			System.err.println("#  --min_per_id_same_path=<float>      min percent identity for two paths to be merged into single paths (default: " + MIN_PERCENT_IDENTITY_SAME_PATH + ")");
			System.err.println("#  --max_internal_gap_same_path=<int>  maximum number of internal consecutive gap characters allowed for paths to be merged into single paths. (default: " + MAX_INTERNAL_GAP_SAME_PATH);
			System.err.println("#  --max_seq_len_DP_align=<int>        path regions to be aligned that are longer than this length use simple zipper alignment. (default: " + MAX_SEQ_LEN_DP_ALIGN + ")");
			/*
			System.err.println("#  --REDUCE                            enable final cdhit-like reduction. Additional opts below determine sequence filtering rules.");

			System.err.println("#       --diffs_window_size=<int>      under --REDUCE: length of window to scan for sequence differences. (default: " + DIFFS_WINDOW_SIZE + ")");
			System.err.println("#       --max_final_diffs_in_window=<int>    under --: maximum number of differences allowed in any alignment window. (default: " + MAX_FINAL_DIFFS_IN_WINDOW + ")");
			 */
			System.err.println("#  ");



			System.err.println("# Misc: ");
			System.err.println("#  --max_number_of_paths_per_node     total number of paths allowed per node (default=1000)");
			System.err.println("#  --generate-full-sequence-graphs    generate full sequence dot files");
			System.err.println("#                                        (default: generate dot files with start and end of each seq).");
			System.err.println("#  --generate_intermediate_dot_files  generate dot files after each step of butterfly");
			System.err.println("#                                        (default: generate only a the start and end dot files).");			
			System.err.println("#  --stderr                           prints the output to STDERR ");
			System.err.println("#  --log_stderr                       writes status info to fiule COMPONENT_PREFIX.err ");
			System.err.println("#  -V <int>                           verbosity level ");
			System.err.println("#                                        (default: 10 - progress of method + some stats)");
			System.err.println("#                                        (15 - like (10) + final paths to be added + additional loop info and dot files)");
			System.err.println("#                                        (20 - maximum verbosity)");
			System.err.println("#");
			System.err.println("########################################################################################");
			System.err.println("");
			System.exit(1);

		}

		// set calculated vars:
		if (PATH_REINFORCEMENT_DISTANCE > 0) {
			debugMes("path reinforcement distance set manually to: " + PATH_REINFORCEMENT_DISTANCE, 5);
		}
		else {

			PATH_REINFORCEMENT_DISTANCE = (int) (PATH_REINFORCEMENT_DISTANCE_PERCENT/100.0 * MAX_PAIR_DISTANCE);
			debugMes("path reinforcement distance computed based on " 
					+ PATH_REINFORCEMENT_DISTANCE_PERCENT + "% of max pair distance: "+ MAX_PAIR_DISTANCE
					+ " = " + PATH_REINFORCEMENT_DISTANCE + " bases", 5);
		}
		/* original version:
		if (PATH_REINFORCEMENT_DISTANCE == 0 && MAX_PAIR_DISTANCE > 50) {
			PATH_REINFORCEMENT_DISTANCE = MAX_PAIR_DISTANCE - 50; // Moran's original settings.
		}
		 */


		if (!COLLAPSE_SNPs && USE_DEGENERATE_CODE)
			USE_DEGENERATE_CODE = false;

		Vector<Integer> rootIDs = new Vector<Integer>();

		HashMap<Integer,Integer> outFlow = new HashMap<Integer, Integer>();
		HashMap<Integer,Integer> inFlow = new HashMap<Integer, Integer>();
		HashMap<Integer,String> firstLetter = new HashMap<Integer, String>();

		LONG_READ_PATH_MAP = new HashMap<PairPath, ArrayList<String>>();
		LONG_READ_NAME_TO_PPath = new HashMap<String, PairPath>();

		PrintStream p;

		/*  
		String bfly_start_indicator_file = file + ".bfly.started";
		String bfly_end_indicator_file = file + ".bfly.finished";

		{ 
			// write bfly start-indication file
			p = new PrintStream(new FileOutputStream(bfly_start_indicator_file));
			p.close();
		}
		 */

		PrintStream pout_diff = null;
		PrintStream pout_all = new PrintStream(new FileOutputStream(file+".allProbPaths.fasta"));


		debugMes("preProcessGraphFile: " + file + ".out", 10);
		preProcessGraphFile(file+".out",outFlow,inFlow,firstLetter);

		debugMes("buildNewGraphFirstLetter: " + file + ".out", 10);
		DirectedSparseGraph<SeqVertex, SimpleEdge> graph = buildNewGraphFirstLetter(file+".out",rootIDs,outFlow,inFlow,firstLetter); 

		LAST_REAL_ID = LAST_ID;
		debugMes("Graph is built",10);

		String[] tmpFile = file.split("/");
		String graphName = tmpFile[tmpFile.length-1];


		//boolean createMiddleDotFiles = false;
		boolean createMiddleDotFiles = GENERATE_MIDDLE_DOT_FILES;


		if (createMiddleDotFiles) 
		{
			p= new PrintStream(new FileOutputStream(file + ".A.dot"));
			writeDotFile(graph,p,graphName);
			p.close();
		}

		fixExtremelyHighSingleEdges(graph,outFlow,inFlow);

		removeLightEdges(graph);

		if (createMiddleDotFiles)
		{
			p = new PrintStream(new FileOutputStream(file + "_removedLightEdges.B.dot"));
			writeDotFile(graph,p,graphName);
			p.close();
		}

		compactLinearPaths(graph);

		if (createMiddleDotFiles)
		{
			p = new PrintStream(new FileOutputStream(file + "_compactonly.C.dot"));
			writeDotFile(graph,p,graphName);
			p.close();
		}

		if (GENERATE_FULL_SEQ_GRAPH)
		{
			p = new PrintStream(new FileOutputStream(file + "_compactonly.fullSeq.D.dot"));
			writeDotFile(graph,p,graphName,GENERATE_FULL_SEQ_GRAPH);
			p.close();
		}

		if (graph.getVertexCount() == 0) {
			debugMes("Warning: graph pruned to nothingness", 1);
			/*
			if (NO_CLEANUP) {
				Runtime.getRuntime().exec("mv " + bfly_start_indicator_file + " " + bfly_end_indicator_file);
			}
			else {
				//Runtime.getRuntime().exec("rm " + bfly_start_indicator_file);
				//Runtime.getRuntime().exec("rm " + file + ".out");
				//Runtime.getRuntime().exec("rm " + file + ".reads");
				File f = new File(bfly_start_indicator_file);
				f.delete();
			}
			 */
			System.exit(0);
		}

		compactPrefixesBottomUp(graph);

		if (graph.getVertexCount() == 0) {
			debugMes("Warning: graph pruned to nothingness", 1);
			//Runtime.getRuntime().exec("mv " + bfly_start_indicator_file + " " + bfly_end_indicator_file);
			System.exit(0);
		}

		if (createMiddleDotFiles)
		{
			p = new PrintStream(new FileOutputStream(file + "_compact1.E.dot"));
			writeDotFile(graph,p,graphName);
			p.close();
		}

		int i=1;
		boolean runAgain = removeLightEdges(graph);
		boolean changend_suffices = false,changend_rmEdges=false;
		while (runAgain)
		{
			changend_suffices = compactPrefixesBottomUp(graph);
			i++;
			changend_rmEdges = removeLightEdges(graph);

			runAgain = changend_suffices || changend_rmEdges;

			if (createMiddleDotFiles)
			{
				p = new PrintStream(new FileOutputStream(file + "_compact"+i+".F.dot"));
				writeDotFile(graph,p,graphName);
				p.close();
			}

		}

		if (createMiddleDotFiles)
		{
			p = new PrintStream(new FileOutputStream(file + "_compactDone.G.dot"));
			writeDotFile(graph,p,graphName);
			p.close();
		}

		if (COLLAPSE_SNPs)
			if (USE_DEGENERATE_CODE)
				removeSingleNtBubblesWithDegenerateCode(graph);
			else
				removeSingleNtBubbles(graph);

		compactLinearPaths(graph);

		if (createMiddleDotFiles)
		{
			p = new PrintStream(new FileOutputStream(file + "_compactDone_withoutBubbles.H.dot"));
			writeDotFile(graph,p,graphName);
			p.close();
		}

		//remove small components
		calcSubComponentsStats(graph);

		if (graph.getVertexCount() == 0) {
			debugMes("Warning: graph pruned to nothingness", 1);
			//Runtime.getRuntime().exec("mv " + bfly_start_indicator_file + " " + bfly_end_indicator_file);
			System.exit(0);
		}

		if (createMiddleDotFiles)
		{
			p = new PrintStream(new FileOutputStream(file + "_goodComp.I.dot"));
			writeDotFile(graph,p,graphName);
			p.close();
		}

		HashMap<Integer, LocInGraph> originalVerIDsMapping = getOriginalVerIDsMappingHash(graph);



		int numXstructs = countNumOfXstructures(graph);
		if (numXstructs>0)
			debugMes("number X structures = "+numXstructs,10);


		// Done Compacting graph.  

		DijkstraDistance<SeqVertex, SimpleEdge> dijkstraDis = new DijkstraDistance<SeqVertex, SimpleEdge>(graph, true);

		// maps individual reads to paths within the graph
		// readNameHash:  "actual read name" => Read object  (see Read class)
		HashMap<String, List<Read>> readNameHash = getReadStarts(graph,file+".reads",originalVerIDsMapping,rootIDs);

		// pair up reads into PathPairs
		// combinedReadHash: start_vertex => (pair_path => count)
		HashMap<Integer,HashMap<PairPath,Integer>> combinedReadHash = getSuffStats_wPairs(graph,readNameHash,dijkstraDis);

		debugMes(combinedReadHash+"",15);

		//start working on one sub component at a time:
		// look for loops, try to solve them
		// if loops remain, move on to the next subComp.

		Set<Set<SeqVertex>> comps = divideIntoComponents(graph);
		debugMes("total number of components = "+comps.size(),10);
		int compID = -1;


		if (FIND_ALSO_DIFF_PATHS)
			pout_diff = new PrintStream(new FileOutputStream(file+"_diffPaths.fasta"));


		String[] pathName = file.split("/");
		if (VERBOSE_LEVEL>=5)
		{
			p = new PrintStream(new FileOutputStream(file + "_withLoops.J.dot"));
			writeDotFile(graph,p,graphName,false);
			p.close();
		}

		if (GENERATE_FULL_SEQ_GRAPH)
		{
			p = new PrintStream(new FileOutputStream(file + "_withLoops.fullSeq.K.dot"));
			writeDotFile(graph,p,graphName,GENERATE_FULL_SEQ_GRAPH);
			p.close();
		}

		int totalNumPaths = 0;
		int totalNumSuccComps = 0;

		for (Set<SeqVertex> comp : comps)
		{
			compID++;
			debugMes("prepping subcomponent "+compID,10);

			int loop_round = 0;
			while(dealWithLoops(graph,comp,combinedReadHash)) { // run this as long as there are loops
				if (createMiddleDotFiles)
				{
					loop_round++;
					p = new PrintStream(new FileOutputStream(file + "_goodComp.KL.comp" + compID 
							+ ".loop_removal_round-" + loop_round + ".dot"));
					writeDotFile(graph,p,graphName);
					p.close();
				}

			}

		}


		DijkstraDistanceWoVer<SeqVertex, SimpleEdge> dijkstraDisWoVer = new DijkstraDistanceWoVer<SeqVertex, SimpleEdge>(graph);

		//finished updating the graph, update the DFS stats on each vertex.
		getTopologicalOrder(graph);


		compID = -1; // reset
		for (Set<SeqVertex> comp : comps)
		{
			compID++;
			debugMes("transcript reconstruction for subcomponent "+compID,10);

			addSandT(graph,comp,combinedReadHash);

			HashMap<List<Integer>,ArrayList<String>> final_paths_to_long_read_content = new HashMap<List<Integer>,ArrayList<String>>();
			Pair<HashMap<List<Integer>,Pair<Integer>>> FinalPathsPair = getAllProbablePaths(graph,comp,
					combinedReadHash,dijkstraDis,dijkstraDisWoVer, final_paths_to_long_read_content);

			HashMap<List<Integer>,Pair<Integer>> FinalPaths_diff = FinalPathsPair.getFirst();
			HashMap<List<Integer>,Pair<Integer>> FinalPaths_all = FinalPathsPair.getSecond();

			String name = pathName[pathName.length-1]+"_c"+compID;

			/*
			  if (!FinalPaths_diff.isEmpty())
				printFinalPaths(FinalPaths_diff,graph,compID,pout_diff,name,totalNumReads);
			 */

			if (FinalPaths_all==null)
				continue;

			// Final Path Reporting (plus some path filtering)
			FinalPaths_all = printFinalPaths(FinalPaths_all,graph,compID,pout_all,name,totalNumReads, final_paths_to_long_read_content);

			totalNumPaths+=FinalPaths_all.keySet().size();
			if (FinalPaths_all.keySet().size()>0)
				totalNumSuccComps++;

			for (List<Integer> path : FinalPaths_all.keySet())
			{
				debugMes("FinalPath: "+path+" with support "+FinalPaths_all.get(path),10);
			}


			numXstructs = countNumOfXstructuresResolved(graph,comp,FinalPaths_all);
			if (numXstructs>0)
				debugMes("number X structures resolved = "+numXstructs,10);

			removeAllEdgesOfSandT(graph);

		}
		pout_all.close();
		if (FIND_ALSO_DIFF_PATHS)
			pout_diff.close();


		debugMes("total number of paths reported = "+totalNumPaths+" from "+totalNumSuccComps +" components",10);

		if (VERBOSE_LEVEL >= 5) {
			p = new PrintStream(new FileOutputStream(file + "_finalCompsWOloops.L.dot"));
			writeDotFile(graph,p,graphName);
			p.close();
		}

		if (GENERATE_FULL_SEQ_GRAPH)
		{
			p = new PrintStream(new FileOutputStream(file + "_finalCompsWOloops.fullSeq.M.dot"));
			writeDotFile(graph,p,graphName,GENERATE_FULL_SEQ_GRAPH);
			p.close();
		}


		debugMes("Done",10);
		/*
		if (NO_CLEANUP) {
			Runtime.getRuntime().exec("mv " + bfly_start_indicator_file + " " + bfly_end_indicator_file);
		}
		else {
			// remove the inputs.
			//Runtime.getRuntime().exec("rm " + file + ".out");
			//Runtime.getRuntime().exec("rm " + file + ".reads");
			//Runtime.getRuntime().exec("rm " + bfly_start_indicator_file);
			File f = new File(bfly_start_indicator_file);
			f.delete();
		}
		 */

		if (LOG_STDERR)
			ERR_STREAM.close();

	}




	/**
	 * given the graph, find all single nt bubbles, and choose the majority vote. 
	 * add the weights to the majority path, and add the prevID  
	 * v -> v1 -> vend
	 * v -> v2 -> vend
	 * @param graph
	 */
	private static void removeSingleNtBubbles(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph) {

		SeqVertex v1=null ,v2 = null, vend = null;
		SeqVertex vToKeep=null ,vToRemove = null;
		SimpleEdge e1ToKeep = null, e1ToRemove = null;
		SimpleEdge e2ToKeep = null, e2ToRemove = null;

		Vector<SeqVertex> removeV = new Vector<SeqVertex>();
		Collection<SeqVertex> allV = new HashSet<SeqVertex>();
		allV.addAll(graph.getVertices());

		for (SeqVertex v : allV)
		{
			if (removeV.contains(v))
				continue;
			if (graph.getSuccessorCount(v)==2)
			{
				Collection<SeqVertex> children = graph.getSuccessors(v);
				Iterator<SeqVertex> iter = children.iterator();
				v1 = iter.next();
				v2 = iter.next();


				int len1 = v1.getName().length();
				int len2 = v2.getName().length();

				if (len1==1 && len2==1 && 
						graph.getSuccessorCount(v1)==1 && 
						graph.getSuccessorCount(v2)==1 &&
						getSingleSuccessor(graph,v2).equals(getSingleSuccessor(graph,v1)))
				{
					vend = getSingleSuccessor(graph,v1);
					if (graph.findEdge(v, v1).getWeight() > graph.findEdge(v, v2).getWeight())
					{ //keep v1, loose v2
						vToKeep = v1;
						vToRemove = v2;
					}else
					{ //keep v2, loose v1
						vToKeep = v2;
						vToRemove = v1;
					}
					e1ToKeep = graph.findEdge(v, vToKeep);
					e2ToKeep = graph.findEdge(vToKeep, vend);
					e1ToRemove = graph.findEdge(v, vToRemove);
					e2ToRemove = graph.findEdge(vToRemove, vend);
					debugMes("merging the node "+vToRemove.getID()+" to the node "+vToKeep.getID(),20);

					SeqVertex newV = new SeqVertex(getNextID(), vToKeep.getName());
					newV.copyTheRest(vToKeep);
					newV.addToPrevIDs(vToKeep,vToRemove,LAST_REAL_ID);

					graph.addVertex(newV);
					graph.addEdge(new SimpleEdge(e1ToKeep.getWeight() + e1ToRemove.getWeight()), v, newV);
					graph.addEdge(new SimpleEdge(e2ToKeep.getWeight() + e2ToRemove.getWeight()), newV,vend);

					removeV.add(vToRemove);
					removeV.add(vToKeep);


				}
			}
		}

		for (SeqVertex rv : removeV)
		{
			debugMes("removing the single nt variation vertex "+rv.getID(),20);
			graph.removeVertex(rv);
		}

	}




	/**
	 * given the graph, find all single nt bubbles, and choose the majority vote. 
	 * add the weights to the majority path, and add the prevID  
	 * v -> v1 -> vend
	 * v -> v2 -> vend
	 * @param graph
	 * @throws Exception 
	 */
	private static void removeSingleNtBubblesWithDegenerateCode(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph) throws Exception {

		SeqVertex v1=null ,v2 = null, vend = null;
		SimpleEdge eTop1 = null, eTop2 = null;
		SimpleEdge eBottom1 = null, eBottom2 = null;

		Vector<SeqVertex> removeV = new Vector<SeqVertex>();
		Collection<SeqVertex> allV = new HashSet<SeqVertex>();
		allV.addAll(graph.getVertices());

		for (SeqVertex v : allV)
		{
			if (removeV.contains(v))
				continue;
			if (graph.getSuccessorCount(v)==2)
			{
				Collection<SeqVertex> children = graph.getSuccessors(v);
				Iterator<SeqVertex> iter = children.iterator();
				v1 = iter.next();
				v2 = iter.next();


				int len1 = v1.getName().length();
				int len2 = v2.getName().length();

				if (len1==1 && len2==1 && 
						graph.getSuccessorCount(v1)==1 && 
						graph.getSuccessorCount(v2)==1 &&
						getSingleSuccessor(graph,v2).equals(getSingleSuccessor(graph,v1)))
				{
					vend = getSingleSuccessor(graph,v1);
					String key;
					if (String.CASE_INSENSITIVE_ORDER.compare(v1.getName(),v2.getName())<0)
						key =  v1.getName()+v2.getName();
					else
						key =  v2.getName()+v1.getName();
					String name = getDegenerateRepresentation(key);
					SeqVertex newV = new SeqVertex(getNextID(), name);

					if (graph.findEdge(v, v1).getWeight() > graph.findEdge(v, v2).getWeight())
						newV.copyTheRest(v1);
					else
						newV.copyTheRest(v2);

					eTop1 = graph.findEdge(v, v1);
					eBottom1 = graph.findEdge(v1, vend);
					eTop2 = graph.findEdge(v, v2);
					eBottom2 = graph.findEdge(v2, vend);
					debugMes("merging the nodes "+v1.getID()+" and the node "+v2.getID()+" to the node "+newV,18);

					newV.addToPrevIDs(v1,v2,LAST_REAL_ID);
					newV.setFrequencies(v1.getName(),eTop1.getWeight(),v2.getName(),eTop2.getWeight());
					graph.addVertex(newV);
					graph.addEdge(new SimpleEdge(eTop1.getWeight() + eTop2.getWeight()), v, newV);
					graph.addEdge(new SimpleEdge(eBottom1.getWeight() + eBottom2.getWeight()), newV,vend);

					removeV.add(v1);
					removeV.add(v2);


				}
			}
		}

		for (SeqVertex rv : removeV)
		{
			debugMes("removing the single nt variation vertex "+rv.getID(),20);
			graph.removeVertex(rv);
		}

	}

	/**
	 * return the single successor of this node in this graph
	 * @param graph
	 * @param v2
	 * @return
	 */
	private static SeqVertex getSingleSuccessor(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph, SeqVertex v) {
		Collection<SeqVertex> children = graph.getSuccessors(v);
		if (children.size()!=1)
			return null;

		SeqVertex vout = children.iterator().next();
		return vout;

	}


	/**
	 * find edges that are extremely high compared to both side (a single very abundant kmer, and fix their support
	 * @param graph
	 * @param inFlow 
	 * @param outFlow 
	 */
	private static void fixExtremelyHighSingleEdges(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph, HashMap<Integer,Integer> outFlow, HashMap<Integer,Integer> inFlow) {

		debugMes("fixExtremelyHighSingleEdges()", 5);
		for (SimpleEdge e : graph.getEdges())
		{
			double supp =e.getWeight(); 
			Integer sourceID = graph.getSource(e).getID();
			Integer targetID = graph.getDest(e).getID();
			Integer inFlowToSource = inFlow.get(sourceID);
			Integer outFlowOfTarget = outFlow.get(targetID);

			if (inFlowToSource!= null && outFlowOfTarget!= null && 
					supp > inFlowToSource*EXTREME_EDGE_FLOW_FACTOR && supp > outFlowOfTarget*EXTREME_EDGE_FLOW_FACTOR)
			{
				double newSupp = Math.max(inFlowToSource, outFlowOfTarget);
				debugMes("the support of edge "+sourceID+"->"+targetID+" has changed from "+supp+" to "+newSupp,20);
				e.setWeight(newSupp);
			}

		}
	}


	/**
	 * given the graph and the final paths, find x structures that belong to only two paths, which resolve this structure.
	 * @param graph
	 * @param comp 
	 * @param finalPaths
	 * @return
	 */
	private static int countNumOfXstructuresResolved(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph,
			Set<SeqVertex> comp, HashMap<List<Integer>,Pair<Integer>> finalPaths) {

		int res = 0;

		for (SeqVertex v : comp)
		{
			if (graph.inDegree(v)>1 && graph.outDegree(v)>1)
			{
				//this is an x-structure
				int maxPaths = Math.max(graph.inDegree(v), graph.outDegree(v));
				Integer bef,after;
				int vid = v.getID();
				HashMap<Pair<Integer>,Integer> befAndAfterNodes = new HashMap<Pair<Integer>, Integer>();
				Pair<Integer> key;
				for (List<Integer> path : finalPaths.keySet())
				{
					int index = path.indexOf(vid);

					if (index!=-1 && index!=0 && index!=path.size()-1) // vid is not the first or the last
					{

						bef = path.get(index-1);
						after = path.get(index+1);
						key = new Pair<Integer>(bef,after);
						if (!befAndAfterNodes.containsKey(key))
							befAndAfterNodes.put(key,1);
						else
							befAndAfterNodes.put(key,befAndAfterNodes.get(key)+1);
					}
				}

				if (befAndAfterNodes.keySet().size()==maxPaths)
				{
					debugMes("vertex "+v.getID()+" is resolved in an X-structure",10);
					res++;
				}
			}
		}

		return res;
	}


	public static class FinalPaths implements Comparable<FinalPaths> {

		List<Integer> path;
		String sequence;

		public FinalPaths (List<Integer> p, String s) {
			path = p;
			sequence = s;
		}

		public int compareTo(FinalPaths f) {

			if (this.sequence.length() > f.sequence.length()) {
				return(-1);
			}
			else if (this.sequence.length() < f.sequence.length()) {
				return(1);
			}
			else {
				return(0);
			}

		}



	}


	/**
	 * Print all final paths
	 * @param finalPaths
	 * @param graph
	 * @param compID 
	 * @param p 
	 * @param name 
	 * @param totalNumReads 
	 * @throws FileNotFoundException 
	 */
	private static HashMap<List<Integer>,Pair<Integer>> printFinalPaths(
			HashMap<List<Integer>,Pair<Integer>> finalPaths,
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph, 
			int compID, 
			PrintStream p, 
			String name, 
			long totalNumReads,
			HashMap<List<Integer>,ArrayList<String>> final_paths_to_long_read_content) 
					throws FileNotFoundException {





		Vector<FinalPaths> path_vec = new Vector<FinalPaths>();

		DecimalFormat df = new DecimalFormat("#.#");
		for (List<Integer> path : finalPaths.keySet())
		{
			String seq = getPathSeq(graph,path);

			FinalPaths f = new FinalPaths(path, seq);
			path_vec.add(f);
		}






		int seq_count = 1;
		double fpkm_all = 0;
		double fpkm_rel = 0;

		DecimalFormat f0 = new DecimalFormat("#");

		HashMap<List<Integer>,Pair<Integer>> post_filtering_finalPaths = new HashMap<List<Integer>,Pair<Integer>>();

		for (FinalPaths f : path_vec) {

			/*
			if (filtered.containsKey(f)) {
				continue;
			} */

			List<Integer> path = f.path;
			String seq = f.sequence;

			post_filtering_finalPaths.put(path, finalPaths.get(path));

			//print this path
			String seqName = name+"_seq"+seq_count;

			if (seq.length()>=MIN_OUTPUT_SEQ) 
			{
				//				rpkm formula = #reads*1e9/(length*totalMapped);
				fpkm_all = (finalPaths.get(path).getFirst()/(double)seq.length()) *(1e9/totalNumReads);
				fpkm_rel = (finalPaths.get(path).getSecond()/(double)seq.length()) *(1e9/totalNumReads);


				String pathName = get_pathName_string(path, graph);

				//seqName = seqName + " FPKM_all:" +df.format(fpkm_all)+ "_FPKM_rel:" +df.format(fpkm_rel)+ "_len:"+seq.length()+"_path:"+ pathName;
				//seqName = seqName.replaceAll(" ", "");

				// separate code now exists for abundance estimation and reporting counts of reads mapped (unique and multi-map)
				// seqName = seqName + " FragCountAll:" + read_count_all + " FragCountRel:" + read_count_rel + " len:"+seq.length()+" path:"+ pathName;
				//seqName = seqName + " len="+seq.length() + " ~FPKM=" + df.format(fpkm_rel) + " path="+ pathName;
				seqName = seqName + " len="+seq.length() + " path="+ pathName;

				// Report the long read content information.
				if (final_paths_to_long_read_content.containsKey(path)) {
					// then got list of long read names assigned to this final path
					HashMap<PairPath, ArrayList<String>> long_read_paths_to_name_list = new HashMap<PairPath, ArrayList<String>>();


					String long_read_info = "";
					for (String long_read_name : final_paths_to_long_read_content.get(path)) {

						PairPath pp = LONG_READ_NAME_TO_PPath.get(long_read_name);
						if (!long_read_paths_to_name_list.containsKey(pp)) {
							ArrayList<String> a = new ArrayList<String>();
							a.add(long_read_name);
							long_read_paths_to_name_list.put(pp, a);
						}
						else {
							long_read_paths_to_name_list.get(pp).add(long_read_name);
						}

					}
					seqName = seqName + " long_read_mappings: " + long_read_paths_to_name_list;
				}
				debugMes("Final path reported: " + seqName, 10);
				p.print(getSeqFasta(seq, seqName));
				seq_count++;
			}

		}

		return(post_filtering_finalPaths);

	}


	/**
	 * given a path in the graph, return its sequence
	 * @param graph
	 * @param path
	 * @return
	 */
	private static String getPathSeq(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph, List<Integer> path) {
		String seq = "";
		for (Integer nodeID : path)
			if (nodeID>=0)
				seq = seq + getSeqVertex(graph, nodeID).getName();	
		return seq;
	}




	/**
	 * For each path of a read pair, ask how many reads support it.
	 * @param graph
	 * @param readNameHash
	 * @param dijkstraDis 
	 * @return
	 */
	private static HashMap<Integer, HashMap<PairPath, Integer>> getSuffStats_wPairs(
			DirectedSparseGraph<SeqVertex,SimpleEdge> graph, HashMap<String, List<Read>> readNameHash, DijkstraDistance<SeqVertex,SimpleEdge> dijkstraDis) {
		HashMap<Integer,HashMap<PairPath,Integer>>   combinedReadHash = new HashMap<Integer,HashMap<PairPath,Integer>>  ();

		Set<String> usedReads = new HashSet<String>();
		List<Read> curList = null;
		int numReadsUsed = 0;

		int numSingletons = 0;
		int numPairs = 0;
		int numPairsDiscarded = 0;

		for (String name : readNameHash.keySet())
		{
			if (usedReads.contains(name))
				continue; // ignoring reduncancy in the read set?

			curList = readNameHash.get(name);
			if (curList.size()==1)
			{//single read
				Read r = curList.get(0);
				PairPath path = new PairPath(r.getPathIDs());
				Integer firstV = path.getFirstID();

				if (!combinedReadHash.containsKey(firstV))
					combinedReadHash.put(firstV, new HashMap<PairPath,Integer>());

				if (!combinedReadHash.get(firstV).containsKey(path))
					combinedReadHash.get(firstV).put(path, 0);

				Integer counts = combinedReadHash.get(firstV).get(path);
				combinedReadHash.get(firstV).put(path,++counts);
				numReadsUsed++;
				debugMes("we have "+combinedReadHash.get(firstV).get(path)+" reads supporting the path: "+path,19);
				numSingletons++;

				// examine for long read.
				if (r.getSeq().length() >= MIN_LONG_READ_LENGTH) {
					LONG_READ_NAME_TO_PPath.put(name,  path);
					if (! LONG_READ_PATH_MAP.containsKey(path)) {
						ArrayList<String> nameList = new ArrayList<String>();
						nameList.add(name);
						LONG_READ_PATH_MAP.put(path, nameList);
					}
					else {  
						ArrayList<String> nameList = (ArrayList<String>) LONG_READ_PATH_MAP.get(path);
						nameList.add(name);
					}
				}


			}else {// paired read
				Read r1 = curList.get(0);
				List<Integer> path1 = r1.getPathIDs();

				Read r2 = curList.get(1);
				List<Integer> path2 = r2.getPathIDs();


				PairPath  combinedPath = combinePaths(graph,path1,path2,dijkstraDis);
				if (combinedPath.isEmpty())
				{
					debugMes("the paths "+path1+" and "+path2+" couldn't be combined",15);
					numPairsDiscarded++;
					continue;
				}

				Integer firstV = combinedPath.getFirstID();

				if (!combinedReadHash.containsKey(firstV))
					combinedReadHash.put(firstV, new HashMap<PairPath,Integer>());

				if (!combinedReadHash.get(firstV).containsKey(combinedPath))
					combinedReadHash.get(firstV).put(combinedPath, 0);

				Integer counts = combinedReadHash.get(firstV).get(combinedPath);
				combinedReadHash.get(firstV).put(combinedPath,++counts);
				debugMes("we have "+combinedReadHash.get(firstV).get(combinedPath)+" reads supporting the path: "+combinedPath,18);

				numReadsUsed++;
				numPairs++;


			}
			usedReads.add(name);
		}
		debugMes("number of reads used = "+numReadsUsed,15);

		debugMes("## Read PathPair results: " + numSingletons + " singletons, "
				+ " num pairs: " + numPairs + ", num pairs discarded: " + numPairsDiscarded, 10);

		return combinedReadHash;
	}

	/**
	 * Given the graph, and two paths of the two reads, combine them into a single path
	 * @param graph
	 * @param path1
	 * @param path2
	 * @param dijkstraDis
	 * @return
	 */
	private static PairPath combinePaths(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph,
			List<Integer> path1, List<Integer> path2, DijkstraDistance<SeqVertex,SimpleEdge> dijkstraDis) {
		SeqVertex firstV1 = getSeqVertex(graph,path1.get(0));
		SeqVertex lastV1 = getSeqVertex(graph,path1.get(path1.size()-1));
		SeqVertex firstV2 = getSeqVertex(graph,path2.get(0));
		SeqVertex lastV2 = getSeqVertex(graph,path2.get(path2.size()-1));
		PairPath path  = new PairPath();

		if (path1.containsAll(path2))
			path.setPath1(path1);
		else if (path2.containsAll(path1))
			path.setPath2(path2);
		//path1 --> path2
		else if (isAncestral(lastV1, firstV2,dijkstraDis)>0)
		{
			path.setPath1(path1);
			path.setPath2(path2);
		}
		//path2 --> path1
		else if (isAncestral(lastV2, firstV1,dijkstraDis)>0)
		{
			path.setPath1(path2);
			path.setPath2(path1);
		}

		else if (isAncestral(firstV2,firstV1,dijkstraDis)==0 && 
				isAncestral(lastV2,lastV1,dijkstraDis)==0)
		{
			//there is no consistent path between read1 and read2
		}

		//path1(partial) -> path2
		else if (isAncestral(firstV1,firstV2,dijkstraDis)>0 && 
				path1.indexOf(firstV2.getID())>=0)
		{
			int i = path1.indexOf(firstV2.getID());
			path.setPath1(path1.subList(0, i));
			path.addToPath1(path2);
		}

		//path2(partial) -> path1
		else if (isAncestral(firstV2,firstV1,dijkstraDis)>0 &&
				path2.indexOf(firstV1.getID())>=0)
		{
			int i = path2.indexOf(firstV1.getID());
			path.setPath1(path2.subList(0, i));
			path.addToPath1(path1);
		}

		if (path.getPath1().isEmpty() && !path.getPath2().isEmpty())
			path.movePath2To1();

		return path;

	}

	/** 
	 * using the dfs discovery and finishing times, figure out which is ancestral to which
	 * @param v1
	 * @param v2
	 * @param dijkstraDis 
	 * @return 1 if v1 is ancestral to v2
	 * @return -1 if v2 is ancestral to v1
	 * @return 0 if there is no path (v1,v2) and no path (v2, v1)
	 */
	private static int isAncestral(SeqVertex v1, SeqVertex v2, DijkstraDistance<SeqVertex,SimpleEdge> dijkstraDis) {

		// v1 ---> v2
		if (dijkstraDis.getDistance(v1, v2)!=null)
			return 1;
		// v2 ---> v1
		if (dijkstraDis.getDistance(v2, v1)!=null)
			return -1;

		return 0;
	}

	/**
	 * Count how many vertices we have with in degree >1 & out degree >1
	 * @param graph
	 * @return
	 */
	private static int countNumOfXstructures(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph) {
		int res = 0;

		for (SeqVertex v : graph.getVertices())
		{
			if (graph.inDegree(v)>1 && graph.outDegree(v)>1)
				res++;
		}

		return res;
	}

	/**
	 * Given the graph and the hash with all reads, find all probable paths from S to T.
	 * @param graph
	 * @param comp 
	 * @param combinedReadHash
	 * @param dijkstraDis 
	 * @param dijkstraDisWoVer 
	 */
	private static Pair<HashMap<List<Integer>, Pair<Integer>>> getAllProbablePaths(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph,
			Set<SeqVertex> comp, 
			HashMap<Integer,HashMap<PairPath,Integer>> combinedReadHash, 
			DijkstraDistance<SeqVertex,SimpleEdge> dijkstraDis, 
			DijkstraDistanceWoVer<SeqVertex,SimpleEdge> dijkstraDisWoVer,
			HashMap<List<Integer>,ArrayList<String>> final_paths_to_long_read_content
			) {

		HashMap<SeqVertex,List<List<Integer>>> Paths = new HashMap<SeqVertex,List<List<Integer>>>();
		HashMap<List<Integer>,HashMap<PairPath,Integer>> PathReads = new HashMap<List<Integer>,HashMap<PairPath,Integer>>();
		HashMap<List<Integer>,Boolean> Extensions = new HashMap<List<Integer>,Boolean>();

		HashMap<List<Integer>,Pair<Integer>> FinalPaths_diff = new HashMap<List<Integer>,Pair<Integer>>();
		HashMap<List<Integer>,Pair<Integer>> FinalPaths_all = new HashMap<List<Integer>,Pair<Integer>>();




		//initiation
		//NUM_MATCHES_HASH = new HashMap<String, Integer>();
		NUM_MISMATCHES_HASH = new HashMap<String, AlignmentStats>();

		ROOT.setDFS_FinishingTime(Integer.MAX_VALUE);
		T_VERTEX.setDFS_FinishingTime(-1);

		SeqVertexFinishTimeComparator finishingTimeComparator = new SeqVertexFinishTimeComparator();

		PriorityQueue<SeqVertex> C = new PriorityQueue<SeqVertex>(comp.size(),finishingTimeComparator  );

		C.add(ROOT);
		List<Integer> tmpL = new ArrayList<Integer>();
		tmpL.add(ROOT.getID());
		ArrayList<List<Integer>> tmpPathList = new ArrayList<List<Integer>>();
		tmpPathList.add(tmpL);
		Paths.put(ROOT, tmpPathList);
		SeqVertex v;


		HashMap<Integer, List<List<Integer>>> tripletMapper;  // central_vertex -> ( [ left_vertex, right_vertex], [ left_vertex, right_vertex] )  as supported by reads

		if (TRIPLET_LOCKING) {
			tripletMapper = extractTripletsFromReads(combinedReadHash);

			if (VERBOSE_LEVEL >= 10) {
				// describe the locked down nodes
				debugMes("\n### " + tripletMapper.size() + " nodes have locked-in triplet paths:", 10);
				for (Integer central_node : tripletMapper.keySet()) {
					debugMes("Triplet locks for: " + central_node + " : " + tripletMapper.get(central_node), 10);
				}

			}
		}
		else {
			tripletMapper = new HashMap<Integer, List<List<Integer>>>();
		}


		String Crep;
		while (!C.isEmpty())
		{
			if (VERBOSE_LEVEL>=20)
			{
				Crep = "[";
				for (SeqVertex vp : C)
					Crep = Crep + "" +vp.getID()+":"+vp.getDFS_FinishingTime()+",";
				Crep += "]";
				debugMes("C = "+Crep,10);
			}
			v = C.poll(); 

			debugMes("\n\n#### getAllProbablePaths() The next node in the queue C is "+v.getID(),17);


			//try to combine paths that are very similar and reach v
			combineSimilarPathsThatEndAtV(graph,v,Paths,PathReads,Extensions); // already do this with paths that end at u.

			// get read paths that start at vertex V
			HashMap<PairPath,Integer> readsStartingAtV = combinedReadHash.get(v.getID());



			// prep data structures required.
			// go over all paths of P[v], add all reads that start at v
			for (List<Integer> path : Paths.get(v))
			{
				if (!PathReads.containsKey(path))
					PathReads.put(path, new HashMap<PairPath,Integer>()); // init

				if (readsStartingAtV!=null && !readsStartingAtV.isEmpty())
				{
					debugMes("\nadding the reads " +readsStartingAtV +" to the path "+ path, 17);
					PathReads.get(path).putAll(readsStartingAtV);
				}

				//keep track of all extensions
				Extensions.put(path, false);

			}



			// go over all descendants of v
			for (SeqVertex u : graph.getSuccessors(v))
			{

				int path_counter = 0;

				boolean vExtendedToU = false;

				List<List<Integer>> paths_ending_at_v = Paths.get(v);

				// sort paths by pair-path support descendingly
				PathReadSupportComparator pc = new PathReadSupportComparator(PathReads);
				Collections.sort(paths_ending_at_v, pc);
				Collections.reverse(paths_ending_at_v); // now descending according to read support.

				if (VERBOSE_LEVEL >= 18) {
					for (List<Integer> path : paths_ending_at_v) {
						int sum_reads = count_pairpath_support(path, PathReads);
						debugMes("Path: " + path + " has " + sum_reads + " pairpath support", 18);
					}
				}


				for (List<Integer> path : paths_ending_at_v) 
				{


					Boolean path_wvu_acceptable = true;


					if (TRIPLET_LOCKING && path.size() >= 3) {
						Integer w = path.get(path.size()-2); // create triplet w-v-u   (why are we doing this reverse lexically?)


						if (tripletMapper.containsKey(v.getID())) {
							List<Integer> triplet = new ArrayList();
							triplet.add(w); // left
							triplet.add(v.getID()); // central
							triplet.add(u.getID()); // right
							List<List<Integer>> triplet_list = tripletMapper.get(v.getID());
							if (tripletSupported(triplet_list, triplet)){
								// Hurray, got triplet support
								debugMes("Triplet Path: " + triplet + " *IS* supported by reads.", 10);
							}
							else {
								// lock down node, don't allow alternative structures not supported by reads here.
								debugMes("Triplet Path: " + triplet + " is *NOT* supported by reads.", 10);
								path_wvu_acceptable = false;
							}
						}
					}


					HashMap<PairPath,Integer> readsOfPathUntilV = PathReads.get(path); //this holds reads of path until V + reads starting at V
					if (  
							((! TRIPLET_LOCKING) || path_wvu_acceptable)

							&&

							(path_counter <= MAX_NUM_PATHS_PER_NODE)

							&&

							(
									ALL_POSSIBLE_PATHS 
									|| 	
									pathHasEnoughReadSupport(readsOfPathUntilV,path,u,graph,dijkstraDisWoVer)
									||
									u.getID() < 0 // a sink node, if path made it this far, sink can be added.
									)



							)

					{

						path_counter++;

						// add [path,u] to paths of u
						if (!Paths.containsKey(u))
							Paths.put(u, new ArrayList<List<Integer>>());

						List<Integer> pathWu = new ArrayList<Integer>();  // pathWu = path with u
						pathWu.addAll(path);
						pathWu.add(u.getID());
						if (!Paths.get(u).contains(pathWu)){
							debugMes("\nadding the path " +pathWu +" to the paths of "+ u.getID()+": "+Paths.get(u), 12);
							Paths.get(u).add(pathWu);
						}

						//update reads of [path,u]
						updateReadsOfPath(PathReads,pathWu,readsOfPathUntilV,u.getID(),graph,dijkstraDis);

						//update extension
						Extensions.put(path, true);
						vExtendedToU = true;
					}

				}
				if (!C.contains(u))
				{
					debugMes(u.getID()+" was added to the queue",17);
					C.add(u);

				}
				//if v didn't extend to u, and we have an edge there, add (v,u) as a new path
				if ( (!vExtendedToU) )
				{
					debugMes("the edge (v-u) was not used in any extension: "+v.getID()+"->"+u.getID(),15);
					if (!Paths.containsKey(u))
						Paths.put(u, new ArrayList<List<Integer>>());
					List<Integer> vuPath = new ArrayList<Integer>();
					vuPath.add(v.getID());
					vuPath.add(u.getID());

					Paths.get(u).add(vuPath);

					//add the reads
					if (!PathReads.containsKey(vuPath))
						PathReads.put(vuPath, new HashMap<PairPath,Integer>());

					if (readsStartingAtV!=null && !readsStartingAtV.isEmpty())
					{
						debugMes("adding the reads " +readsStartingAtV +" to the path "+ vuPath, 17);
						PathReads.get(vuPath).putAll(readsStartingAtV);
						updateReadsOfPath(PathReads,vuPath,readsStartingAtV,u.getID(),graph,dijkstraDis);

					}


				}

			}
			//report the paths that were not extended AND remove them from Paths
			List<List<Integer>> removePaths = new ArrayList<List<Integer>>();
			for (List<Integer> path : Paths.get(v))
			{
				SeqVertex lastV = getSeqVertex(graph, path.get(path.size()-1));

				if (!lastV.equals(T_VERTEX) && Extensions.get(path)!=null && !Extensions.get(path))
				{
					if (getSeqPathLength(graph,path)>MIN_OUTPUT_SEQ)
					{
						FinalPaths_all.put(path,new Pair<Integer>(getSuppCalculation(PathReads.get(path)),0));
						debugMes("the unextended path: "+path+" was added to the final paths, with "+getSuppCalculation(PathReads.get(path)) +" support",1);
					} 
					removePaths.add(path);
				}
			}

			for (List<Integer> path : removePaths)
			{
				debugMes("path "+ path +" was removed",10);
				Paths.get(v).remove(path);
				Extensions.remove(path);
			}
		}

		for (List<Integer> path : Paths.get(T_VERTEX))
		{
			if (getSeqPathLength(graph,path)>MIN_OUTPUT_SEQ)
			{
				FinalPaths_all.put(path,new Pair<Integer>(getSuppCalculation(PathReads.get(path)),0));
				if (path.get(0).intValue() == ROOT.getID())
					debugMes("the finished path: "+ path+" was added to the final paths, with "+getSuppCalculation(PathReads.get(path))+" support",15);
				else
					debugMes("the finished (from middle unextended) path: "+ path+" was added to the final paths, with "+getSuppCalculation(PathReads.get(path)) +" support",15);
			}
		}


		//if (RUN_ALL_VS_ALL_FILTER) {

		//FinalPaths_all = reduce_cdhit_like(FinalPaths_all, graph, PathReads);
		FinalPaths_all = remove_identical_subseqs(FinalPaths_all, graph, PathReads);
		//}


		// calc expression better (use RSEM, not this)

		HashMap<List<Integer>, List<PairPath>> finalPathsToContainedReads = calcExpressionOfFinalPaths(FinalPaths_all,PathReads);

		// see if any long reads are included.
		for (List<Integer> final_path : finalPathsToContainedReads.keySet()) {

			ArrayList<String> long_reads_included = null;

			List<PairPath> read_paths = finalPathsToContainedReads.get(final_path);
			for (PairPath p : read_paths) {
				if (LONG_READ_PATH_MAP.containsKey(p)) {
					// this final path contains a long read!
					ArrayList<String> long_read_names = LONG_READ_PATH_MAP.get(p);

					if (long_reads_included == null) {
						long_reads_included = new ArrayList<String>();
						final_paths_to_long_read_content.put(final_path, long_reads_included);
					}
					for (String name : long_read_names) {
						//System.err.println("***** Adding long read: " + name);
						long_reads_included.add(name);
					}
				}

			}


		}

		/*
		//remove similar final paths
		if (FIND_ALSO_DIFF_PATHS){  // legacy operation - should remove this
			FinalPaths_diff = new HashMap<List<Integer>, Pair<Integer>>(FinalPaths_all);
			combineSimilarPaths(graph,FinalPaths_diff,PathReads);
			calcExpressionOfFinalPaths(FinalPaths_diff,PathReads);
		}
		 */

		return new Pair<HashMap<List<Integer>, Pair<Integer>>>(FinalPaths_diff,FinalPaths_all);

	}

	/**
	 * given these paths, and reads, re-calc the FPKM of each path
	 * @param FinalPaths
	 * @param PathReads
	 */
	private static HashMap<List<Integer>, List<PairPath>> calcExpressionOfFinalPaths(
			HashMap<List<Integer>, Pair<Integer>> FinalPaths,
			HashMap<List<Integer>, HashMap<PairPath, Integer>> PathReads) {

		debugMes("calcExpressionOfFinalPaths()", 15);

		HashMap<PairPath,Pair<Integer>> ReadPerPathCounts = new HashMap<PairPath, Pair<Integer>>();

		HashMap<List<Integer>, List<PairPath>> finalPathsToContainedReads = new HashMap<List<Integer>,List<PairPath>>();

		for (List<Integer> path : FinalPaths.keySet()) {
			debugMes("\n\nRead pairs mapped to final path: " + path + " :", 18);

			for (PairPath read : PathReads.get(path).keySet())
			{

				if (!finalPathsToContainedReads.containsKey(path)) {
					finalPathsToContainedReads.put(path, new Vector<PairPath>());
				}

				debugMes("-checking for compatibility with read: " + read, 18);

				// check for complete containment:
				if (! read.isCompatibleAndContained(path)) {
					debugMes("\t* not compatible.", 18);
					continue;
				}
				else {
					debugMes("\t* COMPATIBLE read.", 18);
				}



				finalPathsToContainedReads.get(path).add(read);

				debugMes("\tRead: " + read.get_paths(), 18);

				Integer count = PathReads.get(path).get(read);
				if (!ReadPerPathCounts.containsKey(read))
					ReadPerPathCounts.put(read,new Pair<Integer>(1,count));
				else
					ReadPerPathCounts.put(read,new Pair<Integer>(ReadPerPathCounts.get(read).getFirst()+1,count));
			}
		}

		debugMes("\n\n*** PATHS AND COMPATIBLE READS ***\n", 15);

		for (List<Integer> path : FinalPaths.keySet())
		{


			debugMes("\nPATH: " + path, 15);

			Integer supp = 0;
			Integer totalCounts = 0;

			List<PairPath> containedReads = finalPathsToContainedReads.get(path);
			if (containedReads == null) {
				continue;  //FIXME: why was this path captured if no reads are contained? (rare find)
			}
			for (PairPath read : containedReads)
			{


				Integer numPaths = ReadPerPathCounts.get(read).getFirst();
				Integer count = ReadPerPathCounts.get(read).getSecond();
				supp += count/numPaths;
				totalCounts += count;

				debugMes("READ: " + read + ", numPaths: " + numPaths + ", count: " + count, 15);	
			}

			String ascii_illustration = getPathMappingAsciiIllustration(path, finalPathsToContainedReads.get(path), ReadPerPathCounts);
			debugMes("\nPath Illustration:\n\n" + ascii_illustration + "\n", 10);

			FinalPaths.put(path, new Pair<Integer>(totalCounts,supp));
		}

		return(finalPathsToContainedReads);

	}


	/**
	 * Go over all final paths, and combine those that are too similar.
	 * @param graph
	 * @param FinalPaths
	 * @param PathReads
	 * @param topOrderInts 
	 */
	private static void combineSimilarPaths(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph,
			HashMap<List<Integer>, Pair<Integer>> FinalPaths,
			HashMap<List<Integer>, HashMap<PairPath, Integer>> PathReads) {


		List<List<Integer>> removeSimilarPaths = new ArrayList<List<Integer>>();

		debugMes("\n\n===========\nmethod: combineSimilarPaths()", 15);

		Iterator<List<Integer>> i1,i2;
		String path1S="", path2S="";
		int index1;
		int pathcount1 = 0;
		int pathcount2 = 0;

		for (i1=FinalPaths.keySet().iterator() ; i1.hasNext() ; )
		{
			List<Integer> path1 = i1.next();
			path1S = getPathSeq(graph, path1);

			pathcount1++;

			boolean gotToi1 = false;
			for (i2=FinalPaths.keySet().iterator() ; i2.hasNext() ; )
			{

				pathcount2++;

				debugMes("\n************\nComparing paths: (" + pathcount1 + "," + pathcount2 + ")", 15);

				List<Integer> path2 = i2.next();

				while (!gotToi1 && i2.hasNext())
				{
					if (path2.equals(path1))
						gotToi1 = true;
					path2 = i2.next();

				}

				if (path2.equals(path1))
					break;

				index1=path1S.length();

				path2S = getPathSeq(graph, path2);

				boolean noOverlappingVers = true;
				int v1 = -1,v2 = -1, index2=-1;
				for (int j1=path1.size()-1; j1>0 && noOverlappingVers ; j1--)
				{
					v1 = path1.get(j1);
					index1 -= getSeqVertex(graph, v1).getName().length();
					if (v1!=T_VERTEX.getID())
					{
						index2=path2S.length();
						for (int j2=path2.size()-1; j2>0 && noOverlappingVers ; j2--)
						{
							v2 = path2.get(j2);
							index2 -= getSeqVertex(graph, v2).getName().length();

							if (v1==v2)
								//update noOverlappingVers, so we'll get out of the loop:
								noOverlappingVers = false;
						}
					}
				}

				if (!noOverlappingVers) //check only paths that share vertices
				{
					index1 += getSeqVertex(graph, v1).getName().length();
					index2 += getSeqVertex(graph, v2).getName().length();
					debugMes("checking paths: "+ path1+ 
							"(len="+path1S.length()+") and "+path2+"(len="+path2S.length()+")",15);

					if (path1.lastIndexOf(T_VERTEX.getID())==-1)
						index1--;

					if (path2.lastIndexOf(T_VERTEX.getID())==-1)
						index2--;
					if (twoPathsAreTooSimilar(graph, path1, path2, path1S, path2S, index1, index2))
					{
						debugMes("they are too similar!",15);	
						//remove the shorter path
						removeTheLesserSupportedPath(path1S,path2S,path1,path2,removeSimilarPaths,PathReads);
					}
				}
			}
		}

		for (List<Integer> path2Remove : removeSimilarPaths)
		{
			debugMes("The final path "+path2Remove+" was removed because it was too close to another path",15);
			FinalPaths.remove(path2Remove);
		}
	}



	/**
	 * check for similar paths that end at V, and start at different nodes
	 * remove the shortest of the two
	 * @param graph
	 * @param v
	 * @param Paths
	 * @param PathReads
	 * @param Extensions
	 * @param topOrderInts 
	 */
	private static void combineSimilarPathsThatEndAtV(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph,  SeqVertex v,
			HashMap<SeqVertex, List<List<Integer>>> Paths,
			HashMap<List<Integer>, HashMap<PairPath, Integer>> PathReads,
			HashMap<List<Integer>, Boolean> Extensions) {



		// new Throwable().printStackTrace();

		int vertex_id = v.getID();
		int total_num_paths = Paths.get(v).size();

		debugMes("method: combineSimilarPathsThatEndAtV(" + vertex_id + ") with "+total_num_paths+ " paths", 10);
		debugMes("paths are: "+Paths.get(v),17);

		List<List<Integer>> removeSimilarPaths = new ArrayList<List<Integer>>();
		List<Integer> removedPathsIndices = new ArrayList<Integer>();
		String path1S="", path2S="";
		Iterator<List<Integer>> i1, i2;
		int index1, index2, rIndex;

		int pathCount1 = 0;
		int pathCount2 = 0;

		if (total_num_paths<=1)
			return;


		// all-vs-all comparison among the paths ending at v
		for (i1=Paths.get(v).iterator() ; i1.hasNext() ; )
		{
			List<Integer> path1 = i1.next();
			path1S = getPathSeq(graph, path1);
			index1 = path1S.length()-1;

			pathCount1++;
			pathCount2 = 0;

			if (removedPathsIndices.contains(pathCount1)) {
				continue;
			}

			boolean gotToi1 = false;
			for (i2=Paths.get(v).iterator() ; i2.hasNext() ; )
			{
				List<Integer> path2 = i2.next();

				pathCount2++;

				debugMes("\r*V[" + vertex_id + "] Comparing " + total_num_paths + " paths, pairs:(" + pathCount1 + "," + pathCount2 + ")   ", 12);


				while (!gotToi1 && i2.hasNext())
				{
					if (path2.equals(path1))
						gotToi1 = true;
					path2 = i2.next();
					pathCount2++;
				}

				if (path2.equals(path1))
					break;

				// one of these paths were removed already
				if (removedPathsIndices.contains(pathCount2)) {
					continue;
				}	

				/* false assumption */
				/*
				if (! paths_have_any_node_in_common(path1, path2, false)) {

						debugMes("paths have no node in common, so must not be too similar");
						continue;
				}
				 */

				path2S = getPathSeq(graph, path2);
				index2 = path2S.length()-1;
				debugMes("checking for similarity the two paths: "+path1+ 
						"(len="+path1S.length()+");"+path2+"(len="+path2S.length()+")",15);

				if (twoPathsAreTooSimilar(graph, path1, path2, path1S,path2S,index1,index2))
				{
					debugMes("they are too similar!",15);	
					//remove the shorter path
					rIndex = removeTheLesserSupportedPath(path1S,path2S,path1,path2,removeSimilarPaths,PathReads);
					if (rIndex == 1)// the first path was removed
						removedPathsIndices.add(pathCount1);
					else
						removedPathsIndices.add(pathCount2);


				}
			}
		}

		for (List<Integer> path2Remove : removeSimilarPaths)
		{
			debugMes("The path "+path2Remove+" was removed because it was too close to another path",12);

			Paths.get(v).remove(path2Remove);
			Extensions.remove(path2Remove);

		}



	}


	/** 
	 * compare the sequences of the two paths, and return true if they are more than MIN_PERCENT_IDENTITY_SAME_PATH. 
	 * @param path1s
	 * @param path2s
	 * @param topOrderInts 
	 * @return
	 */
	private static boolean twoPathsAreTooSimilar(
			DirectedSparseGraph<SeqVertex, 
			SimpleEdge> graph,
			List<Integer> path1, 
			List<Integer> path2,
			String path1s, 
			String path2s,
			int index1, 
			int index2) {

		debugMes("-checking twoPathsAreTooSimilar (" + index1 + "," + index2 + ")", 15);

		// ... >V2<.. >V
		Integer V = path1.get(path1.size()-1);
		int numMatches = 0;
		AlignmentStats numPrevMismatchesAndGaps = new AlignmentStats();
		Comparator<String> stringComp = String.CASE_INSENSITIVE_ORDER;
		List<Integer> subP1_list,subP2_list;
		Integer V2 = findLastSharedNode(graph,path1,path2);
		int p1V2index, p2V2index;

		if (V2==-1) { // there is no other shared node other than V, since V2 is the start/sink node.
			p1V2index = -1;
			p2V2index = -1;
			debugMes("&& Paths "+path1+" and "+path2+" do not share a node other than "+V,17);
		} else {
			p1V2index = path1.indexOf(V2);
			p2V2index = path2.indexOf(V2);

			// get path up to the shared node.
			subP1_list = path1.subList(0, p1V2index+1);
			subP2_list = path2.subList(0, p2V2index+1); 


			numPrevMismatchesAndGaps = getPrevCalcNumMismatches(graph, subP1_list, subP2_list);
			debugMes("path prefix alignment stats for: " + subP1_list + " and " + subP2_list + " : " + numPrevMismatchesAndGaps.toString(), 18);
		}

		p1V2index++; // don't include V2 itself
		p2V2index++;

		subP1_list = path1.subList(p1V2index,path1.size());
		subP2_list = path2.subList(p2V2index,path2.size());
		//			numMatches += getPrevCalcNumMatches(graph, subP1_list, subP2_list,stringComp,path1+" and "+path2);


		debugMes("Comparing paths: " + path1 + " and " + path2, 15);
		AlignmentStats numCurrMismatchesAndGaps = getPrevCalcNumMismatches(graph, subP1_list, subP2_list);
		debugMes("Path suffix alignment stats for: " + subP1_list + " and " + subP2_list + " : " + numCurrMismatchesAndGaps.toString(), 18);

		AlignmentStats numTotalMismatchesAndGaps = numPrevMismatchesAndGaps.increment_alignment_stats(numCurrMismatchesAndGaps);
		// add this new entry to the hash, only if we found a V2, otherwise we've already added it:
		if (V2!=-1)
		{
			String P1_s = path1+"";
			String P2_s = path2+"";
			int compRes = stringComp.compare(P1_s, P2_s);

			String key = (compRes>=0)? P1_s+";"+P2_s : P2_s+";"+P1_s;

			//NUM_MATCHES_HASH.put(key,numMatches);
			NUM_MISMATCHES_HASH.put(key,numTotalMismatchesAndGaps);
		}
		int shorterLen = Math.min(getSeqPathLength(graph,path1),getSeqPathLength(graph,path2));
		float path_per_id = 100 - (float)numTotalMismatchesAndGaps.mismatches/shorterLen * 100;
		boolean tooSimilar = isThisTooSimilar(numTotalMismatchesAndGaps.mismatches, numTotalMismatchesAndGaps.max_internal_gap_length, path_per_id);

		DecimalFormat df = new DecimalFormat("#.##");

		debugMes("Running PATH alignment of : " + path1 + " to " + path2 + " :: numMM:" + numTotalMismatchesAndGaps.mismatches  
				+ ", max_internal_gap: " + numTotalMismatchesAndGaps.max_internal_gap_length
				+ ", path_per_id = " + df.format(path_per_id) + ", tooSimilar: " + tooSimilar, 18);

		debugMes(numTotalMismatchesAndGaps.toString(), 18);


		return(tooSimilar);





	}

	/**
	 * for p1, p2 find the latest nodes that they share (v2), and the last node is also shared (v)
	 * find v2 by going backwards on the paths, while using the topological order of the nodes, and advancing while keeping them in order.
	 * @param graph 
	 * @param path1
	 * @param path2
	 * @param topOrderInts 
	 * @return
	 */
	private static Integer findLastSharedNode(DirectedSparseGraph<SeqVertex,SimpleEdge> graph, List<Integer> path1,
			List<Integer> path2) {
		List<SeqVertex> reversePath1 = getReverseSeqVertexPath(graph,path1);
		List<SeqVertex> reversePath2 = getReverseSeqVertexPath(graph,path2);

		Iterator<SeqVertex> p1_iter = reversePath1.iterator();
		Iterator<SeqVertex> p2_iter = reversePath2.iterator();

		SeqVertex p1_v = p1_iter.next();
		SeqVertex p2_v = p2_iter.next();

		// we know the first elements are the same, we want the next ones
		p1_v = p1_iter.next();
		p2_v = p2_iter.next();
		SeqVertexFinishTimeComparator finishingTimeComparator = new SeqVertexFinishTimeComparator();


		while (p1_v!=p2_v && p1_iter.hasNext() && p2_iter.hasNext())
		{
			if (finishingTimeComparator.compare(p1_v,p2_v)>=0)
				p1_v = p1_iter.next();
			else
				p2_v = p2_iter.next();
		}
		return (p1_v==p2_v)? p1_v.getID() : -1;
	}



	/**
	 * given the graph and a list of integers, return the reverse list of seqVertices
	 * @param graph
	 * @param path
	 * @return
	 */
	private static List<SeqVertex> getReverseSeqVertexPath(DirectedSparseGraph<SeqVertex,SimpleEdge> graph, List<Integer> path) {
		List<SeqVertex> res = new ArrayList<SeqVertex>();
		for (int i=path.size()-1; i>=0 ; i--){
			res.add(getSeqVertex(graph, path.get(i)));
		}
		return res;
	}






	/** 
	 * given the key of the two paths, return their number of matches.
	 * If this calculation hasn't been done before, calc and save it.
	 * @param key
	 * @return
	 */
	private static AlignmentStats getPrevCalcNumMismatches (			
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph,
			List<Integer> P1_list, List<Integer> P2_list) {

		Comparator<String> stringComp = String.CASE_INSENSITIVE_ORDER;

		String P1_s = P1_list+"";
		String P2_s = P2_list+"";


		int compRes = stringComp.compare(P1_s, P2_s);

		String key = (compRes>=0)? P1_s+";"+P2_s : P2_s+";"+P1_s;
		Integer V2 = P1_list.get(P1_list.size()-1);

		debugMes("getPrevCalcNumMismatches() path1: " + P1_s + ", Path2: " + P2_s, 17);

		debugMes("&& Paths share "+ V2 + " so we compare "+key,17);
		if (compRes==0) {//subP1==subP2, just add their length
			debugMes("&& Paths "+P1_s + " and " + P2_s +" are identical, so we add 0 diffs" ,17);
			AlignmentStats a = new AlignmentStats();
			// perfect matches, no gaps.
			String path1s = getPathSeq(graph, P1_list);
			a.matches = path1s.length();
			a.alignment_length = path1s.length();
			return(a);
		}


		if (!NUM_MISMATCHES_HASH.containsKey(key)){
			String path1s = getPathSeq(graph, P1_list);
			String path2s = getPathSeq(graph, P2_list);

			if (VERBOSE_LEVEL >= 15) {

				try {
					// write files to disk for further exploration
					PrintStream seq1s_ofh = new PrintStream(new FileOutputStream("_t_seqA.fa"));
					PrintStream seq2s_ofh = new PrintStream(new FileOutputStream("_t_seqB.fa"));

					seq1s_ofh.println(">seqA");
					seq1s_ofh.println(path1s);

					seq2s_ofh.println(">seqB");
					seq2s_ofh.println(path2s);

					seq1s_ofh.close();
					seq2s_ofh.close();
				}
				catch (Exception e) {
					e.printStackTrace();
				}
			}


			debugMes("-alignment not cached, computing: " + P1_list + " to " + P2_list, 12);
			debugMes("-path1s length: " + path1s.length() + ", path2s length: " + path2s.length(), 12);


			//TODO: If one path sequence is a substring of the other, no reason to do an alignment.
			//  this can be known based on the path list comparison, without needing to do a string comparison.



			//align the two seqs

			boolean is_at_start_of_graph = (P1_list.get(0) == -1 || P2_list.get(0) == -1);
			boolean is_at_end_of_graph = (P1_list.get(P1_list.size()-1) == -2 || P2_list.get(P2_list.size()-1) == -2);

			AlignmentStats stats;

			if ( (path1s.length() > MAX_SEQ_LEN_DP_ALIGN && path2s.length() > MAX_SEQ_LEN_DP_ALIGN) 
					||
					path1s.length() > 100000   // problems can arise in the alignment code if either seq is longer
					||
					path2s.length() > 100000

					) {
				// heuristic...   if seqs are this long, it's highly unlikely they'd be too similar anyway
				stats = ZipperAlignment.doZipperAlignment("A", path1s, "B", path2s);
			}
			else if (SMITH_WATERMAN_ALIGN_FLAG) {
				debugMes("-running Smith-Waterman alignment of path sequences", 15);
				Alignment alignment = NWalign.run_SW_alignment("A", path1s, "B", path2s, 4, -5, 10, 1);
				debugMes (new jaligner.formats.Pair().format(alignment), 17);
				stats = new AlignmentStats(alignment);
			}
			else {
				// Needleman Wunsch Global Alignment is default
				debugMes("-running Needleman-Wunsch alignment of path sequences", 15);
				Alignment alignment	= NWalign.run_NW_alignment("A", path1s, "B", path2s, 4, -5, 10, 1);   //NW locks up or takes too long with very long sequences (eg. 40kb align to 6kb)
				debugMes (new jaligner.formats.Pair().format(alignment), 17);
				stats = new AlignmentStats(alignment);
			}


			int alignment_length = stats.alignment_length;
			int matches = stats.matches;
			int mismatches = stats.mismatches;
			int gaps = stats.gaps;

			int right_gap_len = stats.right_gap_length;
			int left_gap_len = stats.left_gap_length;
			int max_internal_gap_length = stats.max_internal_gap_length;

			float percent_A_in_alignment = (float) stats.get_count_of_bases_in_aligned_region("A") / (path1s.length()) * 100;
			float percent_B_in_alignment = (float) stats.get_count_of_bases_in_aligned_region("B") / (path2s.length()) * 100;

			debugMes("Percent A in alignment = " +  stats.get_count_of_bases_in_aligned_region("A") + " / " + path1s.length() + " = " + percent_A_in_alignment + "%",15);
			debugMes("Percent B in alignment = " + stats.get_count_of_bases_in_aligned_region("B") + " / " + path2s.length() + " = " + percent_B_in_alignment + "%",15);

			float max_percent_aligned = Math.max(percent_A_in_alignment, percent_B_in_alignment);


			float percent_identity = (float)matches/(matches+mismatches) * 100;
			float percent_gapped = (float)gaps/alignment_length * 100;

			debugMes("Matches: " + matches + ", Mismatches: " + mismatches + ", gaps: " + gaps + ", align_len: " + alignment_length,15);
			debugMes("percent_identity: " + percent_identity + ", percent_gapped: " + percent_gapped,15);
			debugMes("max_percent_aligned: " + max_percent_aligned,15);
			debugMes("max internal gap length: " + max_internal_gap_length + "\n",15);


			int total_significant_diffs = 0;
			if (is_at_start_of_graph || is_at_end_of_graph) {
				total_significant_diffs = mismatches + gaps; 
				debugMes("(start of graph) Total number of significant alignment diffs = (mismatches: " + mismatches 
						+ " + internal_gaps: " + gaps
						+ " + right_gap_len: "+ right_gap_len
						+ "  = " + total_significant_diffs, 15); 

				// the max internal gap length value based ignores the left gap length
				if (is_at_start_of_graph) {
					stats.left_gap_length = 0; 
					if (! is_at_end_of_graph) {
						// deal with right-gap in alignment stats
						stats.max_internal_gap_length = Math.max(stats.max_internal_gap_length, stats.right_gap_length);
						total_significant_diffs += stats.right_gap_length;
						stats.gaps += stats.right_gap_length;
					}
				}
				if (is_at_end_of_graph) {
					stats.right_gap_length = 0;
					if (! is_at_start_of_graph) {
						// deal with left-gap in alignment stats
						stats.max_internal_gap_length = Math.max(stats.max_internal_gap_length, stats.left_gap_length);
						total_significant_diffs += stats.left_gap_length;
						stats.gaps += stats.left_gap_length;
					}
				}


			}
			else {
				total_significant_diffs = mismatches + gaps + left_gap_len + right_gap_len; // all gaps count TODO: ignore right gap length if at end of graph
				debugMes("(internal of graph) Total number of significant alignment diffs = (mismatches: " + mismatches 
						+ " + internal_gaps: " + gaps
						+ " + left_gap_len: " + left_gap_len 
						+ " + right_gap_len: "+ right_gap_len
						+ "  = " + total_significant_diffs, 15); 


				// adjust max internal gap length value based on left or right gap lengths, since this is an internal node
				stats.max_internal_gap_length = Math.max(stats.max_internal_gap_length, stats.left_gap_length);
				stats.max_internal_gap_length = Math.max(stats.max_internal_gap_length, stats.right_gap_length);

			}

			stats.total_not_matched = total_significant_diffs; // update based on above.

			NUM_MISMATCHES_HASH.put(key, stats); 

		}
		return NUM_MISMATCHES_HASH.get(key);
	}




	/**
	 * given all the params, decide if the two seqs are too similar
	 * FIXME - find a better criteria.
	 * @param numMM - number of mismatches
	 * @param longestMMstretch
	 * @param shortestLen
	 * @return
	 */




	private static boolean isThisTooSimilar(int numMM, int max_internal_gap_length, float percent_identity) { // number of differences, not just mismatches, includes gaps


		DecimalFormat df = new DecimalFormat("#.##");



		boolean too_similar = ( max_internal_gap_length <= MAX_INTERNAL_GAP_SAME_PATH
				&&
				(	numMM <= MAX_DIFFS_SAME_PATH || percent_identity >= MIN_PERCENT_IDENTITY_SAME_PATH));


		debugMes("the two paths have these stats: numMM="+numMM
				+ ", max_internal_gap_length=" + max_internal_gap_length
				+  ", identity="+df.format(percent_identity)+"%" 
				+ ", tooSimilar: " + too_similar,15);

		return (too_similar);  // same as saying they are too similar... I just process the logic better in the terms of them not being too different.

	}


	/**
	 * given two paths (and their seqs) remove the shorter path, and add its reads to the other one.
	 * if the are equal in length, remove the lighter one.
	 * @param path1S
	 * @param path2S
	 * @param path1
	 * @param path2
	 * @param removeSimilarPaths
	 * @param PathReads
	 */
	private static int removeTheLesserSupportedPath(String path1S, String path2S,
			List<Integer> path1, List<Integer> path2, List<List<Integer>> removeSimilarPaths,
			HashMap<List<Integer>, HashMap<PairPath, Integer>> PathReads) {
		List<Integer> path2remove,path2keep;

		int sum1=0,sum2=0;
		if (PathReads.get(path1)!=null)
			for (Integer s : PathReads.get(path1).values())
				sum1+=s;
		if (PathReads.get(path2)!=null)
			for (Integer s : PathReads.get(path2).values())
				sum2+=s;

		if (sum1<sum2)
		{
			path2remove = path1;
			path2keep = path2;
		} 
		else if (sum1 > sum2)
		{
			path2remove = path2;
			path2keep = path1;
		}
		else {
			// same read support, so choose the longer sequence over the shorter one.

			if (path1S.length() >= path2S.length())
			{
				path2remove = path2;
				path2keep = path1;
			}
			else
			{
				path2remove = path1;
				path2keep = path2;
			}


		}

		debugMes("removing path "+path2remove+" and keeping path "+path2keep,15);

		if (!removeSimilarPaths.contains(path2remove))
			removeSimilarPaths.add(path2remove);
		if (PathReads.get(path2remove)!=null)
		{
			if (PathReads.get(path2keep)==null)
				PathReads.put(path2keep, new HashMap<PairPath,Integer>());

			PathReads.get(path2keep).putAll(PathReads.get(path2remove));
			PathReads.remove(path2remove);
		}	

		return (path2remove==path1)? 1:2;
	}




	/** 
	 * Given this path, ask whether it has enough support, either by last triplet, or by length
	 * @param readsOfPathUntilV - reads of this path, so far
	 * @param path - the path so far
	 * @param u - the extension to the path
	 * @param graph
	 * @param dijkstraDisWoVer
	 * @return
	 */
	private static boolean pathHasEnoughReadSupport(
			HashMap<PairPath, Integer> readsOfPathUntilV, List<Integer> path,
			SeqVertex u, DirectedSparseGraph<SeqVertex, SimpleEdge> graph,
			DijkstraDistanceWoVer<SeqVertex, SimpleEdge> dijkstraDisWoVer) {


		List<Integer> pathWU = new ArrayList<Integer>(path);
		pathWU.add(u.getID());

		List<Integer> subPath = new ArrayList<Integer>();
		subPath.add(0, u.getID());

		SeqVertex v = getSeqVertex(graph,path.get(path.size()-1));



		if (LENIENT_PATH_CHECKING) {

			// nodes u and v exist within a read pair path, and the read(s) are compatible with the this tentative path.
			return(pathHasTerminalCompatibleReadSupport(path, v, u, graph, readsOfPathUntilV, dijkstraDisWoVer));

		}

		else if (USE_TRIPLETS)  // never do it this way, option turned off permanently but retained for legacy sake.
		{

			subPath.add(0, v.getID());
			if (path.size()>1)
				subPath.add(0,path.get(path.size()-2));



			return (subPathHasEnoughReadSupport(pathWU, readsOfPathUntilV,subPath,graph,dijkstraDisWoVer));
		}

		else{
			// default method

			int lookBack = PATH_REINFORCEMENT_DISTANCE; 
			int lenSoFar = u.getName().length();
			for (int j = path.size()-1 ; j>=0 && lenSoFar < lookBack; j--){
				SeqVertex vLast = getSeqVertex(graph, path.get(j));
				subPath.add(0, vLast.getID());
				lenSoFar += vLast.getName().length();
			}

			return (subPathHasEnoughReadSupport(pathWU, readsOfPathUntilV,subPath,graph,dijkstraDisWoVer));
		}
	}



	/**
	 * Check that the given sub-path has N supporting reads or more.
	 * A supporting read is a read that enforces this triplet
	 * @param readsOfPathUntilV
	 * @param subPath
	 * @param graph
	 * @param dijkstraDisWoVer
	 * @return
	 */
	private static boolean subPathHasEnoughReadSupport(
			List<Integer> fullPathWU,
			HashMap<PairPath, Integer> readsOfPathUntilV,
			List<Integer> subPath,
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph,
			DijkstraDistanceWoVer<SeqVertex, SimpleEdge> dijkstraDisWoVer) {

		debugMes("-checking if subPath has enough read support. Exploring sub path: " + subPath, 18);

		// note, subpath contains U as final node.


		int numberReadsSupporting = 0;
		for (PairPath pPath : readsOfPathUntilV.keySet())
		{


			boolean thisReadOK = true;

			if (! ORIGINAL_PATH_EXTENSIONS) {
				// COMPATIBLE_PATH_EXTENSIONS MODE, NOW THE DEFAULT
				boolean subPathContained = pPath.containsSubPath(subPath);
				boolean pathWUcompatible = pPath.isCompatible(fullPathWU);

				debugMes("CPATEXT: subPath: " + subPath + " contained by read: " + pPath.get_paths() + " : " + subPathContained, 18);
				debugMes("CPATEXT: pathWU: " + fullPathWU + " compatible with read: " + pPath.get_paths() + " : " + pathWUcompatible, 18);

				thisReadOK = (subPathContained && pathWUcompatible);

			}
			else {

				// Examining within the context of the entire graph

				for (Integer vTempID : subPath) {
					if (thisReadOK)
						thisReadOK = thisReadOK && 	
						readEnforcesVertex(graph, dijkstraDisWoVer, pPath, getSeqVertex(graph, vTempID));
				}
			}

			debugMes("examining subPath: " + subPath + " for reinforcement by read: " + pPath.get_paths() + " :" + thisReadOK, 18);

			if (thisReadOK)
			{
				numberReadsSupporting+=readsOfPathUntilV.get(pPath);
				debugMes("the read "+pPath+"("+readsOfPathUntilV.get(pPath)+") enforces the sub-path ("+subPath+")",20);
			} else
				debugMes("the read "+pPath+"("+readsOfPathUntilV.get(pPath)+") does not enforce the sub-path ("+subPath+")",20);

		}

		debugMes("-found: " + numberReadsSupporting + " reads supporting subpath.", 18);

		boolean res = (numberReadsSupporting>=MIN_READ_SUPPORT_THR);
		if (res)
			debugMes("the sub-path ("+subPath+") has PASSED",20);
		else
			debugMes("the sub-path ("+subPath+") has NOT PASSED",15);

		return res;	
	}






	/**
	 * Check whether there are at least N reads enforcing 
	 * @param graph
	 * @param dijkstraDis
	 * @param pPath
	 * @param v
	 * @return
	 */
	private static boolean readEnforcesVertex(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph,
			DijkstraDistanceWoVer<SeqVertex, SimpleEdge> dijkstraDisWoVer,
			PairPath pPath, SeqVertex v) {

		// read contains vertex v
		if (v==null || pPath.containsID(v.getID()) || v.equals(ROOT) || v.equals(T_VERTEX))
			return true;

		// is path from the root (sink) to first vertex of the read disabled by removing vertex v of subpath?
		SeqVertex firstV = getSeqVertex(graph, pPath.getFirstID());
		if (dijkstraDisWoVer.getDistanceWoVer(ROOT, firstV,v)==null)
			return true;
		// is path from last vertex of the read to the terminal node (sink) disabled by removing vertex v of subpath?
		SeqVertex lastV = getSeqVertex(graph, pPath.getLastID());
		if (dijkstraDisWoVer.getDistanceWoVer(lastV, T_VERTEX,v)==null)
			return true;

		if (pPath.hasSecondPath())
		{

			// is path from beginning to end of read's pair-path disrupted by removing vertex v of subpath?

			//last of first path
			lastV = getSeqVertex(graph, pPath.getLastID_path1());
			//first of second path
			firstV = getSeqVertex(graph, pPath.getFirstID_path2());
			if (dijkstraDisWoVer.getDistanceWoVer(lastV,firstV,v)==null)
				return true;
		}
		return false;
	}


	private static boolean pathHasTerminalCompatibleReadSupport(
			List<Integer> path,
			SeqVertex v, SeqVertex u, 
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph,
			HashMap<PairPath, Integer> readsOfPathUntilV,
			DijkstraDistanceWoVer<SeqVertex, SimpleEdge> dijkstraDisWoVer) {


		List<Integer> tentativePath = new Vector<Integer>(path);
		tentativePath.add(u.getID());

		Integer v_id = v.getID();
		Integer u_id = u.getID();

		List<Integer> subPath = new ArrayList<Integer>();
		subPath.add(v_id);
		subPath.add(u_id);

		int num_compatible_paths = 0;

		for (PairPath pPath : readsOfPathUntilV.keySet()) {

			//if (pPath.containsID(v_id) && pPath.containsID(u_id)) {
			if (pPath.containsSubPath(subPath)) {
				debugMes("Checking for compatibility.  Path: " + tentativePath +  " with " + pPath, 18);
				// got both terminal path vertices.  Check for read compatibility.
				if (pPath.isCompatible(path)) {
					debugMes("\tPaths ARE compatible.", 18);
					num_compatible_paths += readsOfPathUntilV.get(pPath);
				}

			}

		}

		debugMes("\t" + num_compatible_paths + " read (pair) paths were found to be compatible.", 18);

		if (num_compatible_paths >= MIN_READ_SUPPORT_THR) { // note, not using this as triplet support here. 
			//TODO: rename triplet support var
			return(true);
		}
		else {
			return(false);
		}

	}



	private static boolean vertexPairHasDiscontinuousPathSupport(
			List<Integer> path,
			SeqVertex v, SeqVertex u, 
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph,
			HashMap<PairPath, Integer> readsOfPathUntilV,
			DijkstraDistanceWoVer<SeqVertex, SimpleEdge> dijkstraDisWoVer) {


		debugMes("\n\nCurrent path being checked for LENIENT path extension: " + path, 18);

		debugMes("Performing LENIENT path checking between (v,u):\nv: " + v + "\nu: " + u, 18);

		// look for u-v where u is last node of one pairpath, and v-u is the start of another path
		// find a pairpath that ends in v
		// find another pairpath that starts with v-u

		boolean last_vertex_found_as_v = false;
		boolean first_vertices_found_as_vu = false;

		for (PairPath pPath : readsOfPathUntilV.keySet()) {

			debugMes("\t-pairPath: " + pPath, 18);

			SeqVertex last_vertex = getSeqVertex(graph, pPath.getLastID());
			debugMes("\t-Last vertex: " + last_vertex.getID(), 18);

			if (last_vertex.equals(v)) {
				last_vertex_found_as_v = true;
				debugMes("\t\t-found last vertex as (v)", 18);
			}

			List<Integer> first_path = pPath.getPath1();
			if (first_path.size() > 1) {
				SeqVertex first_vertex = getSeqVertex(graph, first_path.get(0));
				SeqVertex second_vertex = getSeqVertex(graph, first_path.get(1));

				debugMes("\t-First,Second: " + first_vertex.getID() + "," + second_vertex.getID(), 18);

				if (first_vertex.equals(v) && second_vertex.equals(u)) {
					first_vertices_found_as_vu = true;
					debugMes("\t\t-found first vertices as (vu)", 18);
				}

			}


			if (first_vertices_found_as_vu && last_vertex_found_as_v) {
				debugMes("\t* FOUND LENIENT EXTENSION", 18);
				return(true);
			}
		}

		debugMes("\t* no LENIENT extension possible", 18);
		return(false);  // no evidence for discontinous support.

	}


	/**
	 * Check whether the pairPath is consistent with the node i
	 * @param pPath
	 * @param i
	 * @param graph
	 * @param dijkstraDis
	 * @return
	 */
	private static boolean readIsConsistentWithNode(PairPath pPath, Integer i,
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph,
			DijkstraDistance<SeqVertex, SimpleEdge> dijkstraDis) {

		//		if (isReadCircular(graph, pPath))
		//			return false;

		if (pPath.containsID(i) || i<0)
			return true;
		SeqVertex vI = getSeqVertex(graph, i);
		SeqVertex firstV = getSeqVertex(graph, pPath.getFirstID());
		// i --> firstV
		if (isAncestral(vI, firstV, dijkstraDis)>0)
			return true;

		SeqVertex lastV = getSeqVertex(graph, pPath.getLastID());
		// lastV --> i
		if (isAncestral(lastV,vI,dijkstraDis)>0)
			return true;

		if (pPath.hasSecondPath())
		{
			//last of first path
			lastV = getSeqVertex(graph, pPath.getLastID_path1());
			//first of second path
			firstV = getSeqVertex(graph, pPath.getFirstID_path2());

			// lastV --> i --> firstV
			if (isAncestral(lastV,vI,dijkstraDis)>0 && isAncestral(vI, firstV, dijkstraDis)>0)
				return true;
		}
		return false;
	}




	/**
	 * given the graph and a list of nodes, calc the length of the seq of this path
	 * @param graph
	 * @param path
	 * @return
	 */
	private static int getSeqPathLength(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph, List<Integer> path) {
		int len = 0;
		for (Integer vid : path)
			if (vid>=0)
				len +=getSeqVertex(graph, vid).getName().length();	
		return len;
	}

	/**
	 * return the number of paths
	 * @param paths
	 * @return number of paths
	 */
	private static int getPathsSize(
			HashMap<SeqVertex, List<List<Integer>>> paths) {
		int res = 0;
		for (SeqVertex key : paths.keySet())
		{
			res+=paths.get(key).size();
		}
		return res;
	}


	/**
	 * returns true iff these two nucleotides are equal
	 * @param n1
	 * @param n2
	 * @return
	 */
	private static boolean areTwoNucleotidesEqual(String n1, String n2)
	{
		if (n1.equals(n2))
			return true;

		if (USE_DEGENERATE_CODE && 
				((DEGENERATE_CODE_REV.containsKey(n1) && DEGENERATE_CODE_REV.get(n1).contains(n2)) ||
						(DEGENERATE_CODE_REV.containsKey(n2) && DEGENERATE_CODE_REV.get(n2).contains(n1))))
			return true;

		return false;
	}

	/**
	 * return the degenerate code representation of the given key
	 * @param key
	 * @return
	 * @throws Exception
	 */
	private static String getDegenerateRepresentation(String key) throws Exception {
		if (DEGENERATE_CODE.containsKey(key))
			return DEGENERATE_CODE.get(key);
		else
			throw new Exception("the letters "+key+" do not have a degenerate representation\n");
	}



	/**
	 * sum the counts of all the reads in this hash
	 * @param readHash
	 * @return
	 */
	private static Integer getSuppCalculation(HashMap<PairPath, Integer> readHash) {
		Integer res = 0;
		for (PairPath key : readHash.keySet())
			res = res + readHash.get(key);
		return res;
	}



	/**
	 * Given the new path (with u), and the set of reads that supported the path until v
	 * update the set of reads that support the new path
	 * @param PathReads 
	 * @param pathWu
	 * @param readsOfPathUntilV
	 * @param i 
	 * @param dijkstraDis 
	 * @param graph 
	 */
	private static void updateReadsOfPath(HashMap<List<Integer>,HashMap<PairPath,Integer>> PathReads, List<Integer> pathWu,
			HashMap<PairPath, Integer> readsOfPathUntilV, Integer i, DirectedSparseGraph<SeqVertex, SimpleEdge> graph, DijkstraDistance<SeqVertex, SimpleEdge> dijkstraDis) {

		if (!PathReads.containsKey(pathWu))
			PathReads.put(pathWu, new HashMap<PairPath,Integer>());

		for (PairPath pPath : readsOfPathUntilV.keySet())
		{
			if (!PathReads.get(pathWu).containsKey(pPath))  // only if this read doesn't exist in the PathReads for this pathWu
				// if this read is consistent with pathWu, then add it
				if (readIsConsistentWithNode(pPath,i,graph,dijkstraDis))
				{
					debugMes("read "+pPath+" is consistent with "+i, 20);
					PathReads.get(pathWu).put(pPath,readsOfPathUntilV.get(pPath));
				}else{
					debugMes("read "+pPath+" is not consistent with "+i, 20);
				}
		}

	}

	//	/**
	//	 * return true iff this read is circular. 
	//	 * A read is considered circular if its gap includes a circle 
	//	 * (the vertex at the end of path1 is inside a circle or the first vertex of path 2 is inside a circle).
	//	 * @param graph
	//	 * @param readPath
	//	 * @return
	//	 */
	//	private static boolean isReadCircular(DirectedSparseGraph<SeqVertex, SimpleEdge> graph, PairPath readPath)
	//	{
	//		if (!readPath.hasSecondPath())
	//			return false;
	//		
	//		if (getSeqVertex(graph, readPath.getLastID()).isInCircle() ||        //lastID of first path is circular 
	//				getSeqVertex(graph, readPath.getFirstID_path2()).isInCircle()) // firstID of second path is circular
	//				{
	//					debugMes("the read "+readPath+" is circular",10);
	//					return true;
	//				} else
	//					return false;
	//	}


	/**
	 * Return the reads, hashed by their starting vertex
	 * @param graph
	 * @param filename
	 * @param originalVerIDsMapping
	 * @param rootIDs
	 * @return
	 * @throws IOException
	 */
	private static HashMap<String, List<Read>> getReadStarts(DirectedSparseGraph<SeqVertex, SimpleEdge> graph,
			String filename,
			HashMap<Integer, LocInGraph> originalVerIDsMapping, Vector<Integer> rootIDs) throws IOException {
		BufferedReader fileB = 	new BufferedReader(new FileReader(filename)); 

		HashMap<String, List<Read>> readNameHash = new HashMap<String, List<Read>>();
		String l = fileB.readLine(); // read header of component
		int numReadsNotMapped = 0;
		int numReadsMapped = 0;
		int line_counter = 0;

		while (fileB.ready())

		{
			l = fileB.readLine();
			if (l.isEmpty())
				continue;

			line_counter++;
			if (line_counter % 1000 == 0 && VERBOSE_LEVEL >= 10)
				System.err.print("\rmapped read [" + line_counter + "]");	

			//			Component 0
			//			>@42MRYAAXX100104:7:100:1000:103#0      11      101393  36      101418          GAAAGACTGTCACCCTTGAGGTGGAGTCCTCTGACACTATTGACAATGTCAAGAGCAAAATCCAAGACAAGGAAGG
			debugMes("Read: " + l, 20);
			String[] fields = l.split("\t");
			fields[0] = fields[0].replaceFirst(">", "");

			List<Integer> pathIDS = null;
			Read r = new Read();
			pathIDS = readAndMapSingleRead(fields,originalVerIDsMapping,graph,r,false);

			debugMes("Read: " + r.getName() + " : " + pathIDS, 19);

			if (pathIDS==null || (pathIDS!=null && pathIDS.isEmpty()))
			{
				numReadsNotMapped++;
			}else
			{

				//add to readNameHash
				if (!readNameHash.containsKey(r.getName()))
					readNameHash.put(r.getName(), new ArrayList<Read>());

				readNameHash.get(r.getName()).add(r);
				numReadsMapped++;

				//System.err.println(r.getName());

			}
		}	



		//		debugMes("number of reads not found in graph = "+numReadsNotMapped +" of a total of "+(numReadsNotMapped+numReadsMapped),10);
		debugMes("number of reads found = "+numReadsMapped+" (from total of "+(numReadsNotMapped+numReadsMapped)+") which came from "+ readNameHash.keySet().size() + " pairs",10);

		if (numReadsNotMapped > .5*(numReadsNotMapped+numReadsMapped))
			debugMes("PROBLEM: less than half of the reads were mapped to this graph ("+numReadsMapped+"/"+(numReadsNotMapped+numReadsMapped)+")",10);

		if (VERBOSE_LEVEL >= 18) {
			for (String readName : readNameHash.keySet()) {
				String descr = "Read name to pairing info: " + readName + " => "; 
				List<Read> read_list = readNameHash.get(readName);
				for (Read r : read_list) {
					descr += r.getPathIDs();
				}
				debugMes(descr, 15);
			}

		}


		return readNameHash;
	}


	/**
	 * given this read, try and map it to the graph. if rev= true, do it in reverse.
	 * @param fields
	 * @param originalVerIDsMapping
	 * @param graph
	 * @param r 
	 * @param rev
	 * @return
	 */
	private static List<Integer> readAndMapSingleRead(String[] fields,
			HashMap<Integer, LocInGraph> originalVerIDsMapping,
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph, Read r, boolean rev) {

		List<Integer> pathIDS = new ArrayList<Integer>();
		LocInGraph fromV;
		Integer startInRead,endInRead,fromOrigV;

		String name;
		String seq;

		name = fields[0];
		if (name.endsWith("/1") || name.endsWith("/2") 
				|| name.endsWith("\1") || name.endsWith("\2")
				|| name.endsWith(":1") || name.endsWith(":2")
				)
			name = name.substring(0, name.length()-2);

		startInRead = Integer.parseInt(fields[1]);
		endInRead = Integer.parseInt(fields[3])+K-1;

		fromOrigV = Integer.parseInt(fields[2]);
		fromV = originalVerIDsMapping.get(fromOrigV);
		seq = fields[6]; //there is an empty field before the seq.


		if (endInRead >= seq.length()) {
			debugMes("read " + name + " has sequence length that is shorter than supposed endInRead marking(" + endInRead + "): " + seq, 0);
			return pathIDS;
		}

		seq = seq.substring(startInRead, endInRead);

		if (fromV!=null)// && toV!=null)
		{
			pathIDS = findPathInGraph(graph,seq,fromV,name);
			if (!pathIDS.isEmpty())
				r.init(name,seq, fromV, startInRead, endInRead,pathIDS);

		}else
			debugMes("read "+name+" was not mapped to graph. original node doesn't exist anymore ("+fromOrigV+")",19);

		return pathIDS;
	}


	/**
	 * Given the graph, and the read, find the path of the read in the graph
	 * @param graph
	 * @param seq
	 * @param fromV
	 * @return
	 */
	private static List<Integer> findPathInGraph(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph, String seq,
			LocInGraph fromV, String readName) {


		List<Integer> path = new ArrayList<Integer>();

		SeqVertex fromVer = getSeqVertex(graph, fromV.getNodeID());
		List<SeqVertex> continueVers = new ArrayList<SeqVertex>();
		continueVers.add(fromVer);
		debugMes("trying to start the mapping to node "+fromVer.getID(),20);
		Integer totalNumMM = 0;
		Path_n_MM_count best_path_mapping = updatePathRecursively(graph,continueVers,seq,fromV.getIndexInNode(),totalNumMM,readName);

		if (best_path_mapping != null) {
			path = best_path_mapping.path;
		}

		return path;
	}





	/**
	 * Update the given path recursively
	 * @param path
	 * @param graph
	 * @param fromVers
	 * @param seq
	 * @param locInNode
	 * @param totalNumMM
	 * @param readName
	 */
	private static Path_n_MM_count updatePathRecursively(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph,
			List<SeqVertex> fromVers, String seq,int locInNode, Integer totalNumMM,String readName) {

		Path_n_MM_count best_path = null;


		for (SeqVertex fromV : fromVers)
		{

			Integer numMM = totalNumMM; // init for each node check

			debugMes("trying to continue the mapping to node "+fromV.getID(),19);
			String verSeq = fromV.getName();
			int startI = locInNode;
			int j=0, i = startI;
			for (; i>=0 && i<verSeq.length() && j<seq.length() ; i++,j++)
			{

				String readLetter = ""+seq.charAt(j);
				String verLetter = ""+verSeq.charAt(i);

				String mismatchFlag = (areTwoNucleotidesEqual(readLetter,verLetter)) ? "" : "XXX mismatch XXX";
				debugMes("Comparing read bases: " + i + ":" + readLetter + ", " + j + ":" + verLetter + " " + mismatchFlag, 21);

				if (!areTwoNucleotidesEqual(readLetter,verLetter)) 
				{
					//we have a mismatch
					numMM++;
					if (numMM>=MAX_MM_ALLOWED)
						break;

					if (seq.length()>j+1 && verSeq.length()>i+1)  // FIXME: bhaas questions: why do this?
					{
						j++;
						i++;
					}
				}
			}

			if (numMM>=MAX_MM_ALLOWED)
			{
				debugMes("read "+readName+" has too many mismatches ("+numMM+")",19);

				//break;  // bugfix, do not break, continue instead
				continue; // try alternative vertex if available

			} else if (j==seq.length())
			{
				// read sequence fully aligned to vertex
				// reached base case.

				debugMes("read" + readName + " ends within node: " + fromV.getID(), 19);

				Integer mm_encountered_here = numMM - totalNumMM;
				if (best_path == null
						||
						best_path.mismatch_count > mm_encountered_here) {
					best_path = new Path_n_MM_count(fromV.getID(), mm_encountered_here);
				}


			}else if (i==verSeq.length()) // move to the next ver
			{
				// vertex sequence fully traversed, examine children vertices

				// Going on to recursive path mapping for read

				List<SeqVertex> continueVers = new ArrayList<SeqVertex>();

				Collection<SimpleEdge> outE = graph.getOutEdges(fromV);
				List<SimpleEdge> outE_list = new ArrayList<SimpleEdge>();
				outE_list.addAll(outE);
				SimpleEdgeComparator edgeComp = new SimpleEdgeComparator();
				Collections.sort(outE_list, edgeComp);

				debugMes("-reached end of vertex, exploring next vertices for continued path extension: " + outE_list, 19);
				for (SimpleEdge e : outE_list)
				{
					SeqVertex v2 = graph.getDest(e);
					debugMes("-edge: " + e + " reaches vertex: " + v2, 21);
					debugMes("-checking that next characters match up: " + v2.getName().charAt(0) + " vs. " + seq.charAt(j), 21);
					if (v2.getName().charAt(0)==seq.charAt(j)) {
						continueVers.add(v2);

					}
				}
				debugMes("-potential vertex extensions to explore include: " + continueVers, 19);
				Path_n_MM_count best_extension = updatePathRecursively(graph,continueVers,seq.substring(j),0,numMM,readName);
				if (best_extension != null) {
					Integer num_mm_encountered = numMM - totalNumMM;
					if (best_path == null 
							||
							(num_mm_encountered + best_extension.mismatch_count < best_path.mismatch_count) ) {
						best_path = best_extension;
						best_path.add_path_n_mm(fromV.getID(), num_mm_encountered);
					}
				}

			}else // the seq hasn't ended, and the vertex hasn't ended either, wrong mapping 
			{
				// should never end up here

			}
		}
		return(best_path);
	}

	/**
	 * create a hash that hold all the original vertices ids and the new ones 	
	 * @param graph
	 * @param rootIDs 
	 * @return the hash
	 */
	private static HashMap<Integer, LocInGraph> getOriginalVerIDsMappingHash(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph) {

		// clear double entries in the prevID list - not sure why they happen?
		for (SeqVertex v : graph.getVertices())
			v.clearDoubleEntriesToPrevIDs();


		HashMap<Integer, LocInGraph> hash = new HashMap<Integer,LocInGraph>();
		for (SeqVertex v : graph.getVertices())
		{

			Integer loc = 0;
			Integer vid = v.getID();
			// if the node id is new, than the real start is in the vector 
			if (vid>LAST_REAL_ID)
				loc = loc-1;
			else
			{
				debugMes("adding to "+vid+": Location of original node "+vid+" in index "+loc,20);
				hash.put(vid, new LocInGraph(vid,loc));

			}

			for (Vector<Integer> vec :  v.getPrevVerIDs())
			{
				loc++;
				for (Integer id : vec)
				{
					debugMes("adding to "+id+": Location of original node "+v.getID()+" in index "+loc,20);
					hash.put(id, new LocInGraph(v.getID(),loc));
				}
			}
		}
		return hash;
	}

	/**
	 * go over the graph file, and count the in flow and out flow of each node
	 * @param firstLetter 
	 * @throws IOException 
	 */
	private static void preProcessGraphFile(String filename,
			HashMap<Integer, Integer> outFlow, HashMap<Integer, Integer> inFlow, HashMap<Integer,String> firstLetter) throws IOException {

		BufferedReader fileB = 	new BufferedReader(new FileReader(filename)); 
		String l = fileB.readLine(); // read header of component
		Integer from, to, supp;

		while (fileB.ready())

		{
			l = fileB.readLine();
			//	0       -1      3       ATTGAAAGCAAGTTTTCTTCGAAT        0
			//	1       0       3       TTGAAAGCAAGTTTTCTTCGAATT        0
			//	to		from	supp	kmer							stam       
			String[] fields = l.split("\t");
			from = Integer.parseInt(fields[1]);
			to = Integer.parseInt(fields[0]);
			supp = Integer.parseInt((fields[2]));
			String kmer = fields[3];

			if (!outFlow.containsKey(from))
				outFlow.put(from, supp);
			else
				outFlow.put(from, outFlow.get(from)+supp);

			if (!inFlow.containsKey(to))
				inFlow.put(to, supp);
			else
				inFlow.put(to, inFlow.get(to)+supp);

			firstLetter.put(to,kmer.substring(0,1));
		}
	}


	/**
	 * given the filename, make a graph out of the connected components
	 * This time, keep the first letter of each kmer:
	 * keep the whole kmer, and then if there is an edge out, leave only first letter 
	 * @param filename
	 * @param rootIDs 
	 * @param inFlow in flow for all vertices
	 * @param outFlow out flow for all vertices
	 * @param firstLetter 
	 * @return
	 * @throws IOException
	 */
	private static DirectedSparseGraph<SeqVertex, SimpleEdge> buildNewGraphFirstLetter(String filename, 
			Vector<Integer> rootIDs, HashMap<Integer,Integer> outFlow, HashMap<Integer,Integer> inFlow, 
			HashMap<Integer, String> firstLetter) 
					throws IOException
					{

		BufferedReader fileB = 	new BufferedReader(new FileReader(filename)); 
		DirectedSparseGraph<SeqVertex, SimpleEdge> graph = 
				new DirectedSparseGraph<SeqVertex,SimpleEdge>();
		String l = fileB.readLine(); // read header of component
		Integer from, to;
		double supp;
		int linecount = 0;
		while (fileB.ready())

		{
			linecount++;
			if (VERBOSE_LEVEL >= 18 && linecount % 17 == 0) {
				System.err.print("\r[" + linecount + "]  ");
			}


			l = fileB.readLine();
			//	0       -1      3       ATTGAAAGCAAGTTTTCTTCGAAT        0
			//	1       0       3       TTGAAAGCAAGTTTTCTTCGAATT        0
			//	to		from	supp	kmer							stam       
			String[] fields = l.split("\t");
			from = Integer.parseInt(fields[1]);
			to = Integer.parseInt(fields[0]);
			supp = Double.parseDouble((fields[2]));
			if (supp < INITIAL_EDGE_ABS_THR )
				continue;

			if (from>LAST_ID)
				LAST_ID = from;

			if (to>LAST_ID)
				LAST_ID = to;

			String kmer = fields[3];
			K = kmer.length();
			SeqVertex toV = getSeqVertex(graph, to);
			SeqVertex fromV = getSeqVertex(graph, from);
			if (fromV==null && from>=0)
			{
				fromV = new SeqVertex(from,firstLetter.get(from)+""+kmer.substring(0,K-1));
				graph.addVertex(fromV);
			}

			boolean isRoot = (from<0 || fromV==null);

			if (isRoot)
			{
				if (toV==null)
				{
					toV = new SeqVertex(to, kmer,supp);
					graph.addVertex(toV);
					rootIDs.add(to);
				}
			}
			else
			{
				if (toV==null)
				{
					toV = new SeqVertex(to, kmer);
					graph.addVertex(toV);
				}
				SimpleEdge e = new SimpleEdge(supp); 
				graph.addEdge(e, fromV, toV);
			}

		}

		//Go over the whole graph, and if there edges coming out, leave only first letter
		for (SeqVertex v : graph.getVertices())
			if (graph.outDegree(v)>0)
				v.removeAllButFirstLetter();

		return graph;
					}




	/**
	 * white to dot file with shortened seqs 
	 * @param graph
	 * @param p
	 * @param name
	 */
	private static void writeDotFile(DirectedSparseGraph<SeqVertex, SimpleEdge> graph,
			PrintStream p, String name)
	{
		writeDotFile(graph,p,name,false);
	}

	/**
	 * Write to dot file, where the list of paths are colored red -> blue
	 * @param graph
	 * @param p
	 * @param name
	 * @param vertices which vertices to print
	 */
	private static void writeDotFile(DirectedSparseGraph<SeqVertex, SimpleEdge> graph,
			PrintStream p, String name,boolean printFullSeq)
	{

		p.println("digraph "+name+"{");
		SeqVertex toVertex;
		int weight;

		//for each edge decide it's color
		for (SeqVertex vertex : graph.getVertices())
		{ //go over all vertices

			String verDesc = ""+vertex.getID()+" [label=\"";
			if (printFullSeq)
				verDesc = verDesc.concat(""+vertex.getLongtSeqWID() + "["+vertex.getName().length()+"]\"");
			else
				verDesc = verDesc.concat(""+vertex.getShortSeqWID() + "["+vertex.getName().length()+"]\"");

			if (vertex.getWeightAvg()>25)
				verDesc = verDesc.concat(" ,style=bold,color=\"#AF0000\"");

			verDesc = verDesc.concat("]");
			if (!vertex.equals(T_VERTEX) && !vertex.equals(ROOT))
				p.println(verDesc);


			for (SimpleEdge edge : graph.getOutEdges(vertex)) //get all edges of vertex->?
			{
				toVertex = graph.getDest(edge);

				weight = (int) Math.round(edge.getWeight());
				String edgeStyle = "[label="+ weight +"]";

				if (weight>20)
					edgeStyle = "[style=bold,label="+ weight +",color=\"#AF0000\"]";
				if (!toVertex.equals(T_VERTEX) && !vertex.equals(ROOT))
					p.println(vertex.getID() + "->" + toVertex.getID() +edgeStyle);

			}
		}


		p.println("}");

	}



	/**
	 * Compact the given graph:
	 * for each vertex, if degree out = degree in = 1, and nextVertexIn ==1, remove this vertex, and connect edges
	 * @param graph
	 */
	private static boolean compactLinearPaths(DirectedSparseGraph<SeqVertex, SimpleEdge> graph)
	{
		debugMes("=================\nCOMPACTING THE GRAPH\n=================",10);
		//compact vertices
		Vector<SeqVertex> removeVertices = new Vector<SeqVertex>();
		Vector<SimpleEdge> removeEdges = new Vector<SimpleEdge>();
		boolean changed = false;
		for (SeqVertex v1 : graph.getVertices())
		{
			//			debugMes("looking at vertex: "+v1);
			while (!v1.equals(ROOT) && graph.outDegree(v1)==1 )
			{
				SimpleEdge e = null;
				for (SimpleEdge ei : graph.getOutEdges(v1))
					e = ei;
				SeqVertex v2 = graph.getDest(e);
				if (graph.inDegree(v2)!=1 || v2.isToBeDeleted() || v2.equals(T_VERTEX) || v1.equals(v2))
					break;
				debugMes("Found potential edge: "+e +" between "+v1 +" and "+v2,20);
				v1.concatVertex(v2, e.getWeight(),LAST_REAL_ID);
				debugMes("removing vertex "+v2+" was concatenated into "+v1,20);

				removeVertices.add(v2);
				v2.setToBeDeleted(true);

				changed = true;
				removeEdges.clear();
				for (SimpleEdge e2 : graph.getOutEdges(v2))
				{
					SeqVertex v3 = graph.getDest(e2);
					debugMes("Want to move edge " + e2 + "("+v2 +"->"+v3+") to ("+v1+"->"+v3,20);

					SimpleEdge newEdge = new SimpleEdge(e2);
					graph.addEdge(newEdge, v1, v3);

					removeEdges.add(e2);
				}

				for (SimpleEdge re : removeEdges)
				{
					debugMes("removing edge " + re + "("+graph.getSource(re) +"->"+graph.getDest(re)+")",20);
					graph.removeEdge(re);
				}
				debugMes("removing edge " + e + "("+v1 +"->"+v2+")",20);
				graph.removeEdge(e);

			}
		}
		//remove all vertices that we don't want
		for (SeqVertex v : removeVertices)
		{
			graph.removeVertex(v);
		}
		return changed;
	}



	/**
	 * remove light edges from the graph. return true if something has changed
	 * @param graph
	 * @return
	 */
	private static boolean removeLightEdges(DirectedSparseGraph<SeqVertex, SimpleEdge> graph)
	{
		debugMes("removeLightEdges()", 10);

		boolean comp = false ; //removeLightCompEdges(graph);
		boolean in = removeLightInEdges(graph);
		boolean out = removeLightOutEdges(graph);
		boolean flow = removeLightFlowEdges(graph);
		return comp || in || out || flow;
	}


	/**
	 * Given a graph, go over all vertices and remove incoming or outgoing edges that do not match the flow (<2% coverage) see FLOW_THR
	 * When considering flow, this considers both the incoming and outgoing edges, but also the average node coverage.
	 * @param graph
	 * @return true if graph was changed.
	 */
	private static boolean removeLightFlowEdges(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph) {
		debugMes("=================\nREMOVING LIGHT FLOW EDGES\n=================",10);

		boolean changed = false;
		for (SeqVertex v : graph.getVertices())
		{
			if (graph.inDegree(v)==0 && graph.outDegree(v)==0)
				continue;

			int totalIn = 0, totalOut = 0;
			for (SimpleEdge e : graph.getInEdges(v))
				totalIn+=e.getWeight();

			for (SimpleEdge e : graph.getOutEdges(v))
				totalOut+=e.getWeight();

			debugMes("FLOW: total in for vertex "+v+" is "+totalIn + " total out  is "+totalOut+" averageCov="+v.getWeightAvg(),20);

			Collection<SimpleEdge> removeEdges = new HashSet<SimpleEdge>();
			for (SimpleEdge e : graph.getOutEdges(v))
			{
				if (e.getWeight()<totalIn* FLOW_THR || e.getWeight()<v.getWeightAvg()*FLOW_THR)
					removeEdges.add(e);
			}

			for (SimpleEdge e : graph.getInEdges(v))
			{
				if (e.getWeight()<totalOut*FLOW_THR || e.getWeight()<v.getWeightAvg()*FLOW_THR)
					removeEdges.add(e);
			}

			for (SimpleEdge re : removeEdges)
			{
				debugMes("removing low flow edge "+re+" from "+ graph.getSource(re)+" to "+graph.getDest(re),20);
				graph.removeEdge(re);
				changed = true;
			}
		}
		return changed;
	}
	/**
	 * go over the graph, and remove edges that are less than EDGE_THR (5%) from the rest of the entry flow
	 * @param graph
	 */
	private static boolean removeLightInEdges(DirectedSparseGraph<SeqVertex, SimpleEdge> graph)
	{
		debugMes("=================\nREMOVING LIGHT In EDGES\n=================",10);
		boolean somethingChanged = false;
		Queue<SeqVertex> allCurVers = new LinkedList<SeqVertex>(graph.getVertices());
		SeqVertex v = null;
		while ((v = allCurVers.poll())!=null)
		{
			if (graph.inDegree(v)<=1)
				continue;
			Vector<SimpleEdge> removeEdges = new Vector<SimpleEdge>();
			int totalIn = 0;
			for (SimpleEdge inE : graph.getInEdges(v))
			{
				totalIn+=inE.getWeight();
			}

			for (SimpleEdge inE : graph.getInEdges(v))
			{
				if (inE.getWeight() <= totalIn*EDGE_THR)
				{
					debugMes("removing the edge: "+graph.getSource(inE)+"->"+graph.getDest(inE)+" ("+inE.getWeight()+" <= "+totalIn*EDGE_THR+")",20);
					removeEdges.add(inE);
					somethingChanged = true;
				}
			}
			for (SimpleEdge e : removeEdges)
				graph.removeEdge(e);
		}
		return somethingChanged;
	}


	/**
	 * go over the graph, and remove edges that are less than EDGE_THR (10%) from the rest of the exit flow
	 * @param graph
	 */
	private static boolean removeLightOutEdges(DirectedSparseGraph<SeqVertex, SimpleEdge> graph)
	{
		debugMes("=================\nREMOVING LIGHT OUT EDGES\n=================",10);
		boolean somethingChanged = false;

		Queue<SeqVertex> allCurVers = new LinkedList<SeqVertex>(graph.getVertices());
		SeqVertex v = null;
		while ((v = allCurVers.poll())!=null)
		{
			if (graph.outDegree(v)<=1)
				continue;
			Vector<SimpleEdge> removeEdges = new Vector<SimpleEdge>();
			int totalOut = 0;
			for (SimpleEdge outE : graph.getOutEdges(v))
			{
				totalOut+=outE.getWeight();
			}

			for (SimpleEdge outE : graph.getOutEdges(v))
			{
				if (outE.getWeight() <= totalOut*EDGE_THR)
				{
					debugMes("removing the edge: "+graph.getSource(outE)+"->"+graph.getDest(outE),20);
					removeEdges.add(outE);
					somethingChanged = true;
				}
			}
			for (SimpleEdge e : removeEdges)
				graph.removeEdge(e);

		}
		return somethingChanged;
	}

	/**
	 * Return the SeqVertex with the given id within the given graph.
	 * @param graph
	 * @param id
	 * @return
	 */
	private static SeqVertex getSeqVertex(DirectedSparseGraph<SeqVertex, SimpleEdge> graph, int id)
	{

		return(SeqVertex.retrieveSeqVertexByID(id));

		/*  orig code too slow for large graphs
		for (SeqVertex v : graph.getVertices())
		{
			if (v.getID() == id)
				return v;
		}
		return null;
		 */

	}


	/**
	 * Given the string seq, return it in fasta format
	 * @param seq - seq
	 * @param name - seq name
	 * @return
	 */
	private static String getSeqFasta(String seq,String name){
		String res = "";
		res = res.concat(">"+name+"\n");

		int i=0;
		for (; i<seq.length()-LINE_LEN ; i+=LINE_LEN)
		{
			res = res.concat(seq.substring(i, i+LINE_LEN)+"\n");
		}
		res = res.concat(seq.substring(i)+"\n");
		return res;
	}


	/**
	 * return the next available vertex id.
	 * @return
	 */
	private static int getNextID() {
		LAST_ID++;
		return LAST_ID;
	}

	/**
	 * return a topological order on the graph's vertices.
	 * @param graph
	 * @return list of nodes.
	 */
	private static List<SeqVertex> getTopologicalOrder(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph) {

		My_DFS dfs = new My_DFS(graph);
		dfs.runDFS();
		Map<SeqVertex,Number> finished = dfs.getFinishing();
		SeqVertexFinishTimeComparator finishingTimeComparator = new SeqVertexFinishTimeComparator();
		debugMes("getTopologicalOrder(), Vertex count: " + graph.getVertexCount(), 18);


		PriorityQueue<SeqVertex> fQueue = new PriorityQueue<SeqVertex>(graph.getVertexCount(),finishingTimeComparator  );

		for (SeqVertex v : finished.keySet())
		{
			fQueue.add(v);
		}
		List<SeqVertex> order = new ArrayList<SeqVertex>();
		while (!fQueue.isEmpty())
		{
			order.add(fQueue.poll());
		}
		return order;
	}



	/**
	 * Go over each sub component of the given graph, and calc the following:
	 * total coverage (sum of weights)
	 * average coverage
	 * number of paths
	 * @param graph
	 */
	private static void calcSubComponentsStats(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph) {

		Set<Set<SeqVertex>> comps = divideIntoComponents(graph);
		int numComp = comps.size();
		for (Set<SeqVertex> comp : comps)
		{
			//now we have one comp in hand
			Vector<Double> allW = new Vector<Double>();
			int compID = -1;
			for (SeqVertex v : comp)
			{
				if (compID==-1)
					compID = v.getID();

				allW.addAll(0, v.getWeights());
				for (SimpleEdge outE : graph.getOutEdges(v))
				{
					allW.add(0, outE.getWeight());
				}
			}
			SeqVertex v1 = getSeqVertex(graph, compID);
			if (allW.size()==0 || (comp.size()==1 && v1.getName().length()<MIN_OUTPUT_SEQ))
			{
				//this is a single node with a single letter
				debugMes("removing component with node "+compID+" which has only one node with short seq "+v1.getName(),20);
				graph.removeVertex(v1);
				numComp = numComp-1;
				continue;

			}

			int t=0;
			for (Double w: allW)
				t+=w;

			int avgCov = t/allW.size();
			debugMes("SubComp: "+compID+" has "+ comp.size() +" nodes; total coverage: "+t+" average: "+avgCov,20);

			if (avgCov<COMP_AVG_COV_THR)
			{
				debugMes("removing component with node "+compID+" which has only average coverage of "+
						avgCov+ " < "+COMP_AVG_COV_THR,20);
				for (SeqVertex v : comp)
					graph.removeVertex(v);
				numComp = numComp-1;
			}
		}
		debugMes("number of good components: "+numComp,10);
	}

	/**
	 * divide the graph into its components
	 * @param graph
	 * @return set of components
	 */
	private static Set<Set<SeqVertex>> divideIntoComponents(DirectedSparseGraph<SeqVertex, SimpleEdge> graph) 
	{

		WeakComponentClusterer<SeqVertex, SimpleEdge> compClus = new WeakComponentClusterer<SeqVertex, SimpleEdge>();
		Set<Set<SeqVertex>> comps = compClus.transform(graph);
		return comps;

	}

	/**
	 * connect the source node to each node with indegree=0,
	 * connect each node with outdegree=0 to the target node 
	 * Also add reads from the root to each of the nodes, and from the ends too.
	 * @param graph
	 * @param comp the current component
	 * @param combinedReadHash 
	 */
	private static void addSandT(DirectedSparseGraph<SeqVertex, SimpleEdge> graph, Set<SeqVertex> comp, HashMap<Integer,HashMap<PairPath,Integer>> combinedReadHash)
	{
		//		debugMes("=================\nADDING S AND T\n=================",10);

		graph.addVertex(ROOT);
		graph.addVertex(T_VERTEX);
		SimpleEdge e=null;
		//		for (SeqVertex v : graph.getVertices())
		for (SeqVertex v : comp)
		{
			if (graph.inDegree(v)==0 && !v.equals(ROOT) && !v.equals(T_VERTEX)) // connect S to this vertex
			{
				double w = v.getFirstWeight();
				if (w==-1) // single letter node?
				{
					debugMes("got a single letter node here.. "+v,20);
					w = 1;
				}
				e = new SimpleEdge(w);
				graph.addEdge(e, ROOT, v);

				debugMes("Adding edge from S to "+v,20);

				for (SeqVertex v2 : graph.getSuccessors(v))
				{
					PairPath pathD = new PairPath();
					pathD.addToPath1(ROOT.getID());
					pathD.addToPath1(v.getID());
					pathD.addToPath1(v2.getID());
					if (!combinedReadHash.containsKey(ROOT.getID()))
						combinedReadHash.put(ROOT.getID(), new HashMap<PairPath,Integer>());
					combinedReadHash.get(ROOT.getID()).put(pathD, MIN_READ_SUPPORT_THR);

				}				
			}

			if (graph.outDegree(v)==0 && !v.equals(T_VERTEX) && !v.equals(ROOT)) // connect this vertex to T
			{
				double w = v.getLastWeight();
				if (w==-1)
					w=1;
				e = new SimpleEdge(w);
				graph.addEdge(e, v, T_VERTEX);
				debugMes("Adding edge from "+v+" to T",20);


				for (SeqVertex v2 : graph.getPredecessors(v))
				{
					PairPath pathD = new PairPath();
					pathD.addToPath1(v2.getID());
					pathD.addToPath1(v.getID());
					pathD.addToPath1(T_VERTEX.getID());
					if (!combinedReadHash.containsKey(v2.getID()))
						combinedReadHash.put(v2.getID(), new HashMap<PairPath,Integer>());
					combinedReadHash.get(v2.getID()).put(pathD, MIN_READ_SUPPORT_THR);


				}
			}
		}
	}

	/**
	 * given the graph, remove all edges of S and T
	 * @param graph
	 */
	private static void removeAllEdgesOfSandT(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph) {
		Set<SimpleEdge> removeEdges = new HashSet<SimpleEdge>();
		if (graph.containsVertex(ROOT))
			for (SimpleEdge e : graph.getOutEdges(ROOT))
				removeEdges.add(e);
		if (graph.containsVertex(T_VERTEX))
			for (SimpleEdge e : graph.getInEdges(T_VERTEX))
				removeEdges.add(e);

		for (SimpleEdge re : removeEdges)
			graph.removeEdge(re);

	}


	//	/**
	//	 * Given the graph, and the reads, solve simple loops (self and of length 2)
	//	 * @param graph
	//	 * @param comp current component
	//	 * @param combinedReadHash all mapped reads
	//	 * @return
	//	 */
	//	private static HashMap<Integer,Integer> dealWithSimpleLoops_old(
	//			DirectedSparseGraph<SeqVertex, SimpleEdge> graph, 
	//			Set<SeqVertex> comp, HashMap<Integer,HashMap<PairPath,Integer>> combinedReadHash) {
	//
	//		HashMap<Integer,Integer> res = new HashMap<Integer,Integer>(); 
	//		DijkstraShortestPath<SeqVertex, SimpleEdge> dp = new DijkstraShortestPath<SeqVertex, SimpleEdge>(graph);
	//		Set<SeqVertex> dontCheckVers = new HashSet<SeqVertex>(); 
	//
	//		Set<SeqVertex> selfLoops = new HashSet<SeqVertex>();
	//		HashMap<SeqVertex,SeqVertex> doubleLoops = new HashMap<SeqVertex,SeqVertex>();
	//
	//		Set<SeqVertex> newVers = new HashSet<SeqVertex>();
	//		Set<SimpleEdge> removeE = new HashSet<SimpleEdge>();
	//		//		for (SeqVertex v : graph.getVertices())
	//		for (SeqVertex v : comp)
	//
	//		{
	//
	//			for (SeqVertex v2 : graph.getSuccessors(v))
	//			{
	//				if (!dontCheckVers.contains(v2) && dp.getDistance(v2, v)!=null)
	//				{
	//
	//					if (v.equals(v2)) // self loop
	//					{
	//						selfLoops.add(v);
	//						dontCheckVers.add(v);
	//
	//					}else if (dp.getDistance(v2, v).intValue()==1) // length 2 loop
	//					{
	//						doubleLoops.put(v, v2);
	//						dontCheckVers.add(v);
	//						dontCheckVers.add(v2);
	//
	//					} else // longer than 2
	//					{
	//
	//						List<SimpleEdge> path = dp.getPath(v2, v);
	//						List<Integer> pathIDs = new ArrayList<Integer>();
	//						dontCheckVers.add(v);
	//
	//						pathIDs.add(v.getID());
	//						pathIDs.add(v2.getID());
	//						for (SimpleEdge e : path)
	//						{
	//							dontCheckVers.add(graph.getDest(e));
	//							pathIDs.add(graph.getDest(e).getID());
	//						}
	//						//find the weakest edge and remove it.
	//						SimpleEdge edgeToRemove = graph.findEdge(v, v2);
	//						for (SimpleEdge e : path)
	//							if (e.getWeight()<edgeToRemove.getWeight())
	//								edgeToRemove = e;
	//
	//						debugMes("to break the loop of "+pathIDs +" we're cutting the edge "
	//								+graph.getSource(edgeToRemove).getID()+"->"+graph.getDest(edgeToRemove).getID(),10);
	//						removeE.add(edgeToRemove);
	//
	//					}
	//				}
	//			}
	//		}
	//		for (SimpleEdge edgeToRemove : removeE)
	//			graph.removeEdge(edgeToRemove);
	//
	//		for (SeqVertex v : selfLoops)
	//		{
	//			dealWithSelfLoops(graph,v,combinedReadHash,newVers);
	//		}
	//
	//		for (SeqVertex v : doubleLoops.keySet())
	//		{
	//			dealWithDoubleLoops(graph,v,doubleLoops.get(v),combinedReadHash,newVers);
	//		}
	//		//		}
	//
	//
	//		for (SeqVertex nv : newVers)
	//			comp.add(nv);
	//		return res;
	//	}
	//
	//	

	/**
	 * Given the graph, and the reads, solve simple loops (self and of length 2)
	 * @param graph
	 * @param comp current component
	 * @param combinedReadHash all mapped reads
	 * @return true if changed
	 */
	private static boolean dealWithLoops(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph, 
			Set<SeqVertex> comp, HashMap<Integer,HashMap<PairPath,Integer>> combinedReadHash) {

		boolean res = false;
		DijkstraShortestPath<SeqVertex, SimpleEdge> dp = new DijkstraShortestPath<SeqVertex, SimpleEdge>(graph);
		Set<Set<SimpleEdge>> curLoops = new HashSet<Set<SimpleEdge>>();

		// find all loops in the graph by seeing if, given edge v->v2, there is a path from v2 back to v
		for (SeqVertex v : comp)
		{
			for (SeqVertex v2 : graph.getSuccessors(v))
			{
				if (dp.getDistance(v2, v)!=null) // there is a connection between v->v2->... ->v
				{
					//path has all edges from v to itself thru v2
					List<SimpleEdge> loopPath = dp.getPath(v2, v);
					loopPath.add(0, graph.findEdge(v, v2));
					List<Integer> pathIDs = new ArrayList<Integer>();
					for (SimpleEdge e : loopPath)
						pathIDs.add(graph.getDest(e).getID());

					Set<SimpleEdge> loopPath_set = new HashSet<SimpleEdge>(loopPath);
					//add to curLoops
					//					debugMes("curLoops = "+curLoops,15);
					if (!curLoops.contains(loopPath_set))
					{
						curLoops.add(loopPath_set);
						debugMes("adding the loop path "+pathIDs+" to the curLoops",15);
					}else
					{
						debugMes("not adding the loop path "+pathIDs+" to the curLoops",15);
					}
				}
			}
		}

		if (curLoops.isEmpty())
			return res;


		// process found loops

		Set<SeqVertex> newVers = new HashSet<SeqVertex>();

		Set<SimpleEdge> allRelevantEdges = new HashSet<SimpleEdge>();
		for (Set<SimpleEdge> loopPath_set : curLoops)
			for (SimpleEdge e : loopPath_set)
			{
				e.increaseNumOfLoopsBy1();
				allRelevantEdges.add(e);
			}



		// look for self or double loops
		Set<Set<SimpleEdge>> removeFromCurLoops = new HashSet<Set<SimpleEdge>>();
		for (Set<SimpleEdge> loopPath_set : curLoops)
		{
			if (loopPath_set.size()==1) { // self loop
				for (SimpleEdge eSelf : loopPath_set)
				{
					if (eSelf.getNumOfLoopsInvolved()==1) // appears only in this loop
					{
						debugMes("Loops: processing self-loop", 15);
						assert(graph.getDest(eSelf).equals(graph.getSource(eSelf)));
						eSelf.decreaseNumOfLoopsBy1();
						dealWithSelfLoops(graph,graph.getDest(eSelf),combinedReadHash,newVers);
						removeFromCurLoops.add(loopPath_set);
						res = true;
					}
				}
			} else if (loopPath_set.size()==2) { //double loop



				boolean doubleUnique = true;
				SeqVertex dL_v1 = null, dL_v2 = null;
				for (SimpleEdge eDoub : loopPath_set)
				{
					doubleUnique = doubleUnique && eDoub.getNumOfLoopsInvolved()==1; // appears only in this loop
					if (dL_v1==null)
					{
						dL_v1 = graph.getSource(eDoub);
						dL_v2 = graph.getDest(eDoub);
					}
				}
				if (doubleUnique)
				{
					debugMes("Loops: processing doubleUnique", 15);
					for (SimpleEdge eDoub : loopPath_set)
						eDoub.decreaseNumOfLoopsBy1();

					dealWithDoubleLoops(graph,dL_v1,dL_v2,combinedReadHash,newVers);
					removeFromCurLoops.add(loopPath_set);
					res = true;
				}

			}
		}

		for (Set<SimpleEdge> loopPath_remove : removeFromCurLoops){
			curLoops.remove(loopPath_remove);
			for (SimpleEdge e : loopPath_remove){
				e.decreaseNumOfLoopsBy1();
			}
		}

		//go over all relevant edges, and re-examine if to keep them in the "problematic" set of edges that belong to loops.
		ArrayList<SimpleEdge> removeEdges = new ArrayList<SimpleEdge>();
		for (SimpleEdge e : allRelevantEdges){
			if (graph.getSource(e)==null || graph.getDest(e)==null || e.getNumOfLoopsInvolved()==0)
				removeEdges .add(e);		
		}

		for (SimpleEdge e : removeEdges)
			allRelevantEdges.remove(e);

		for (SeqVertex nv : newVers)
			comp.add(nv);

		if (!allRelevantEdges.isEmpty()){
			Comparator<Object> numLoopsComparator = new numLoopsEdgeComparator();
			PriorityQueue<SimpleEdge> edgesQ = new PriorityQueue<SimpleEdge>(allRelevantEdges.size(),numLoopsComparator   );
			edgesQ.addAll(allRelevantEdges);

			//FIXME - add some single and double loop handling !!

			//while there are still loops
			// find the next edge that can be removed to reduce the number of loops
			// updated queue: remove all edges, and update their loop content
			SimpleEdge nextEtoRemove;
			while (!curLoops.isEmpty())
			{
				nextEtoRemove = edgesQ.poll();
				debugMes("removing the edge "+graph.getSource(nextEtoRemove).getID()+"->"+graph.getDest(nextEtoRemove).getID()+" that appears in "+nextEtoRemove.getNumOfLoopsInvolved()+" loops",15);

				// remove the loops that have this edge from curLoops
				Set<Set<SimpleEdge>> removeLoops = new HashSet<Set<SimpleEdge>>();
				for (Set<SimpleEdge> loopPath_set : curLoops)
					if (loopPath_set.contains(nextEtoRemove))
					{
						debugMes("the loop "+ loopPath_set+" is now solved",15);
						removeLoops.add(loopPath_set);

						// update the number of loops involved in each edge
						for (SimpleEdge e : loopPath_set)
							e.decreaseNumOfLoopsBy1();
					}
				for (Set<SimpleEdge> loopPath_set : removeLoops)
					curLoops.remove(loopPath_set);

				//update the queue. remove all, and insert again if numLoops>0.
				SimpleEdge[] relEdges = (SimpleEdge[]) edgesQ.toArray(new SimpleEdge[0]);
				edgesQ.clear();
				for (SimpleEdge otherE : relEdges)
					if (otherE.getNumOfLoopsInvolved()>0)
						edgesQ.add(otherE);

				// remove this edge
				graph.removeEdge(nextEtoRemove);
				res = true;
			}
		}
		return res;


	}

	/**
	 * given the graph and the node with the self loop,
	 * find the reads that support this loop, and multiply this vertex as many times as needed, and then remap these reads.
	 * @param graph
	 * @param v
	 * @param combinedReadHash
	 * @param newVers 
	 */
	private static void dealWithSelfLoops(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph, SeqVertex v,
			HashMap<Integer, HashMap<PairPath, Integer>> combinedReadHash, Set<SeqVertex> newVers) {


		int vid = v.getID();
		int maxNumOfOccurrences = 0;

		HashMap<PairPath, Integer> relaventReads = new HashMap<PairPath, Integer>();
		for (Integer startV : combinedReadHash.keySet())
		{
			for (PairPath path: combinedReadHash.get(startV).keySet())
			{
				int numOcc = path.numOccurrences(vid);
				if (numOcc>0)
				{					
					Integer count = combinedReadHash.get(startV).get(path);
					if (count == null)
						debugMes("stop here",10);
					relaventReads.put(path,count);
				}

				if ( numOcc> maxNumOfOccurrences) //this read includes this vertex
				{
					debugMes("the read "+path+" includes the vertex "+vid+" "+numOcc+" times",19);
					maxNumOfOccurrences = numOcc;
				}
			}
		}

		// remove the self loop
		SimpleEdge removeE = graph.findEdge(v, v);
		double oldW = removeE.getWeight();
		List<Integer> newVerIDs = new ArrayList<Integer>();
		newVerIDs.add(vid);

		graph.removeEdge(removeE);
		debugMes("removing the edge between "+ v +" and itself",20);
		// multiply this node maxNumOfOccurrences times
		int upID = vid;
		int downID = -1;
		ArrayList<SimpleEdge> removeEdges = new ArrayList<SimpleEdge>();
		for (int i=2; i<=maxNumOfOccurrences; i++)
		{
			if (downID!=-1)
				upID = downID;

			downID = getNextID();
			newVerIDs.add(downID);

			SeqVertex newV = new SeqVertex(downID, v);
			debugMes("adding the new vertex "+newV.getID(),20);

			newV.setOrigButterflyID(v.getID());
			graph.addVertex(newV);
			SeqVertex upV = getSeqVertex(graph, upID);

			newVers.add(newV);


			debugMes("adding an edge between "+upID+" and "+newV.getID(),20);
			graph.addEdge(new SimpleEdge(oldW), upV, newV);

		}
		// moved to the end of loop added in the new loop opening process - Feb 2013
		SeqVertex newV = getSeqVertex(graph, downID);
		for (SeqVertex vOut : graph.getSuccessors(v))
		{
			if (!newVerIDs.contains(vOut.getID())){
				debugMes("adding an edge between "+newV.getID()+" and "+vOut.getID(),0);
				SimpleEdge e = graph.findEdge(v, vOut);
				graph.addEdge(new SimpleEdge(e), newV, vOut);
				debugMes("removing the edge between "+ v.getID() +" and "+vOut.getID(),20);
				removeEdges.add(e);
			}
		}

		//remove edges:
		for (SimpleEdge re : removeEdges){
			graph.removeEdge(re);

		}

		List<Integer> loopVIDs = new ArrayList<Integer>();
		loopVIDs.add(vid);
		List<List<Integer>> newVerIDsList = new ArrayList<List<Integer>>();
		newVerIDsList.add(newVerIDs);
		updateReadsAfterLoopOpening(combinedReadHash,relaventReads,loopVIDs,newVerIDsList,maxNumOfOccurrences);

	}

	/**
	 * Given the combinedReadHash, and the relevant reads, update their paths.
	 * @param combinedReadHash
	 * @param relevantReads
	 * @param loopVIDs
	 * @param newVerIDs
	 * @param maxNumOfOccurrences
	 */
	private static void updateReadsAfterLoopOpening(
			HashMap<Integer, HashMap<PairPath, Integer>> combinedReadHash,
			HashMap<PairPath, Integer> relevantReads, List<Integer> loopVIDs,
			List<List<Integer>> newVerIDs, int maxNumOfOccurrences) {

		for (PairPath path: relevantReads.keySet())
		{
			Integer origFirstV = path.getFirstID();
			Integer origCount = combinedReadHash.get(origFirstV).get(path);
			List<Integer> newPath1 = new ArrayList<Integer>(path.getPath1());
			List<Integer> newPath2 = new ArrayList<Integer>(path.getPath2());

			if (loopVIDs.size()==1)
			{
				updatePathOfSelfLoop(newPath1,loopVIDs,newVerIDs.get(0),maxNumOfOccurrences);
				updatePathOfSelfLoop(newPath2,loopVIDs,newVerIDs.get(0),maxNumOfOccurrences);
			} else
			{
				updatePathOfDoubleLoop(newPath1,loopVIDs,newVerIDs.get(0),newVerIDs.get(1),maxNumOfOccurrences);
				updatePathOfDoubleLoop(newPath2,loopVIDs,newVerIDs.get(0),newVerIDs.get(1),maxNumOfOccurrences);
			}
			// path hasn't changed
			if (path.getPath1().equals(newPath1) && path.getPath2().equals(newPath2))
				continue;

			// both are empty now
			if (newPath1.isEmpty() && newPath2.isEmpty())
				combinedReadHash.get(origFirstV).remove(path);

			// at least one has changed
			PairPath newKey;
			if (newPath1.isEmpty())	
				newKey = new PairPath(newPath2,new ArrayList<Integer>());
			else if (newPath2.isEmpty())
				newKey = new PairPath(newPath1,new ArrayList<Integer>());
			else
				newKey = new PairPath(newPath1,newPath2);


			Integer firstV = newKey.getFirstID();
			if (!combinedReadHash.containsKey(firstV))
				combinedReadHash.put(firstV, new HashMap<PairPath, Integer>());

			if (combinedReadHash.get(firstV).containsKey(newKey))
			{
				Integer oldCount = combinedReadHash.get(firstV).get(newKey);
				combinedReadHash.get(firstV).put(newKey,oldCount+origCount);
				combinedReadHash.get(firstV).remove(path);
			}else
			{
				combinedReadHash.get(firstV).put(newKey,origCount);
			}
		}

	}



	/**
	 * given a path, the vid of the self loop, and the new vertices' id, update the path
	 * if the path starts of ends inside the loop, trim this part of the path, and leave only the outside info.
	 * @param path
	 * @param vid
	 * @param newVerIDs
	 * @return
	 */
	private static void updatePathOfSelfLoop(List<Integer> path, List<Integer> loopVIDs,
			List<Integer> newVerIDs,int maxNumOcc) {
		int vid = loopVIDs.get(0).intValue();
		String origPath = ""+path;
		Set<Integer> loopVs = new HashSet<Integer>();
		loopVs.add(vid);
		boolean changed = false;
		if (path.contains(vid))
		{
			if (path.get(0).intValue()==vid)
			{ //starts inside the loop
				changed = true;
				if (path.get(path.size()-1).intValue()==vid)
					//starts and ends inside the loop
					if (path.size()==maxNumOcc)
					{
						for (int i=1 ; i<=path.size()-1 ; i++)
							path.set(i,newVerIDs.get(i));

						changed = true;
					}else
						path.clear();
				else
					updatePathToRemoveLoopNodes(path,loopVs);
			}else
			{ // starts and ends outside the loop
				for (int i=1 ; i<=path.size()-1 ; i++)
				{
					if (path.get(i).intValue()==vid) // i>0
					{
						int j = newVerIDs.indexOf(path.get(i-1));
						if (j>=0)
						{
							path.set(i, newVerIDs.get(j+1));
							changed = true;
						}
					}

				}
			}
		}
		if (changed)
			debugMes("path changed from "+origPath+" to "+path,20);
	}

	/**
	 * remove the integers that are inside the loop
	 * @param path
	 * @param loopVs
	 */
	private static void updatePathToRemoveLoopNodes(List<Integer> path,
			Set<Integer> loopVs) {
		List<Integer> indicesToRemove = new ArrayList<Integer>();
		for (int i=0 ; i<=path.size()-1 ; i++)
			if (loopVs.contains(path.get(i)))
				indicesToRemove.add(i);
		Collections.sort(indicesToRemove);
		Collections.reverse(indicesToRemove);
		for (Integer i : indicesToRemove)
			path.remove(i.intValue());
	}



	/**
	 * given the graph and the node with the self loop,
	 * find the reads that support this loop, and multiply this vertex as many times as needed
	 * @param graph
	 * @param t_v1
	 * @param t_v2
	 * @param combinedReadHash
	 * @param newVers 
	 */
	private static void dealWithDoubleLoops(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph, SeqVertex t_v1,
			SeqVertex t_v2,
			HashMap<Integer, HashMap<PairPath, Integer>> combinedReadHash, Set<SeqVertex> newVers) 
	{
		int v1_id=-1; // the one inside the regular flow
		int v2_id=-1; // the addition

		//CONTINUE HERE!

		if (graph.getSuccessorCount(t_v1)>1)
		{
			v1_id = t_v1.getID();
			v2_id = t_v2.getID();
		} else if (graph.getSuccessorCount(t_v2)>1)
		{
			v1_id = t_v2.getID();
			v2_id = t_v1.getID();
		}

		if (v1_id==-1)
		{		
			//FIXME - decide randomly, doesn't solve the loops right. (ignores input edges to t_v1)
			v1_id = t_v1.getID();
			v2_id = t_v2.getID();
		}


		HashMap<PairPath, Integer> relaventReads = new HashMap<PairPath, Integer>();

		int maxNumOfOccurrences = 0;
		for (Integer startV : combinedReadHash.keySet())
		{
			for (PairPath path: combinedReadHash.get(startV).keySet())
			{
				int numOcc2 = path.numOccurrences(v2_id);
				if (numOcc2>0)
				{
					Integer count = combinedReadHash.get(startV).get(path);
					if (count == null)
					{
						count = combinedReadHash.get(startV).get(path);

						for (PairPath path2: combinedReadHash.get(startV).keySet())
						{
							debugMes("path: "+path2+" with hashCode "+path2.hashCode(),15);
							debugMes("path: "+path2+" with value "+combinedReadHash.get(startV).get(path2),15);
						}
					}
					relaventReads.put(path,count);

					if ( numOcc2> maxNumOfOccurrences) //this read includes this vertex
					{
						debugMes("MAX:the read "+path+" includes the vertex "+v1_id+" "+numOcc2+" times",15);
						maxNumOfOccurrences = numOcc2;
					}

				}
			}
		}
		// the loop is v1 (v2,v1)*
		//if we count how many v2 appears, then the number appearances of v1 is one more.
		SeqVertex v1 = getSeqVertex(graph, v1_id);
		SeqVertex v2 = getSeqVertex(graph, v2_id);
		List<Integer> newVerIDs_v1 = new ArrayList<Integer>();
		List<Integer> newVerIDs_v2 = new ArrayList<Integer>();
		newVerIDs_v1.add(v1_id);
		newVerIDs_v2.add(v2_id);

		// remove the self loop
		SimpleEdge removeE = graph.findEdge(v2, v1);
		double oldW = removeE.getWeight();
		double oldW2 = graph.findEdge(v1, v2).getWeight();

		graph.removeEdge(removeE);
		debugMes("removing the edge between "+ v2_id +" and "+v1_id,20);
		// multiply this node maxNumOfOccurrences times

		int up_v1 = v1_id;
		if (maxNumOfOccurrences>=1) //multiply only v1
		{
			SeqVertex newV = new SeqVertex(getNextID(), v1);
			newV.setOrigButterflyID(v1_id);
			graph.addVertex(newV);
			newVerIDs_v1.add(newV.getID());

			newVers.add(newV);

			//			// removed in the new loop opening process - Feb 2013
			//			for (SeqVertex vOut : graph.getSuccessors(v1))
			//			{
			//				if (!vOut.equals(v2))
			//				{
			//					debugMes("adding an edge between "+newV.getID()+" and "+vOut.getID(),20);
			//					graph.addEdge(new SimpleEdge(graph.findEdge(v1, vOut)), newV, vOut);
			//				}
			//			}
			debugMes("adding an edge between "+v2_id+" and "+newV.getID(),20); 
			graph.addEdge(new SimpleEdge(oldW), v2, newV);

			up_v1 = newV.getID();
		}

		int up_v2 = v2_id;
		int down_v1 = -1;
		int down_v2 = -1;

		ArrayList<SimpleEdge> removeEdges = new ArrayList<SimpleEdge>();
		for (int i=2; i<=maxNumOfOccurrences; i++) // multiple v2-v1
		{
			if (down_v1!=-1)
			{
				up_v1 = down_v1;
			}

			down_v1 = getNextID();
			down_v2 = getNextID();
			newVerIDs_v1.add(down_v1);
			newVerIDs_v2.add(down_v2);

			SeqVertex newV1 = new SeqVertex(down_v1, v1);
			newV1.setOrigButterflyID(v1_id);
			SeqVertex newV2 = new SeqVertex(down_v2, v2);
			newV2.setOrigButterflyID(v2_id);
			//debugMes("i="+i+"("+maxNumOfOccurrences+") adding newV1:"+newV1+" newV2:"+newV2,10);
			graph.addVertex(newV1);
			graph.addVertex(newV2);

			newVers.add(newV1);
			newVers.add(newV2);

			SeqVertex upV = getSeqVertex(graph, up_v1);
			SeqVertex orig_upV = getSeqVertex(graph, v1_id);

			if (i==maxNumOfOccurrences){// this cirteria added in the new loop opening process - Feb 2013
				for (SeqVertex vOut : graph.getSuccessors(orig_upV))
				{
					if (!newVerIDs_v2.contains(vOut.getID()))
					{
						debugMes("adding an edge between "+newV1.getID()+" and "+vOut.getID(),20);
						SimpleEdge e = graph.findEdge(orig_upV, vOut);
						graph.addEdge(new SimpleEdge(e), newV1, vOut);
						debugMes("removing an edge between "+orig_upV.getID()+" and "+vOut.getID(),20); 
						removeEdges.add(e);
					}
				}
			}
			//			// removed in the new loop opening process - Feb 2013
			//			for (SeqVertex vIn : graph.getPredecessors(getSeqVertex(graph, up_v2)))
			//			{
			//				if (!newVerIDs_v1.contains(vIn.getID()))
			//				{
			//					debugMes("$$adding an edge between "+vIn.getID()+" and "+down_v2,10);
			//					graph.addEdge(new SimpleEdge(graph.findEdge(vIn, getSeqVertex(graph, up_v2))), vIn, newV2);
			//				}
			//			}
			debugMes("adding an edge between "+up_v1+" and "+newV2.getID(),20);
			graph.addEdge(new SimpleEdge(oldW), upV, newV2);

			debugMes("adding an edge between "+newV2.getID()+" and "+newV1.getID(),20);
			graph.addEdge(new SimpleEdge(oldW2), newV2, newV1);


		}

		List<Integer> loopVIDs = new ArrayList<Integer>();
		loopVIDs.add(v1_id);
		loopVIDs.add(v2_id);
		List<List<Integer>> newVerIDs = new ArrayList<List<Integer>>();
		newVerIDs.add(newVerIDs_v1);
		newVerIDs.add(newVerIDs_v2);

		//remove edges:
		for (SimpleEdge re : removeEdges){
			graph.removeEdge(re);

		}
		updateReadsAfterLoopOpening(combinedReadHash,relaventReads,loopVIDs,newVerIDs,maxNumOfOccurrences);


	}



	/**
	 * given a path, the vid of the loop vertices, and the new vertices' id, update the path
	 * if the path starts of ends inside the loop, trim this part of the path, and leave only the outside info.
	 * @param path
	 * @param loopVIDs
	 * @param newVerIDsV1
	 * @param newVerIDsV2
	 * @param maxNumOfOccurrences
	 */
	private static void updatePathOfDoubleLoop(List<Integer> path, List<Integer> loopVIDs,
			List<Integer> newVerIDsV1, List<Integer> newVerIDsV2, int maxNumOfOccurrences) {
		int v1_id = loopVIDs.get(0).intValue();
		int v2_id = loopVIDs.get(1).intValue();

		if (path.isEmpty())
			return;
		boolean changed = false;

		String origPath = ""+path;

		Set<Integer> loopVs = new HashSet<Integer>();
		loopVs.add(v1_id);
		loopVs.add(v2_id);

		int firstV = path.get(0).intValue();
		int lastV = path.get(path.size()-1).intValue();
		if (path.contains(v2_id))
		{
			if (firstV==v1_id || firstV==v2_id)
			{
				changed = true;
				if (firstV==v1_id || lastV==v2_id)

					// the whole path is inside the loop
					if ((firstV==v1_id && lastV==v1_id && path.size()==maxNumOfOccurrences*2+1) ||
							(firstV==v2_id && lastV==v2_id && path.size()==maxNumOfOccurrences*2-1) || 
							(firstV==v1_id && lastV==v2_id && path.size()==maxNumOfOccurrences*2) || 
							(firstV==v2_id && lastV==v1_id && path.size()==maxNumOfOccurrences*2) ) // all path is in the loop, but there is only one new path that matches
					{
						changed = updateSinglePathWithDoubleLoopNodes(path,v1_id,v2_id,newVerIDsV1,newVerIDsV2);
					}else
						path.clear();
				else
				{// only the start is inside the loop
					updatePathToRemoveLoopNodes(path, loopVs); 
					changed = true;
				}
			}else
			{ // start and ends outside the loop
				changed = updateSinglePathWithDoubleLoopNodes(path,v1_id,v2_id,newVerIDsV1,newVerIDsV2);
			}
		}
		if (changed)
			debugMes("path changed from "+origPath+" to "+path,20);
	}





	/**
	 * given this path, and the loop info, update the path to its single option.
	 * @param path
	 * @param v1_id
	 * @param v2_id
	 * @param newVerIDsV1
	 * @param newVerIDsV2
	 * @return
	 */
	private static boolean updateSinglePathWithDoubleLoopNodes(
			List<Integer> path, int v1_id, int v2_id, List<Integer> newVerIDsV1,
			List<Integer> newVerIDsV2) {
		boolean changed = false;
		for (int i=1 ; i<=path.size()-1 ; i++)
		{
			if (path.get(i).intValue()==v1_id) 
			{
				int j = newVerIDsV2.indexOf(path.get(i-1));
				if (j>=0)
				{
					path.set(i, newVerIDsV1.get(j+1));
					changed = true;
				}
			} else if (path.get(i).intValue()==v2_id) 
			{
				int j = newVerIDsV1.indexOf(path.get(i-1));
				if (j>=1)
				{
					path.set(i, newVerIDsV2.get(j));
					changed = true;
				}
			}
		}
		return changed;
	}

	/**
	 * print out the given error message, only if DEBUG=true
	 * @param mes Message
	 */
	private static void debugMes(String mes, int verbosityLevel)
	{
		//TODO: use general logging that can be leveraged across all classes.

		if (DEBUG && verbosityLevel<=VERBOSE_LEVEL)
		{
			if (USE_STDERR)
				System.err.println(mes);
			else if (LOG_STDERR)
				ERR_STREAM.println(mes);
		}

	}



	/**
	 * combine prefixes:
	 * calc for each v it's "depth" in terms of length of strings (from them on)
	 * draw all v's with the same depth
	 * sort on their set of parents
	 * draw all v's with same depth and same set of parents
	 * find subsets of those with same prefix
	 * create new node with prefix, connect accordingly.
	 * add the rest (those that removed the prefix) back into queue, with new depths
	 * @param graph
	 * @return
	 */
	private static boolean compactPrefixesBottomUp(DirectedSparseGraph<SeqVertex, SimpleEdge> graph)
	{

		setVerticesDepths(graph);
		Comparator<Object> depthComparator = new SeqVertexDepthComparator();
		PriorityQueue<SeqVertex> dQueue = new PriorityQueue<SeqVertex>(graph.getVertexCount(),depthComparator );
		for (SeqVertex v : graph.getVertices())
			dQueue.add(v);

		int curD;
		SeqVertex v;
		ListComparator listComp = new ListComparator();
		TreeMap<List<SeqVertex>,Collection<SeqVertex>> curParents = new TreeMap<List<SeqVertex>,Collection<SeqVertex>>(listComp );
		boolean changed = false;
		for (curD=0 ; curD<=MAX_DEPTH ; curD++) 
		{
			curParents.clear();

			while (!dQueue.isEmpty() && dQueue.peek().getDepth()==curD)
			{
				v = dQueue.poll();
				if (!graph.containsVertex(v))
					continue;

				List<SeqVertex> parents = getSortedParentList(graph,v); 
				if (!parents.isEmpty())
				{
					debugMes("curParents: "+curParents,20);
					if (!curParents.containsKey(parents))
					{
						debugMes(parents +" doesn't appear in curParents",20);
						curParents.put(parents,new HashSet<SeqVertex>());
					}
					debugMes("adding "+ v +" to "+curParents.get(parents),20);
					curParents.get(parents).add(v);
				}	

			}
			//look for subsets with identical children
			for (Collection<SeqVertex> parents : curParents.keySet())
			{
				// this collection has vertices with the same children
				Collection<SeqVertex> candidateNodes = curParents.get(parents);

				if (candidateNodes.size()==1)
					continue;

				// look for shared suffix
				boolean updateQueue = false;
				Collection<SeqVertex> updatedNodes = new HashSet<SeqVertex>();
				changed = compactPrefixRecursive(graph,candidateNodes,updatedNodes);

				for (SeqVertex ver : updatedNodes)
				{
					if (ver.getName().isEmpty())
					{
						debugMes("Need to update the queue. candidateNodes = "+updatedNodes,20);
						updateQueue = true;
					}
				}
				if (updateQueue)
				{
					for (SeqVertex ver : updatedNodes)
					{
						if (!ver.getName().isEmpty())
						{
							dQueue.add(ver);
							debugMes("adding "+ver+" to the queue, with depth "+ver.getDepth(),20);
						}
					}
				}
			}

		}
		// run compactGraph after the suffices are done. 
		if (compactLinearPaths(graph))
			changed = true;
		return changed;
	}

	/**
	 * Given the graph, go over all vertices, and calculate their depth, as in distance from the roots 
	 * (maximal or minimal??) = doesn't matter as long as it's consistent. I chose maximal. 
	 * @param graph
	 */
	private static void setVerticesDepths(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph) {
		List<SeqVertex> topBottom = getTopologicalOrder(graph);

		for (SeqVertex v : topBottom)
		{
			if (graph.inDegree(v)==0)
			{
				v.setDepth(0);
			}
			else
			{
				int d = -1;
				for (SeqVertex tv : graph.getPredecessors(v))
				{
					if (tv.getDepth() + tv.getName().length() >d)
						d=tv.getDepth() + tv.getName().length();
				}
				v.setDepth(d);
				if (d>MAX_DEPTH)
					MAX_DEPTH = d;
			}
		}

	}

	/**
	 * Given the graph, and the vertex v, return a sorted list of its parents
	 * @param graph
	 * @param v
	 * @return
	 */
	private static List<SeqVertex> getSortedParentList(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph, SeqVertex v) {
		List<SeqVertex> res = new ArrayList<SeqVertex>(graph.getPredecessors(v));
		SeqComparator verComp = new SeqComparator();
		Collections.sort(res, verComp);

		return res;
	}

	/**
	 * Given the graph, and the candidate nodes, look for shared prefixes of a single letter, 
	 * and move on.
	 * @param graph
	 * @param candidateNodes
	 * @param updateQueue 
	 */
	private static boolean compactPrefixRecursive(
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph,
			Collection<SeqVertex> 	candidateNodes, Collection<SeqVertex> updatedNodes) {
		boolean changed = false;
		for (String l : LETTERS)
		{
			Collection<SeqVertex> vWithL = getVerticesWithFirstLetter(candidateNodes,l);
			if (vWithL.size()<=1)
				continue;


			// if there is a letter that has more than one vertex, create a new vertex with this letter
			changed = true;
			SeqVertex newV = new SeqVertex(getNextID(), l);
			newV.addIDsAsFirstPrevIDs(vWithL,LAST_REAL_ID);
			Collection<SeqVertex> new_vWithL = new HashSet<SeqVertex>(); 
			Vector<SimpleEdge> removeEdges = new Vector<SimpleEdge>();

			for (SeqVertex v_withL : vWithL)
			{
				if (!graph.containsVertex(v_withL))
					continue;

				// create a new vertex with the first prevID as id
				SeqVertex newReplaceV_withL;
				if (!v_withL.getPrevVerIDs().isEmpty() && v_withL.getPrevVerIDs().firstElement().size()>1)
				{
					newReplaceV_withL = new SeqVertex(getNextID(), v_withL.getName());
					newReplaceV_withL.copyTheRest(v_withL);
				}else
					newReplaceV_withL = v_withL.generateNewVerWithFirstIDasID(); 
				// move all edges from and to the orig, to the new
				if (!newReplaceV_withL.equals(v_withL)) // they will be equal if the v_withL has no prevIDs, and only his original id
				{
					for (SimpleEdge e : graph.getOutEdges(v_withL))
					{
						removeEdges.add(e);
						graph.addEdge(new SimpleEdge(e.getWeight()), newReplaceV_withL, graph.getDest(e));
					}
					for (SimpleEdge e : graph.getInEdges(v_withL))
					{
						removeEdges.add(e);
						graph.addEdge(new SimpleEdge(e.getWeight()), graph.getSource(e), newReplaceV_withL);
					}
				}
				//replace it's location within vWithL
				new_vWithL.add(newReplaceV_withL);
			}

			for (SimpleEdge re : removeEdges)
			{
				debugMes("removing edge "+re+" between "+graph.getSource(re)+" and "+graph.getDest(re),20);
				graph.removeEdge(re);
			}

			for (SeqVertex rv : vWithL)
			{
				if (!new_vWithL.contains(rv))
				{
					debugMes("removing vertex (because new_vWithL doesn't contain it) "+rv,20);
					graph.removeVertex(rv);
				}
			}

			vWithL = new_vWithL;
			graph.addVertex(newV);
			debugMes("pulled the first letter from all vertices in "+vWithL+" to the new vertex "+newV,20);
			Vector<SeqVertex> removeVertices = new Vector<SeqVertex>();
			for (SeqVertex v1 : vWithL)
			{

				//				if (removeVertices.contains(v1) || !graph.containsVertex(v1))
				if (v1.isToBeDeleted() || !graph.containsVertex(v1))
					continue;
				removeEdges.clear();
				v1.increaseDepthByOne();

				for (SimpleEdge edgeToRemove : graph.getInEdges(v1))
				{
					double w2 = edgeToRemove.getWeight();
					SimpleEdge newE2 = null;
					SeqVertex v3 = graph.getSource(edgeToRemove);

					if (graph.findEdge(v3,newV)==null)
					{
						newE2 = new SimpleEdge(w2);
						graph.addEdge(newE2, v3,newV); 
						debugMes("adding edge "+newE2+" between "+v3+" and "+newV,20);
					}else
					{
						newE2 = graph.findEdge(v3,newV);
						if (w2>newE2.getWeight())
						{
							//FIXME ?? do we want to add up the weights?
							debugMes("setting edge "+newE2+"'s weight from "+newE2.getWeight()+" to "+w2,20); 
							newE2.setWeight(w2);
						}
					}

					removeEdges.add(edgeToRemove);
					debugMes("removed edge "+edgeToRemove+" between "+graph.getSource(edgeToRemove)+" and "+graph.getDest(edgeToRemove),20);

				}
				// handle outgoing edges (newE1)
				SeqVertex newV1; // needed only if this node is less than K in length
				if  (v1.getName().length()==1)
				{
					v1.removeFirstLetter();

					//go over all edges going out of v1, and move them to exit newV
					for (SeqVertex v0 : graph.getSuccessors(v1))
					{
						double w = graph.findEdge(v1,v0).getWeight();
						graph.addEdge(new SimpleEdge(w), newV,v0);
						debugMes("adding edge "+w+" between "+newV+" and "+v0,20);
					}
					debugMes("vertex "+v1+" is going to be removed",20);

					removeVertices.add(v1);
					v1.setToBeDeleted(true);

				}else if (v1.getName().length()<=K && graph.outDegree(v1)==0) 
				{
					v1.removeFirstLetter();
					Collection<SeqVertex> upV = graph.getPredecessors(v1);

					if (v1.getID()<=LAST_REAL_ID)
					{
						newV1 = new SeqVertex(getNextID(),v1.getName());
						graph.addVertex(newV1);
						removeVertices.add(v1);
						v1.setToBeDeleted(true);
					} else
						newV1 = v1;

					//go over all edges going into v1, and move them to exit newV
					if (upV.size()==1)
					{
						for (SeqVertex upV1 : upV)
						{
							SimpleEdge oldE = graph.findEdge(upV1, v1);
							double w = oldE.getWeight();
							graph.addEdge(new SimpleEdge(w), newV,newV1);
							removeEdges.add(oldE);
							debugMes("adding edge "+w+" between "+newV+" and "+newV1,20);
							debugMes("removing edge "+w+" between "+upV1+" and "+v1,20);
							graph.addEdge(new SimpleEdge(1), v1, newV1);
						}
					}
				}else
				{
					double w = v1.removeFirstLetter();
					SimpleEdge newE1 = new SimpleEdge(w);
					graph.addEdge(newE1, newV,v1);
					debugMes("adding edge "+newE1+" between "+newV+" and "+v1,20);

				}

				for (SimpleEdge re : removeEdges)
				{
					graph.removeEdge(re);
				}
			}
			//try this out
			updatedNodes.clear();
			Set<SeqVertex> toAddTo_vWithL = new HashSet<SeqVertex>();
			int curDepth = -1;
			// use this curDepth to decide if to add the children or not.
			if (!removeVertices.isEmpty())
				for (SeqVertex ver : vWithL)
					//					if (!removeVertices.contains(ver))
					if (!ver.isToBeDeleted())
						curDepth = ver.getDepth();
			for (SeqVertex rv : removeVertices)
			{
				for (SeqVertex vChild : graph.getSuccessors(newV))
					if (!vWithL.contains(vChild) && vChild.getDepth()==curDepth)
						toAddTo_vWithL.add(vChild);

				graph.removeVertex(rv);
				debugMes("removed vertex "+rv,20);
				if (vWithL.contains(rv))
					vWithL.remove(rv);
				if (candidateNodes.contains(rv))
					candidateNodes.remove(rv);
			}

			for (SeqVertex vToAdd : toAddTo_vWithL)
				vWithL.add(vToAdd);

			for (SeqVertex vToAdd : vWithL)
			{
				updatedNodes.add(vToAdd);
			}


			if (vWithL.size()>1)
				compactPrefixRecursive(graph, vWithL,updatedNodes);

		}

		return changed;
	}

	/**
	 * Given the set of nodes, return a set of nodes that has the given letter l as a final letter
	 * @param candidateNodes
	 * @param l
	 * @return
	 */
	private static Collection<SeqVertex> getVerticesWithFirstLetter(
			Collection<SeqVertex> candidateNodes, String l) {
		Collection<SeqVertex> res = new HashSet<SeqVertex>();
		for (SeqVertex v : candidateNodes)
		{
			if (v.getName().startsWith(l))
				res.add(v);
		}
		return res;
	}

	// retrieve path list from first unshared node till the end (minus the final vertex)
	public static List<Integer> get_unshared_path_terminus(List<Integer> path_to_search, List<Integer> path_to_index) {

		debugMes("Path to search: " + path_to_search, 19);
		debugMes("Path to index: " + path_to_index, 19);

		Hashtable<Integer,Boolean> path_index = new Hashtable<Integer,Boolean>();
		for (Integer x : path_to_index) {
			path_index.put(x, new Boolean(true));
		}

		int unshared_path_pos = path_to_search.size(); // init to Infinity in essence, never reach this.
		for (int i = 0; i <= path_to_search.size()-2; i++) {
			if (! path_index.containsKey( path_to_search.get(i) ) ) {
				unshared_path_pos = i;
				break;
			}
		}

		List<Integer> unique_terminal_path = new Vector<Integer>();
		for (int i = unshared_path_pos; i <= path_to_search.size() -2; i++) {
			unique_terminal_path.add(path_to_search.get(i));
		}

		debugMes("Unique terminal path: " + unique_terminal_path, 19);

		return(unique_terminal_path);
	}	

	// see if any node is shared between the lists
	public static boolean paths_have_node_in_common (List<Integer> pathA, List<Integer> pathB) {


		Hashtable<Integer,Boolean> path_index = new Hashtable<Integer,Boolean>();
		for (int i = 0; i < pathA.size() - 1; i++) {
			path_index.put(pathA.get(i), new Boolean(true));
		}

		for (int i = 0; i < pathB.size() -1; i++) {
			if (path_index.containsKey( pathB.get(i))) {
				return(true);
			}
		}

		return(false);
	}	


	// see if any node other than the very last one is shared between the lists
	public static boolean paths_have_any_node_in_common (List<Integer> pathA, List<Integer> pathB, boolean include_sinks) {


		Hashtable<Integer,Boolean> path_index = new Hashtable<Integer,Boolean>();
		for (int i = 0; i < pathA.size() - 1; i++) {
			Integer node = pathA.get(i);
			if ( (! include_sinks) && node < 0) {
				continue; // sink node
			}
			path_index.put(node, new Boolean(true));
		}

		for (int i = 0; i < pathB.size() -1; i++) {
			Integer node = pathB.get(i);
			if (path_index.containsKey( node)) {
				// debugMes("Found node: " + node + " in common between paths: " + pathA + " and " + pathB, 10);
				return(true);
			}
		}

		return(false);
	}	



	public static String getPathMappingAsciiIllustration (
			final List<Integer> finalPath, 
			List<PairPath> readPaths,
			HashMap<PairPath,Pair<Integer>> readsPerPathCount
			) {

		String ascii_illustration = "";

		for (int i = 0; i < finalPath.size(); i++) {
			ascii_illustration += "=";
		}
		ascii_illustration += "    PATH: " + finalPath + "\n";


		Collections.sort(readPaths, new Comparator<PairPath>() { // sort illustration by first node position in path
			public int compare(PairPath a, PairPath b) {
				Integer b_index = finalPath.indexOf(b.getFirstID());
				Integer a_index = finalPath.indexOf(a.getFirstID());
				return(a_index - b_index);
			}

		});

		for (PairPath read : readPaths) {

			char chars[] = new char[finalPath.size()];
			for (int i = 0; i < chars.length; i++) {
				chars[i] = ' ';
			}

			for (List<Integer> readPath : read.get_paths()) {
				for (Integer vertex_id : readPath) {
					int index = finalPath.indexOf(vertex_id);
					if (index >= 0) {
						chars[index] = '=';
					}
				}
			}
			for (int i = 0; i < chars.length; i++) {
				ascii_illustration += chars[i];
			}

			int support_count = readsPerPathCount.get(read).getSecond();

			ascii_illustration += "    Read: " + read.get_paths() + "   count: " + support_count + "\n";

		}


		return(ascii_illustration);

	}


	public static int count_pairpath_support(List<Integer> path, HashMap<List<Integer>, HashMap<PairPath, Integer>> PathReads) {

		HashMap<PairPath,Integer> pairPath_map = PathReads.get(path);

		int sum_reads = 0;

		for (PairPath p : pairPath_map.keySet()) {

			int read_count = pairPath_map.get(p);
			sum_reads += read_count;

		}

		return(sum_reads);	
	}


	public static HashMap<Integer, List<List<Integer>>> extractTripletsFromReads(HashMap<Integer,HashMap<PairPath,Integer>> combinedReadHash) {


		HashMap<Integer, List<List<Integer>>> tripletMapper = new HashMap<Integer, List<List<Integer>>>();

		for (Integer vertex_id : combinedReadHash.keySet()) {

			HashMap<PairPath,Integer> pp_hmap = combinedReadHash.get(vertex_id);

			for (PairPath pp : pp_hmap.keySet()) {

				List<List<Integer>> paths = pp.get_paths();
				for (List<Integer> read_path : paths) {
					if (read_path.size() < 3) {
						continue;
					}
					// iterate through triplets
					for (int i = 1; i < read_path.size()-1; i++) {
						Integer central_id = read_path.get(i);
						Integer left_id = read_path.get(i-1);
						Integer right_id = read_path.get(i+1);

						List<Integer> adjacency_path = new ArrayList<Integer>();
						adjacency_path.add(left_id);
						adjacency_path.add(central_id);
						adjacency_path.add(right_id);

						if (tripletMapper.containsKey(central_id)) {
							List<List<Integer>> triplet_list = tripletMapper.get(central_id);
							if (! triplet_list.contains(adjacency_path)) {
								triplet_list.add(adjacency_path);
								debugMes("Adding triplet adjacency_path to central node: " + central_id + " => " + adjacency_path, 10);
							}
							else {
								debugMes("triplet adjacency_path of node: " + central_id + " => " + adjacency_path + " already captured.", 10);
							}
						}
						else {
							List<List<Integer>> triplet_list = new ArrayList<List<Integer>>();
							triplet_list.add(adjacency_path);
							tripletMapper.put(central_id, triplet_list);
							debugMes("Setting initial triplet adjacency_path for central node: " + central_id + " => " + adjacency_path, 10);

						}



					}


				}

			}

		}

		return(tripletMapper);

	}

	public static Boolean tripletSupported(List<List<Integer>> triplet_list, List<Integer> triplet) {

		for (List<Integer> t_list : triplet_list) {
			debugMes("Checking triplet list: " + t_list + " comparing to query triplet: " + triplet, 10);
			if (t_list.get(0).equals(triplet.get(0))
					&& 
					t_list.get(1).equals(triplet.get(1))
					&&
					t_list.get(2).equals(triplet.get(2))
					) {

				return(true);
			}	
		}
		return(false);


	}


	public static List<Integer> ensure_path_has_sinks(List<Integer> path) {

		List<Integer> new_path = new ArrayList<Integer>(path);

		if (new_path.get(0) != -1) {
			new_path.add(0, -1);
		}
		if (new_path.get(new_path.size()-1) != -2) {
			new_path.add(-2);
		}

		return(new_path);


	}


	public static HashMap<List<Integer>, Pair<Integer>> reduce_cdhit_like (
			HashMap<List<Integer>, Pair<Integer>> FinalPaths_all, 
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph,
			HashMap<List<Integer>,HashMap<PairPath,Integer>> PathReads) {



		////////////////////////////////////////////////////////////////////////////
		debugMes("\n\n****  CD-HIT style path collapsing at end of run.\n\n", 15);


		Vector<FinalPaths> path_vec = new Vector<FinalPaths>();

		DecimalFormat df = new DecimalFormat("#.#");
		for (List<Integer> path : FinalPaths_all.keySet())
		{
			String seq = getPathSeq(graph,path);

			FinalPaths f = new FinalPaths(path, seq);
			path_vec.add(f);
		}


		MAX_SEQ_LEN_DP_ALIGN  = ALL_VS_ALL_MAX_DP_LEN; // temporarily replace

		Collections.sort(path_vec); // sort paths by length of sequence descendingly

		// examine sequence CD-HIT -style, remove those that lack sufficient variation
		HashMap<FinalPaths,Boolean> filtered = new HashMap<FinalPaths,Boolean>();


		List<List<Integer>> removeSimilarPaths =  new ArrayList<List<Integer>>(); 

		for (int i = 0; i < path_vec.size()-1; i++) {

			if (filtered.containsKey(path_vec.get(i))) {
				// path filtered, cannot use it as evidence for filtering smaller sequences.
				continue;
			}

			List<Integer> path_i = path_vec.get(i).path;

			List<Integer> path_i_w_sinks = ensure_path_has_sinks(path_i);

			for (int j = i + 1; j < path_vec.size(); j++) {


				if (filtered.containsKey(path_vec.get(j))) {
					// path filtered, cannot use it as evidence for filtering smaller sequences.
					continue;
				}

				List<Integer> path_j = path_vec.get(j).path;
				List<Integer> path_j_w_sinks = ensure_path_has_sinks(path_j);

				String seq_i = path_vec.get(i).sequence;
				String seq_j = path_vec.get(j).sequence;

				int index1 = seq_i.length()-1;
				int index2 = seq_j.length()-1;
				debugMes("ALL-VS-ALL: (" + i + "," + j + " of " + path_vec.size() + ") checking for similarity the two paths: "+path_i+ 
						"(len="+seq_i.length()+");"+path_j+"(len="+seq_j.length()+")",10);




				if (finalSeqsAreTooSimilar(seq_i, seq_j)) {


					debugMes("\n\n*** REDUCE: they are TOO SIMILAR! ***\n\n",10);	
					//remove the shorter path


					int rIndex = removeTheLesserSupportedPath(seq_i, seq_j, path_i, path_j, removeSimilarPaths, PathReads);

					//int rIndex = removeTheShorterPath(path1S,path2S,path1,path2,removeSimilarPaths,PathReads);
					if (rIndex == 1) {// the first path was removed
						filtered.put(path_vec.get(i), true);
						debugMes("\tRemoving (" + i + ") seq in pair", 18);
					}
					else {
						filtered.put(path_vec.get(j), true);
						debugMes("\tRemoving (" + j + ") second seq in pair", 18);
					}

				}
			}
		}


		for (FinalPaths path2Remove : filtered.keySet())
		{
			debugMes("REDUCE-STAGE: The final path "+path2Remove+" was removed because it was too close to another path",10);
			FinalPaths_all.remove(path2Remove.path);

		}

		ALL_VS_ALL_MAX_DP_LEN = MAX_SEQ_LEN_DP_ALIGN; // back to original setting

		return(FinalPaths_all);

	}

	public static HashMap<List<Integer>, Pair<Integer>> remove_identical_subseqs (
			HashMap<List<Integer>, Pair<Integer>> FinalPaths_all, 
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph,
			HashMap<List<Integer>,HashMap<PairPath,Integer>> PathReads) {



		////////////////////////////////////////////////////////////////////////////
		debugMes("\n\n****  Removing identical subsequences.\n\n", 15);


		Vector<FinalPaths> path_vec = new Vector<FinalPaths>();

		DecimalFormat df = new DecimalFormat("#.#");
		for (List<Integer> path : FinalPaths_all.keySet())
		{
			String seq = getPathSeq(graph,path);

			FinalPaths f = new FinalPaths(path, seq);
			path_vec.add(f);
		}


		Collections.sort(path_vec); // sort paths by length of sequence descendingly

		// examine sequence CD-HIT -style, remove those that lack sufficient variation
		HashMap<FinalPaths,Boolean> filtered = new HashMap<FinalPaths,Boolean>();


		List<List<Integer>> removeSimilarPaths =  new ArrayList<List<Integer>>(); 

		for (int i = 0; i < path_vec.size()-1; i++) {

			if (filtered.containsKey(path_vec.get(i))) {
				// path filtered, cannot use it as evidence for filtering smaller sequences.
				continue;
			}

			List<Integer> path_i = path_vec.get(i).path;

			List<Integer> path_i_w_sinks = ensure_path_has_sinks(path_i);

			for (int j = i + 1; j < path_vec.size(); j++) {


				if (filtered.containsKey(path_vec.get(j))) {
					// path filtered, cannot use it as evidence for filtering smaller sequences.
					continue;
				}

				List<Integer> path_j = path_vec.get(j).path;
				List<Integer> path_j_w_sinks = ensure_path_has_sinks(path_j);

				String seq_i = path_vec.get(i).sequence;
				String seq_j = path_vec.get(j).sequence;

				int index1 = seq_i.length()-1;
				int index2 = seq_j.length()-1;
				debugMes("ALL-VS-ALL: (" + i + "," + j + " of " + path_vec.size() + ") checking for identical subseqs between the two paths: "+path_i+ 
						"(len="+seq_i.length()+");"+path_j+"(len="+seq_j.length()+")",10);


				if (seq_i.indexOf(seq_j) >= 0) { 
					filtered.put(path_vec.get(j), true);
					debugMes("\t** Removing (" + j + ") seq in pair, contains " + i, 15);
				}
				else if (seq_j.indexOf(seq_i) >= 0) {
					filtered.put(path_vec.get(i), true);
					debugMes("\t** Removing (" + i + ") seq in pair, contains " + j, 15);
				}

			}

		}


		for (FinalPaths path2Remove : filtered.keySet())
		{
			debugMes("REDUCE-STAGE: The final path "+path2Remove+" was removed because it was too close to another path",10);
			FinalPaths_all.remove(path2Remove.path);

		}


		return(FinalPaths_all);

	}


	public static Boolean finalSeqsAreTooSimilar (String seq_i, String seq_j) {

		// note, to check for perfectly identical sequence clusters, could run cd-hit like so:
		// cd-hit-est -o cdhit -c 1 -i comp.allProbPaths.fasta -p 1 -d 0 -b 1


		if ( (seq_i.length() > MAX_SEQ_LEN_DP_ALIGN && seq_j.length() > MAX_SEQ_LEN_DP_ALIGN) 
				||
				seq_i.length() > 100000   // problems can arise in the alignment code if either seq is longer
				||
				seq_j.length() > 100000) {


			// zipper:  Just get rid of those that are truly nearly identical.

			AlignmentStats stats = ZipperAlignment.doZipperAlignment("A", seq_i, "B", seq_j);
			int mismatches = stats.mismatches;
			debugMes("-zipper reports: " + mismatches + " mismatches between seqs.", 18);
			if (mismatches <= 2)
				return(true);
			else
				return(false);
		}	
		else {

			Alignment alignment;

			if (SMITH_WATERMAN_ALIGN_FLAG) {

				debugMes("-running Smith-Waterman alignment of path sequences", 15);
				alignment = NWalign.run_SW_alignment("A", seq_i, "B", seq_j, 4, -5, 10, 1);


			}
			else {
				// Needleman Wunsch Global Alignment is default
				debugMes("-running Needleman-Wunsch alignment of path sequences", 15);
				alignment = NWalign.run_NW_alignment("A", seq_i, "B", seq_j, 4, -5, 10, 1);   //NW locks up or takes too long with very long sequences (eg. 40kb align to 6kb)


			}


			int max_diffs_in_window = AlignmentStats.get_max_diffs_in_window(alignment, DIFFS_WINDOW_SIZE);
			debugMes (new jaligner.formats.Pair().format(alignment), 10);
			debugMes("Max diffs found in alignment window: " + max_diffs_in_window, 10);


			if (max_diffs_in_window <= MAX_FINAL_DIFFS_IN_WINDOW) {
				return (true);
			}


		}

		return(false);

	}			

	private static String get_pathName_string (List<Integer> path,
			DirectedSparseGraph<SeqVertex, SimpleEdge> graph) {





		/*
		int startI = 0, endI = path.size(); 
		if (path.get(0)== ROOT.getID())
			startI++;
		if (path.get(path.size()-1)== T_VERTEX.getID())
			endI--;

		String pathName;
		if (MISO_OUTPUT) {
			pathName = "[";
			int iSeqL=0,j=0;
			for (int vi=startI; vi<endI; vi++){
				iSeqL = getSeqVertex(graph, path.get(vi)).getName().length();
				pathName = pathName + path.get(vi)+":"+j+"-"+(j+iSeqL-1);
				if (vi<endI-1)
					pathName = pathName.concat(" ");
				j+=iSeqL;
			}
			pathName = pathName +"]";
		} else
			pathName = ""+path.subList(startI, endI);

		 */

		int startI = 0, endI = path.size(); 
		if (path.get(0)== ROOT.getID())
			startI++;
		if (path.get(path.size()-1)== T_VERTEX.getID())
			endI--;


		String pathName,degenString="";
		SeqVertex v;
		if (MISO_OUTPUT) {

			DecimalFormat f0 = new DecimalFormat("#");

			pathName = "[";
			int iSeqL=0,j=0;
			for (int vi=startI; vi<endI; vi++){
				v = getSeqVertex(graph, path.get(vi));
				iSeqL = v.getName().length();
				pathName = pathName + v.getOrigButterflyID()+":"+j+"-"+(j+iSeqL-1);
				if (vi<endI-1)
					pathName = pathName.concat(" ");
				if (v.getDegenerativeFreq().size()>0)
				{
					for (int di=0; di<v.getDegenerativeFreq().size(); di++)
					{
						degenString = degenString + "{("+(j+v.getDegenerativeLocations().elementAt(di))+")";
						degenString = degenString + v.getDegenerativeLetters().elementAt(di).elementAt(0)+":"+
								f0.format(v.getDegenerativeFreq().elementAt(di).elementAt(0))+" ";
						degenString = degenString + v.getDegenerativeLetters().elementAt(di).elementAt(1)+":"+
								f0.format(v.getDegenerativeFreq().elementAt(di).elementAt(1)) +"}";
					}
				}
				j+=iSeqL;

			}
			pathName = pathName +"]";
		} else
			pathName = ""+path.subList(startI, endI);


		if (USE_DEGENERATE_CODE) {
			pathName = pathName + " SNPs="+degenString;
		}




		return(pathName);
	}

}

// End TransAssembly.java
//
//		



