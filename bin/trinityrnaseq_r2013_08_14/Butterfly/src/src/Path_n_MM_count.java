import java.util.Vector;


public class Path_n_MM_count {

	Integer mismatch_count = 0;
	Vector<Integer> path;

	public Path_n_MM_count() {
		path = new Vector<Integer>();
	}

	public Path_n_MM_count(Integer node, Integer mm) {

		path = new Vector<Integer>();
		mismatch_count += mm;
		path.add(0, node);
	}

	public void add_path_n_mm (Integer node, Integer mm) {
		path.add(0, node);
		mismatch_count += mm;
	}

}
