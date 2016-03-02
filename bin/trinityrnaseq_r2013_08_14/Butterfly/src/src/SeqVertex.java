import java.util.Collection;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.util.Vector;

public class SeqVertex {
	protected int _id;
	protected String _name;
	protected Vector<Double> _weights;// all weights that were compacted into this vertex
	protected Vector<Vector<Integer>> _prevVerticesID;//all IDs of vertices that were merged into this one. 
//	protected int _height;
	protected int _depth;
	protected int _dfsDiscoveryTime;
	protected int _dfsFinishTime;

	protected boolean _isInCircle;
	protected boolean _toBeDeleted;
	
	protected int _origButterflyID;
	
	protected Vector<Vector<Integer>> _degenerativeFreq; //frequencies of the different nt in the degenerative representation
	protected Vector<Vector<String>> _degenerativeLetters; // the letters that matched
	protected Vector<Integer> _degenerativeLocations; // holds the location of the degenerative letters.
	
	// track nodes after instantiating for fast retrieval
	public static Map<Integer,SeqVertex> nodeTracker = new HashMap<Integer,SeqVertex>();
	
	//constructors
	/*
	 * create a vertex from a single original node
	 */
	public SeqVertex(int id, String name)
	{
		_id = id;
		_name = name;
		_weights = new Vector<Double>();
		_prevVerticesID = new Vector<Vector<Integer>>();
//		_height = 0;
		_depth = 0;
		_dfsFinishTime = -1;
		_dfsDiscoveryTime = -1;
		_isInCircle = false;
		_toBeDeleted = false;
		_origButterflyID = id;
		_degenerativeFreq = new Vector<Vector<Integer>>();
		_degenerativeLetters = new Vector<Vector<String>>();
		_degenerativeLocations = new Vector<Integer>();
		
		nodeTracker.put(id, this);
	
	}


	public SeqVertex(Integer id, String name, double wei) {
		this(id,name);
		int len = name.length();
		_weights.ensureCapacity(len);
		for (int i=0; i<len; i++)
		{
			_weights.add(i, wei);
		}

	}

	/**
	 * Create a new seqvertex, with all ids from vWithL as prevID
	 * @param nextID
	 * @param l
	 * @param origVers
	 */
	public SeqVertex(int id, String name, Collection<SeqVertex> origVers) {
		this(id,name);
		Vector<Integer> thisNewLetter = new Vector<Integer>();
		for (SeqVertex v : origVers)
		{
			Vector<Integer> vID = v.getAndRemoveLastID(); //this was for the last letter graphs
			thisNewLetter.addAll(vID);
		}
		
		_prevVerticesID.add(thisNewLetter);
	}

	/**
	 * create a new vertex, with the exact same name and weights, and only the depth is like the old one + its length
	 * @param id
	 * @param v
	 */
	public SeqVertex (int id, SeqVertex v)
	{
		this(id,v.getName());
		int len = v.getWeights().size();
		_weights.ensureCapacity(len);
		for (int i=0; i<len; i++)
			_weights.add(i, v.getWeights().get(i));
		_depth = v.getDepth()+v.getName().length();

		
		_degenerativeFreq = new Vector<Vector<Integer>>(v.getDegenerativeFreq());
		_degenerativeLetters = new Vector<Vector<String>>(v.getDegenerativeLetters());
		_degenerativeLocations = new Vector<Integer>(v.getDegenerativeLocations());
		
	}
	//Methods
	public int getID()
	{
		return _id;
	}

	/**
	 * @return the _origButterflyID
	 */
	public int getOrigButterflyID() {
		return _origButterflyID;
	}


	/**
	 * @param _origButterflyID the _origButterflyID to set
	 */
	public void setOrigButterflyID(int origButterflyID) {
		_origButterflyID = origButterflyID;
	}


	public String getName()
	{
		return _name;
	}

	private void setName(String newName)
	{
		_name = newName;
	}


//	public int getHeight()
//	{
//		return _height;
//	}
//
//	public void setHeight(int h)
//	{
//		_height = h;
//	}

	public int getDFS_FinishingTime()
	{
		return _dfsFinishTime;
	}

	public void setDFS_FinishingTime(int f)
	{
		_dfsFinishTime = f;
//		System.err.println("DFS: "+_id+" finish time "+f);
	}

	public int getDFS_DiscoveryTime() {
		return _dfsDiscoveryTime;
	}


	public void setDFS_DiscoveryTime(int dfsDiscoveryTime) {
		_dfsDiscoveryTime = dfsDiscoveryTime;
//		System.err.println("DFS: "+_id+" disc time "+dfsDiscoveryTime);

	}


	/**
	 * @return the _isInCircle
	 */
	public boolean isInCircle() {
		return _isInCircle;
	}


	/**
	 * @return the _toBeDeleted
	 */
	public boolean isToBeDeleted() {
		return _toBeDeleted;
	}


	/**
	 * @param toBeDeleted the _toBeDeleted to set
	 */
	public void setToBeDeleted(boolean toBeDeleted) {
		_toBeDeleted = toBeDeleted;
	}


	/**
	 * @param isInCircle the _isInCircle to set
	 */
	public void setInCircle(boolean isInCircle) {
		_isInCircle = isInCircle;
	}


	public String toString()
	{
		return _name+":"+getWeightAvg()+"("+_id+")";
	}

	public String toStringWeights()
	{
		return _name+":"+getWeightAvg()+_weights+" ("+_id+")";
	}

	public boolean equals(Object other)
	{
		return other!=null && _id==((SeqVertex) other).getID();
	}

	public int hashCode()
	{
		return _id;
	}

	public int getSize()
	{
		return 	_weights.size();

	}

	public Vector<Double> getWeights()
	{
		return _weights;
	}

	public int getWeightAvg()
	{
		double res = 0;
		if (_weights.size()==0)
			return -1;

		for (double t : _weights)
			res += t;
		res = res/_weights.size();

		return (int) Math.round(res);
	}

	public double getWeightSum()
	{
		double res = 0;
		if (_weights.size()==0)
			return res;

		for (double t : _weights)
			res += t;
		return res;
	}

	/*
	 * add the given vertex info into this vertex
	 * combine name and weights 
	 */
	public void concatVertex(SeqVertex vertex,Double w, int lastRealID)
	{
		int prevLen = getName().length();
		setName(getName() + vertex.getName());
		_weights.add(w);
		_weights.addAll(vertex.getWeights());
		//System.out.println(toStringWeights());
		Vector<Integer> newV = new Vector<Integer>();
		if (vertex.getID()<=lastRealID)
		{
			newV.add(vertex.getID());
			_prevVerticesID.add(newV);
		}
 		_prevVerticesID.addAll(vertex.getPrevVerIDs());
 		
 		if (vertex.getDegenerativeFreq().size()>0)
 		{
// 			System.err.println(vertex.getID()+":"+vertex.getDegenerativeFreq());
// 			System.err.println(vertex.getID()+":"+vertex.getDegenerativeLocations());
// 			System.err.println(vertex.getID()+":"+vertex.getDegenerativeLetters());
// 			System.err.println(getID()+":"+getName());
// 			System.err.println(prevLen);
 			
 			for (int i=0; i<vertex.getDegenerativeLocations().size(); i++){
 				_degenerativeLocations.add(prevLen+vertex.getDegenerativeLocations().elementAt(i));	
 			}
 			
 			_degenerativeFreq.addAll(vertex.getDegenerativeFreq());
 			_degenerativeLetters.addAll(vertex.getDegenerativeLetters());
 		}
 			
	}

	public Vector<Integer> getDegenerativeLocations() {
		return _degenerativeLocations;
	}


	public Vector<Vector<Integer>> getDegenerativeFreq() {
		return _degenerativeFreq;
	}


	public Vector<Vector<String>> getDegenerativeLetters() {
		return _degenerativeLetters;
	}


	/**
	 * Return the collection of prev IDs
	 * @return
	 */
	public Vector<Vector<Integer>> getPrevVerIDs() {

		return _prevVerticesID;
	}



	//	private static double maxVector(Vector<Double> vec)
	//	{
	//		double res = 0;
	//		for (Double t : vec)
	//			res+=t.doubleValue();
	//		res = res/vec.size();
	//		return res;
	//	}



	public boolean eladEquals(Object obj)
	{
		return super.equals(obj);
	}

	/**
	 * remove the last element of the _weights vector, and returns it 
	 * @return the last element of the _weights vector
	 */
	public double removeLastWeight() {
		if (getSize()==0)
			return -1;
		double res = _weights.lastElement();
		_weights.removeElementAt(_weights.lastIndexOf(res));
		return res;
	}


	/**
	 * get the first weight in the weights vector. if vector is empty return -1
	 * @return
	 */
	public double getFirstWeight() {
		return (_weights.size()==0)? -1 : _weights.firstElement();
	}

	/**
	 * return the lastw eight in the weights vector. if vector is empty return -1
	 * @return
	 */
	public double getLastWeight() {
		return (_weights.size()==0)? -1 : _weights.lastElement();
	}

	/**
	 * return the name of this vertex. if the name is longer than 20bp, return first and last 5bp.
	 * @return
	 */
	public String getShortSeq() {
		String res = _name;
		if (res.length()>30)
			res = res.substring(0,10)+"..."+res.substring(res.length()-10);
		res = res+":"+getWeightAvg();
		return res;
	}

	/**
	 * return the name of this vertex. if the name is longer than 20bp, return first and last 5bp. with the id
	 * @return
	 */
	public String getShortSeqWID() {
		return getShortSeq()+"("+getID()+")";
	}

	/**
	 * return the name of this vertex. 
	 * if the name is longer than 20bp, return first and last 5bp. 
	 * with the id
	 * with all previous ids
	 * @return
	 */
	public String getShortSeqWIDWprevIDs() {
		return getName()+"("+getID()+";"+getPrevVerIDs()+")";
	}

	/**
	 * like getShortSeqWID only with the full seq
	 * @return
	 */
	public String getLongtSeqWID() {
		return getName()+"("+getID()+")";
	}
	/**
	 * Remove the last letter of the vertex name, and return the corresponding weight.
	 */
	public double removeLastLetter() {
		setName(getName().substring(0, getName().length()-1));
		if (_weights.isEmpty())
			return -1;
		else
			return _weights.remove(_weights.size()-1);

	}


	/**
	 * remove and return the last id from the prevIDs
	 */
	public Vector<Integer> getAndRemoveLastID() {
		Vector<Integer> res = new Vector<Integer>();
		if (!_prevVerticesID.isEmpty())
		{
			res = _prevVerticesID.lastElement();
			_prevVerticesID.remove(_prevVerticesID.size()-1);
		}
		return res;
	}

//	/**
//	 * after extracting one letter, increase the height by one
//	 */
//	public void increaseHeightByOne() {
//		_height++;
//	}


	/**
	 * remove all the letters except for the first
	 */
	public void removeAllButFirstLetter() {
		setName(_name.substring(0,1));

	}

	public int getDepth() {
		return _depth;
	}


	public void setDepth(int depth) {
		_depth = depth;
	}


	/**
	 * after extracting one letter, increase the depth by one
	 */
	public void increaseDepthByOne() {
		_depth++;
	}


	/**
	 * Remove the first letter of the vertex name, and return the corresponding weight.
	 */
	public double removeFirstLetter() {
		setName(getName().substring(1, getName().length()));

		if (_weights.isEmpty())
			return -1;
		else
			return _weights.remove(0);


	}


	/**
	 * remove and return the first id from the prevIDs
	 */
	public Integer getAndRemoveFirstID() {
		if (_prevVerticesID.isEmpty() || _prevVerticesID.firstElement().isEmpty())
			return getID();
		if (_prevVerticesID.firstElement().size()>1)
			return -1;
		Vector<Integer> firstIDs = _prevVerticesID.firstElement();
		_prevVerticesID.remove(0);
		return firstIDs.elementAt(0);
	}


	/**
	 * create a new seqVertex, and give it the first id in this prev IDs
	 * remove the first prevIDS.
	 * @return
	 */
	public SeqVertex generateNewVerWithFirstIDasID() {
		Integer firstID = getAndRemoveFirstID(); 
		if (firstID == getID())
			return this;
		SeqVertex newV = new SeqVertex(firstID, getName());
		newV._prevVerticesID = getPrevVerIDs();
		newV._dfsFinishTime = _dfsFinishTime;
//		newV._height = _height;
		newV._depth = _depth;
		newV._weights = _weights;
		return newV;
	}

	public void copyTheRest(SeqVertex v)
	{
		_prevVerticesID = v.getPrevVerIDs();
		_dfsFinishTime = v._dfsFinishTime;
		_depth = v._depth;
		_weights = v._weights;
	
	}
	
	
	public void addIDsAsFirstPrevIDs(Collection<SeqVertex> vWithL, int lAST_REAL_ID) {
		Vector<Integer> prevIDs = new Vector<Integer>();
		for (SeqVertex v : vWithL)
		{
			int vid = v.getID();
			if (vid>=0) 
				if (vid<=lAST_REAL_ID)
					prevIDs.add(vid);
				else if (!v.getPrevVerIDs().isEmpty())
				{
					prevIDs.addAll(v.getPrevVerIDs().get(0));
					v.getPrevVerIDs().remove(0);
				}
				
		}
		
		_prevVerticesID.add(prevIDs);
		
	}

	/**
	 * add the name of v1 to this name
	 * @param v1
	 */
	public void addToName(SeqVertex v1) {
		_name = _name + v1.getName();
	}

	/**
	 * go over all the prev ids, and if you have consecutive identical entries, remove one.
	 */
	public void clearDoubleEntriesToPrevIDs() {

		Vector<Integer> removeIndices = new Vector<Integer>(); 
		for (int i = 0 ; i<=getPrevVerIDs().size()-2; i++)
		{
			Vector<Integer> vec1 = getPrevVerIDs().elementAt(i);
			Vector<Integer> vec2 = getPrevVerIDs().elementAt(i+1);
			
			if (vec1.equals(vec2))
				removeIndices.add(i);
		}
		
		Collections.reverse(removeIndices);
		
		for (int i : removeIndices)
			_prevVerticesID.removeElementAt(i);
	}


	/** 
	 * add the ver id from the vToRemove to this vertex previous ids
	 * @param vToKeep
	 * @param vToRemove 
	 */
	public void addToPrevIDs(SeqVertex vToKeep, SeqVertex vToRemove, int lastRealID) {
		if (_prevVerticesID.isEmpty())
		{
			Vector<Integer> thisV = new Vector<Integer>();
			if (vToKeep.getID()>=lastRealID)
				thisV.add(vToKeep.getID());
			if (vToRemove.getID()>=lastRealID)
				thisV.add(vToRemove.getID());
			if (!vToKeep.getPrevVerIDs().isEmpty())
				thisV.addAll(vToKeep.getPrevVerIDs().firstElement());
			if (!vToRemove.getPrevVerIDs().isEmpty())
				thisV.addAll(vToRemove.getPrevVerIDs().firstElement());
			
			_prevVerticesID.add(thisV);
		}else
		{
			assert(true);
		}
	}


	public static SeqVertex retrieveSeqVertexByID (Integer id) {
		return(nodeTracker.get(id));
		
	}

	/**
	 * given two letters and their reads, calc the frequencies
	 * @param name
	 * @param weight
	 * @param name2
	 * @param weight2
	 */
	public void setFrequencies(String n1, double w1, 
			String n2,double w2) {
//		Integer fre1 = (int)Math.round(((w1/(w1+w2))*100));
//		Integer fre2 = (int)Math.round((w2/(w1+w2)*100));
		Integer fre1 = (int)w1;
		Integer fre2 = (int)w2;

		Vector<Integer> vW = new Vector<Integer>();
		vW.add(fre1);
		vW.add(fre2);
		_degenerativeFreq.add(vW);
		Vector<String> vS = new Vector<String>();
		vS.add(n1);
		vS.add(n2);
		_degenerativeLetters.add(vS);
		_degenerativeLocations.add(0);
		System.err.println(getID()+":"+getName());
		System.err.println(getDegenerativeLocations());
		
	}




}
