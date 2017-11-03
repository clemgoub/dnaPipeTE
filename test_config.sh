#! /bin/bash
# -*-coding:Utf-8 -*

#Copyright (C) 2014 Clement Goubert and Laurent Modolo

#This program is free software; you can redistribute it and/or
#modify it under the terms of the GNU Lesser General Public
#License as published by the Free Software Foundation; either
#version 2.1 of the License, or (at your option) any later version.

#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
#Lesser General Public License for more details.

#You should have received a copy of the GNU Lesser General Public
#License along with this program; if not, write to the Free Software
#Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA

echo "This is the test script for dnaPipeTE"
echo "                  ***                "
echo ""
echo "We will test a few dependancies to be sure tha the pipeline run properly"
echo ""
echo ""
echo "Testing Java..." 

JAVA_VER=$(java -version 2>&1 | sed -n ';s/.* version "\(.*\)\.\(.*\)\..*"/\1\2/p;')
here=$(pwd)
if [[ "$JAVA_VER" < "18" ]]; then 
	echo "java version < 1.8, either install latest version or"
	echo "run ./fixjava.sh to use the provided version"
 else
	echo "java version OK!"
fi
echo ""
echo ""
echo "Testing RepeatMasker Libraries..."

if [[ $(grep -c '>' ./bin/RepeatMasker/Libraries/RepeatMasker.lib) > 425 ]]; then
	echo "Repbase Libraries are properly installed!"
else
	echo "RepeatMasker.lib doesn't include the Repbase sequences! Follow instruction to install RepeatMasker libraries on https://github.com/clemgoub/dnaPipeTE"
fi
