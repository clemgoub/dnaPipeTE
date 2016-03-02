
public class SimpleEdge {
	public double _wei;
	public boolean _isInCircle;
	protected int _numberOfLoopsInvolved;
	
	/*
	 * ctor
	 */
	public SimpleEdge (double w)
	{
		_wei = w;
		_isInCircle = false;
		_numberOfLoopsInvolved = 0;
	}

	
	
	public SimpleEdge(SimpleEdge e2) {
		_wei = e2.getWeight();
		_isInCircle = e2.isInCircle();
		_numberOfLoopsInvolved = e2.getNumOfLoopsInvolved();
	}


	/**
	 * @return the number of loops involving this edge
	 */
	public int getNumOfLoopsInvolved() {
		return _numberOfLoopsInvolved;
	}

	public void increaseNumOfLoopsBy1(){
		_numberOfLoopsInvolved++;
	}
	

	public void decreaseNumOfLoopsBy1() {
		_numberOfLoopsInvolved--;		
	}
	/*
	 * return weight
	 */
	public double getWeight()
	{
		return _wei;
	}

	/*
	 * set weight
	 */
	public void setWeight(double w)
	{
		_wei = w;
	}

	
	/**
	 * @return the _isInCircle
	 */
	public boolean isInCircle() {
		return _isInCircle;
	}



	/**
	 * @param isInCircle the _isInCircle to set
	 */
	public void setInCircle(boolean isInCircle) {
		_isInCircle = isInCircle;
	}



	/*
	 * toString
	 */
	public String toString()
	{
		return "("+_wei+")";
	}





	
//	public boolean equals(Object other)
//	{
//		return other!=null && 
//		_v1.equals(((SimpleEdge) other).getSourceVertex()) &&
//		_v2.equals(((SimpleEdge) other).getTargetVertex());
//	}
//	
//	public int hashCode()
//	{
////		Integer.parseInt("1"+_v1.getID()+"00"+_v2.getID());	
//		return (_v1.getID()+"00"+_v2.getID()).hashCode(); //make a string, and use the string hashcode.
//	}

}
