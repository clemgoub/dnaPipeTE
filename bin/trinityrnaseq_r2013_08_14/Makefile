###################################################################
#
# The default compiler is GNU gcc/g++.
# Run
#  make TRINITY_COMPILER=intel
# to build Inchworm and Chrysalis with the Intel compiler.
#

ifeq ($(TRINITY_COMPILER),intel)
INCHWORM_CONFIGURE_FLAGS = CXX=icpc CXXFLAGS="-fast"
CHRYSALIS_MAKE_FLAGS = COMPILER=icpc
else
override TRINITY_COMPILER=gnu
endif

TARGETS=inchworm chrysalis jellyfish fastool parafly slclust coreutils collectl

all: ${TARGETS}
	sh install_tests.sh

inchworm:
	@echo Using $(TRINITY_COMPILER) compiler for Inchworm and Chrysalis
	cd Inchworm && (test -e configure || autoreconf) \
                && ./configure --prefix=`pwd` $(INCHWORM_CONFIGURE_FLAGS) && $(MAKE) install

chrysalis:
	cd Chrysalis && $(MAKE) UNSUPPORTED=yes $(CHRYSALIS_MAKE_FLAGS)

jellyfish:
	cd trinity-plugins/jellyfish && ./configure CC=gcc CXX=g++ --prefix=`pwd` && $(MAKE) AM_CPPFLAGS="-Wall -Wnon-virtual-dtor -I"`pwd`

fastool:
	cd trinity-plugins/fastool && $(MAKE)

parafly:
	cd trinity-plugins/parafly && ./configure --prefix=`pwd` && $(MAKE) install

slclust:
	cd trinity-plugins/slclust && $(MAKE) install

coreutils:
	cd trinity-plugins/coreutils && ./build_parallel_sort.sh

collectl:
	cd trinity-plugins/collectl && ./build_collectl.sh

test:
	sh install_tests.sh

clean:
	cd Inchworm && make clean
	cd Chrysalis && $(MAKE) clean UNSUPPORTED=yes
	cd trinity-plugins/jellyfish && $(MAKE) clean 
	cd trinity-plugins/fastool && $(MAKE) clean
	cd trinity-plugins/parafly && $(MAKE) clean
	cd trinity-plugins/slclust && $(MAKE) clean
	cd trinity-plugins/coreutils && rm -rf bin && rm -rf && rm -rf coreutils-8.17
	cd trinity-plugins/collectl && rm -rf bin doc man


###################################################################


