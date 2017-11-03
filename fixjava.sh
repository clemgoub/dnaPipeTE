#! /bin/bash
#This script amend and source your ~/.bashrc file to use the Java 1.8 version provided with dnaPipeTE

#export the Java 1.8 program path from dnaPipeTE ./bin folder
here=$(pwd)
echo "### Add Java 8 from dnaPipeTE to Path" >> ~/.bashrc
echo "export JAVA_HOME=$here/bin/OpenJDK-1.8.0.141-x86_64-bin" >> ~/.bashrc
echo "export PATH=\"\$JAVA_HOME/bin:\$PATH\"" >> ~/.bashrc

echo "type \"source ~/.bashrc\" now to make changes effective and you're done!" 
