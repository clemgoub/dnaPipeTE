#!/bin/bash

# Chrysalis wants sort in the trinity-plugins/coreutils/bin folder
# we have to deal with three possibilities
# 1. sort of the system is recent enough
#    - just symlink it
# 2. sort is to old
#    - build it from coreutils
# 3. sort is to old and building it fails
#    - create a shellscript that will strip off the "--parallel" so that the old sort works 

#switch to the folder of this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR

# Version has to be at least 8.6 so feature "--parallel"
VERSIONSTRING=(`sort --version | head -1`)
VERSION=${VERSIONSTRING[3]}
MAJOR=${VERSION%.*}
MINOR=${VERSION#*.}

if [ $MAJOR -gt 8 -o $MAJOR -eq 8 -a $MINOR -ge 6 ]; then
  echo "sort is recent enough, bailing out >&2 "
  mkdir -p ${DIR}/bin
  cd ${DIR}/bin
  SORTPATH=`which sort`
  ln -s ${SORTPATH}
  exit 0
fi 

# else try to build new sort
FILE=`ls coreutils*.tar.bz2| tail -1`

INSTALLDIR=`echo ${FILE} | cut -d '.' -f 1-2`

echo "INSTALLDIR: ${INSTALLDIR}"

if [ ! -d ${INSTALLDIR} ] ; then
    tar xjf ${FILE}
fi

if [ ! -d ${INSTALLDIR} ] ; then
    echo "sort installation went terribly wrong >&2"
    exit 127
fi

cd ${INSTALLDIR}
./configure
#make clean
make -j
cd src
mkdir -p ${DIR}/bin
cp sort ${DIR}/bin
cd ${DIR}
#rm -rf ${INSTALLDIR}

# in case that the sort build fails, create a workaround
cd bin
if [ ! -f ./sort ]; then
  echo "#!/bin/bash
#  echo \"this script will remove the first argument which has to be the --parallel=NCPU >&2 \"
  shift
  sort \$*
  ">sort
  chmod +x ./sort
fi

