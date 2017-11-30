#set your GIRI username and password
GIRINST_USERNAME='login'
GIRINST_PASSWORD='password'

if [[ $GIRINST_USERNAME == 'username' ]] || [[ $GIRINST_PASSWORD == 'password' ]]
then 
	echo "GIRI username and/or password not set in init.sh!"
	echo "Please specify your GIRI/Repbase login and re-run the script!"
else

mkdir -p bin
cd bin

# install trinity
echo ""
echo "Installing Trinity"
echo ""
curl -k -L https://github.com/trinityrnaseq/trinityrnaseq/archive/Trinity-v2.5.1.tar.gz -o Trinity-v2.5.1.tar.gz
tar -zxvf Trinity-v2.5.1.tar.gz
cd trinityrnaseq*
make
cd ../

# install trf
echo ""
echo "Installing Tandem Repeat Finder..."
echo ""
curl -k -L http://tandem.bu.edu/trf/downloads/trf409.linux64 -o trf
chmod +x trf

# RM blast
echo ""
echo "Installing RMBlastn..."
echo ""
curl -k -L  ftp://ftp.ncbi.nlm.nih.gov/blast/executables/rmblast/2.2.28/ncbi-rmblastn-2.2.28-x64-linux.tar.gz -o ncbi-rmblastn-2.2.28-x64-linux.tar.gz
tar -xvf ncbi-rmblastn-2.2.28-x64-linux.tar.gz
rm ncbi-rmblastn-2.2.28-x64-linux.tar.gz

# blast
echo ""
echo "Installing Blastn..."
echo ""
curl -k -L ftp://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/2.2.28/ncbi-blast-2.2.28+-x64-linux.tar.gz -o ncbi-blast-2.2.28+-x64-linux.tar.gz
tar -xvf ncbi-blast-2.2.28+-x64-linux.tar.gz
rm ncbi-blast-2.2.28+-x64-linux.tar.gz

cp ncbi-rmblastn-2.2.28/bin/* ncbi-blast-2.2.28+/bin/

# install RepeatMasker
echo ""
echo "Installing RepeatMasker"
echo ""
curl -k -L http://repeatmasker.org/RepeatMasker-open-4-0-7.tar.gz -o RepeatMasker-open-4-0-7.tar.gz
tar -xvf RepeatMasker-open-4-0-7.tar.gz

# RM database
echo ""
echo "Installing RM Libraries"
echo ""
wget http://www.girinst.org/server/RepBase/protected/repeatmaskerlibraries/RepBaseRepeatMaskerEdition-20170127.tar.gz --password=$GIRINST_PASSWORD  --user=$GIRINST_USERNAME
mv RepBaseRepeatMaskerEdition-20170127.tar.gz RepeatMasker/
cd RepeatMasker
tar -zxvf RepBaseRepeatMaskerEdition-20170127.tar.gz

echo ""
echo "##################################################################################################"
echo "installation of dependencies done, now run the ./configure script in the ./bin/RepeatMasker folder"
echo "##################################################################################################"

fi
