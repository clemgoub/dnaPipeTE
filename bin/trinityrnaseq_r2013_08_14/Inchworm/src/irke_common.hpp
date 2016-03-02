#ifndef __IRKE_COMMON__
#define __IRKE_COMMON__

namespace IRKE_COMMON {
    
    extern unsigned int MONITOR;
    
    // various developer-evaluation settings.

    extern bool __DEVEL_no_kmer_sort;
    extern bool __DEVEL_no_greedy_extend;
    extern bool __DEVEL_no_tie_breaking;
    extern bool __DEVEL_zero_kmer_on_use;
    
    extern bool __DEVEL_rand_fracture;
    extern float __DEVEL_rand_fracture_prob;
    
}

#endif


