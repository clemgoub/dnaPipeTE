import java.util.Comparator;


public class numLoopsEdgeComparator implements Comparator<Object> {

	@Override
	public int compare(Object o1, Object o2) {
		SimpleEdge e1 = (SimpleEdge)o1;
		SimpleEdge e2 = (SimpleEdge)o2;
		
		int l1 = e1.getNumOfLoopsInvolved();
		int l2 = e2.getNumOfLoopsInvolved();
		
		double s1 = e1.getWeight();
		double s2 = e2.getWeight();
		
		if( l1 < l2 )
			return 1;
		else if( l1 > l2 )
			return -1;
		else
		{
			if (s1 > s2)
				return 1;
			else if (s1 < s2)
				return -1;
			else
				return 0;
		}
		
	}

}
