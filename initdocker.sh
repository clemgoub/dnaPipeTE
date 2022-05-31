#!/bin/bash

mkdir -p bin
cd /opt/dnaPipeTE/bin

# install trinity
echo ""
echo "Installing Trinity"
echo ""
curl -k -L https://github.com/trinityrnaseq/trinityrnaseq/archive/Trinity-v2.5.1.tar.gz -o Trinity-v2.5.1.tar.gz
tar -zxvf Trinity-v2.5.1.tar.gz
cd trinityrnaseq*
make
cd ../

# copy Java 1.8
echo ""
echo "Downloading Java 1.8 distribution..."
echo ""
wget ftp://pbil.univ-lyon1.fr/pub/divers/goubert/dnaPipeTE/OpenJDK-1.8.0.141-x86_64-bin.tar.xz
tar -xJf OpenJDK-1.8.0.141-x86_64-bin.tar.xz

# blast
echo ""
echo "Installing Blastn..."
echo ""
curl -k -L ftp://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/2.2.28/ncbi-blast-2.2.28+-x64-linux.tar.gz -o ncbi-blast-2.2.28+-x64-linux.tar.gz
tar -xvf ncbi-blast-2.2.28+-x64-linux.tar.gz
rm ncbi-blast-2.2.28+-x64-linux.tar.gz