import java.util.ArrayList;
import java.util.List;

/**
 * a class representing a paired end read
 * If the read is not paired end, only the first path will be used.
 * @author morani
 *
 */
public class PairPath {

	private List<List<Integer>> _paths;
	private boolean _isCircular;
	
	
	public PairPath(List<Integer> path1,List<Integer> path2) {
		_paths = new ArrayList<List<Integer>>();
		_paths.add(path1);
		_paths.add(path2);
		_isCircular = false;
	}

	public PairPath(List<Integer> path1) {
		_paths = new ArrayList<List<Integer>>();
		_paths.add(path1);
		_paths.add(new ArrayList<Integer>()); //path2
		_isCircular = false;
	}
	public PairPath() {
		_paths = new ArrayList<List<Integer>>();
		_paths.add(new ArrayList<Integer>()); //path1
		_paths.add(new ArrayList<Integer>()); //path2
		_isCircular = false;
	}


	@Override
	public String toString() {
		String res = "PairPath [_paths=" + _paths + "]";
		if (_isCircular)
			res = res+" (C)";
		return res;
			
	}

	@Override
	public int hashCode() {
		final int prime = 31;
		int result = 1;
		result = prime * result + ((_paths == null) ? 0 : _paths.hashCode());
		return result;
	}

	@Override
	public boolean equals(Object obj) {
		if (this == obj)
			return true;
		if (obj == null)
			return false;
		if (getClass() != obj.getClass())
			return false;
		PairPath other = (PairPath) obj;
		if (_paths == null) {
			if (other._paths != null)
				return false;
		} else if (!_paths.equals(other._paths))
			return false;
		return true;
	}

	/**
	 * @return the _isCircular
	 */
	public boolean isCircular() {
		return _isCircular;
	}

	/**
	 * @param isCircular the _isCircular to set
	 */
	public void setCircular() {
		_isCircular = true;
	}

	public List<List<Integer>> get_paths() {
		return _paths;
	}

	public List<Integer> getPath1() {
		return _paths.get(0);
	}
	
	public List<Integer> getPath2() {
		return _paths.get(1);
	}

	public void setPath1(List<Integer> path1) {
		_paths.get(0).addAll(path1);
	}
	
	public void setPath2(List<Integer> path2) {
		_paths.get(1).addAll(path2);
	}

	public Integer getFirstID(){
		return (isEmpty())? -10 : _paths.get(0).get(0);
	}

	public boolean isEmpty() {
		return _paths.get(0).isEmpty();
	}

	public void addToPath1(List<Integer> path) {
		_paths.get(0).addAll(path);		
	}

	public void addToPath1(Integer id) {
		_paths.get(0).add(id);
		
	}

	public boolean containsID(Integer i) {
		return ( (!_paths.get(0).isEmpty() && _paths.get(0).contains(i)) || 
				(!_paths.get(1).isEmpty() && _paths.get(1).contains(i)));
	}


	/**
	 * return the max number of occurrences of vid in EITHER path1 or path2
	 * @param vid
	 * @return
	 */
	public int numOccurrences(int vid) {
		
		return Math.max(numOccurrencesSinglePath(0,vid),numOccurrencesSinglePath(1,vid));
		
	}

	
	private int numOccurrencesSinglePath(int i, int vid) {
		int res = 0;
		if (!_paths.get(i).isEmpty())
		{
			for (Integer v :  _paths.get(i))
			{
				if (v.intValue() == vid)
					res++;
			}
		}

		return res;
	}

	public Integer getLastID() {
		return (!hasSecondPath())? getLastID_path1() : _paths.get(1).get(_paths.get(1).size()-1);
	}

	public Integer getFirstID_path2() {
		return (hasSecondPath())? _paths.get(1).get(0) : -10;
	}

	public Integer getLastID_path1() {
		return (isEmpty())? -10 : _paths.get(0).get(_paths.get(0).size()-1);
	}

	public boolean hasSecondPath() {
		return !_paths.get(1).isEmpty();
	}

	public void movePath2To1() {
		_paths.get(0).clear();
		for (Integer v :  _paths.get(1))
			_paths.get(0).add(v);
		
		getPath2().clear();
		
	}
	
	public static Integer getFirstCommonID (List<Integer> pathA, List<Integer> pathB) {
		
		for (Integer node_id : pathA) {
			if (pathB.contains(node_id)) {
				return(node_id);
			}
		}
		
		return(null); // nothing in common.
	}
	
	public  boolean haveAnyNodeInCommon(List<Integer> path) {
		
		// sink nodes don't count.
		
		List<Integer> firstPath = trimSinkNodes(this.getPath1());
		
		for (Integer node_id: firstPath) {
			if (path.contains(node_id)) {
				return(true);
			}
		}
		
		// try path 2
		if (this.hasSecondPath()) {
			List<Integer> secondPath = trimSinkNodes(this.getPath2());
			for (Integer node_id : secondPath) {
				if (path.contains(node_id)) {
					return(true);
				}
			}
		
		}
		
		
		return(false); // nothing shared.
	}
	
	// find first element in param path that exists in path1
	public Integer getFirstCommonID_path1 (List<Integer> path) {
		
		for (int i = 0; i < path.size(); i++) {
			if (getPath1().contains(path.get(i))) {
				return(getPath1().indexOf(path.get(i)));
			}
		}
		
		return(-1);
		
	}
	
	// find first element in param path that exists in path2
	public Integer getFirstCommonID_path2 (List<Integer> path) {
		
		if (! this.hasSecondPath()) {
			return(-1);
		}
	
		for (int i = 0; i < path.size(); i++) {
			if (getPath2().contains(path.get(i))) {
				return(getPath2().indexOf(path.get(i)));
			}
		}
		
		return(-1);
		
	}

	public boolean isCompatible (List<Integer> path) {
		
		// if the first node of path1 or path2 anchors into path, then the remaining nodes must also anchor up to the end of the path, whichever ends first.
		
		//   Compatibility can look like any of these:
		//     read:     ---
		//     path:   ---------
		// or
		//     read:   -----------
		//     path:      ---
		// or 
		//     read:   -------
		//     path:       --------
		// or
		//     read:        --------
		//     path:   --------
		
		path = trimSinkNodes(path);
		List<Integer> firstPath = trimSinkNodes(this.getPath1());
	
		if (! haveAnyNodeInCommon(path)) {
			return(false);
		}
		
		Integer firstCommonNode = getFirstCommonID(path, firstPath);
		
		if (firstCommonNode != null) {
			
			int i = path.indexOf(firstCommonNode);
			int j = firstPath.indexOf(firstCommonNode);
			
			//System.err.println("i: " + i + ", j: " + j);
			
			if (! (i == 0 || j == 0)) {
				return(false); // one should begin at the first node in region of overlap (see illustrations above)
			}
			
			// check overlap
			for (; i < path.size() && j < firstPath.size(); i++, j++) {
				int i_val = path.get(i);
				int j_val = firstPath.get(j);
				if (i_val != j_val) {
					return(false);
				}
			}
			
		}
		
		// walk the second path, if one exists.
		if (hasSecondPath()) {
			List<Integer> secondPath = trimSinkNodes(this.getPath2());
			Integer commonNode = getFirstCommonID(path, secondPath);
			if (commonNode != null) {
				int i = path.indexOf(commonNode);
				int j = secondPath.indexOf(commonNode);
				
				if (! (i == 0 || j == 0) ) {
					return(false);  // same reasoning as above.
				}
				
				for (; i < path.size() && j < secondPath.size(); i++, j++) {
					int i_val = path.get(i);
					int j_val = secondPath.get(j);
					if (i_val != j_val) {
						return(false);
					}
				}
			}
			
		}
		
		// if got this far, we know first path or second path contains nodes in common across overlap
		
		
		return(true);
	}
		
	// see if read is fully contained within the path and compatible with it.
	public boolean isCompatibleAndContained (List<Integer> path) {

		
		//   Compatibility and containment looks like this
		//     read:     ---
		//     path:   ---------
		
		
		path = trimSinkNodes(path);
		List<Integer> firstPath = trimSinkNodes(this.getPath1());
	
		if (! haveAnyNodeInCommon(path)) {
			return(false);
		}
		
		Integer firstCommonNode = getFirstCommonID(path, firstPath);
		
		if (firstCommonNode != null) {
			
			int i = path.indexOf(firstCommonNode);
			int j = firstPath.indexOf(firstCommonNode);
			
			//System.err.println("i: " + i + ", j: " + j);
			
			if (j != 0) {
				return(false); // must start at beginning of read.
			}
			
			// check overlap
			for (; i < path.size() && j < firstPath.size(); i++, j++) {
				int i_val = path.get(i);
				int j_val = firstPath.get(j);
				if (i_val != j_val) {
					return(false);
				}
			}
			if (j != firstPath.size()) {
				// didn't contain full read
				return(false);
			}
			
		}
		
		// walk the second path, if one exists.
		if (hasSecondPath()) {
			List<Integer> secondPath = trimSinkNodes(this.getPath2());
			Integer commonNode = getFirstCommonID(path, secondPath);
			if (commonNode != null) {
				int i = path.indexOf(commonNode);
				int j = secondPath.indexOf(commonNode);
				
				if (j != 0)  {
					return(false);  // same reasoning as above.
				}
				
				for (; i < path.size() && j < secondPath.size(); i++, j++) {
					int i_val = path.get(i);
					int j_val = secondPath.get(j);
					if (i_val != j_val) {
						return(false);
					}
				}
				if (j != secondPath.size()) {
					return(false);
				}
			}
			
		}
		
		// if got this far, we know both reads are entirely encapsulated by the path.
		
		return(true);
	}	
		
		
		
		
	
		

	// see if read is fully contained within the path and compatible with it.
	public boolean containsSubPath (List<Integer> path) {
	
		//   Compatibility and containment looks like this
		//     read:   ---------
		//     path:     ---- (1 or 2)
		
		// or  (overlap)
		//     read:    ---- (1)
		//     read:      -------- (2)
		//     path:     ----  
		
		// or  (discontiguous)
		//     read:   ---- (1)
		//     read:       ----- (2)
		//     path:     ----
		
		
		path = trimSinkNodes(path);
		List<Integer> firstPath = trimSinkNodes(this.getPath1());
	
		if (! haveAnyNodeInCommon(path)) {
			return(false);
		}
		
		Integer firstCommonNode = getFirstCommonID(path, firstPath);
		
		
		int last_index_of_path_covered = -1;
		
		if (firstCommonNode != null) {
			
			int i = path.indexOf(firstCommonNode);
			int j = firstPath.indexOf(firstCommonNode);
			
			//System.err.println("i: " + i + ", j: " + j);
			
			if (i != 0) {
				return(false); // must start at beginning of path
			}
			
			// check overlap
			for (; i < path.size() && j < firstPath.size(); i++, j++) {
				int i_val = path.get(i);
				int j_val = firstPath.get(j);
				if (i_val != j_val) {
					return(false);
				}
			}
			if (! (i == path.size() || j == firstPath.size()) ) {
				// didn't contain full subPath within range of read
				return(false);
			}
			else if (i == path.size()) {
				// got full path covered by first read
				return(true);
			}
			else {
				last_index_of_path_covered = i - 1;
			}
			
		}
		
		// walk the second path, if one exists.
		if (hasSecondPath()) {
			List<Integer> secondPath = trimSinkNodes(this.getPath2());
			Integer commonNode = getFirstCommonID(path, secondPath);
			if (commonNode != null) {
				int i = path.indexOf(commonNode);
				int j = secondPath.indexOf(commonNode);
				
				if (i > last_index_of_path_covered + 1) {
					return(false); // missing coverage of the path
				}
				
				if (i > 0 && j != 0)  {
					return(false);  // must start at second read's first index if we're already walking the path from 1st read.
				}
				
				for (; i < path.size() && j < secondPath.size(); i++, j++) {
					int i_val = path.get(i);
					int j_val = secondPath.get(j);
					if (i_val != j_val) {
						return(false);
					}
				}
				if (i == path.size()) {
					return(true); // walked rest of path.
				}
			}
			
		}
		
		// if got this far, first path didn't fully cover it and neither did second path.
		
		return(false);
		
	}
		
	
	private static List<Integer> trimSinkNodes (List<Integer> path) {
		
		path = new ArrayList<Integer>(path); // copy contents
		
		// trim sink nodes off
		if (path.get(0) < 0) {
			path.remove(0);
		}
		if (path.size() > 0 && path.get(path.size()-1) < 0) {
			path.remove(path.size()-1);
		}
		
		return(path);
	}
	
}
