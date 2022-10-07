FROM debian:9-slim
# Debian 9's gcc/g++ version is required for proper compilation of Trinity 2.5.1 (Deb 10 doesn't work with it, would need to update Trinity)
USER root

# install all Debian libs for the dependent programs and packages
RUN apt-get update -qq \
&& apt-get -y --no-install-recommends install git \
 make g++ gcc \
 bowtie2 \
 zlib1g-dev libxml2-dev \
 unzip \
 libssl-dev \
 curl wget \
 libgomp1 \
 perl \
 libfile-which-perl \
 libtext-soundex-perl \
 libjson-perl liburi-perl libwww-perl \
 libdevel-size-perl \
 aptitude \
 python3-h5py \
 libfile-which-perl \
 libtext-soundex-perl \
 libjson-perl liburi-perl libwww-perl \
 libdevel-size-perl \
 xvfb \
 xorg xorg-dev \
&& aptitude install -y ~pstandard ~prequired \
 vim nano \
 procps strace \
 libpam-systemd-

# clone dnaPipeTE and dnaPT_utils from github
RUN git clone --branch docker --single-branch https://github.com/clemgoub/dnaPipeTE /opt/dnaPipeTE \
&& git clone https://github.com/clemgoub/dnaPT_utils.git opt/dnaPT_utils

# Install RepeatMasker
RUN mkdir /opt/src \
&& cd /opt/src \
&& wget -O rmblast-2.11.0+-x64-linux.tar.gz https://www.repeatmasker.org/rmblast-2.11.0+-x64-linux.tar.gz \
&& wget -O hmmer-3.3.2.tar.gz http://eddylab.org/software/hmmer/hmmer-3.3.2.tar.gz \
&& wget -O trf-4.09.1.tar.gz https://github.com/Benson-Genomics-Lab/TRF/archive/v4.09.1.tar.gz \
&& wget -O RepeatMasker-4.1.3.tar.gz https://www.repeatmasker.org/RepeatMasker/RepeatMasker-4.1.3.tar.gz

# Install RMBlast
RUN cd /opt \
&& mkdir rmblast \
&& tar --strip-components=1 -x -f src/rmblast-2.11.0+-x64-linux.tar.gz -C rmblast \
&& rm src/rmblast-2.11.0+-x64-linux.tar.gz

# Compile HMMER
RUN cd /opt/src \
&& tar -x -f hmmer-3.3.2.tar.gz \
&& cd hmmer-3.3.2 \
&& ./configure --prefix=/opt/hmmer && make && make install \
&& make clean

# Compile TRF
RUN cd /opt/src \
&& tar -x -f trf-4.09.1.tar.gz \
&& cd TRF-4.09.1 \
&& mkdir build && cd build \
&& ../configure && make && cp ./src/trf /opt/trf \
&& cd .. && rm -r build

# Configure RepeatMasker
RUN cd /opt \
&& tar -x -f src/RepeatMasker-4.1.3.tar.gz \
&& chmod a+w RepeatMasker/Libraries \
&& cd RepeatMasker \
&& perl configure \
-hmmer_dir=/opt/hmmer/bin \
-rmblast_dir=/opt/rmblast/bin \
-libdir=/opt/RepeatMasker/Libraries \
-trf_prgm=/opt/trf \
-default_search_engine=rmblast \
&& cd .. && rm src/RepeatMasker-4.1.3.tar.gz

# hotfix RepeatMasker 4.1.3
RUN cd /opt/RepeatMasker \
&& head -n 3725 ProcessRepeats > ProcessBefore \
&& awk 'NR > 3726' ProcessRepeats > ProcessAfter \
&& touch ProcessFix \
&& printf "              if ( \$newRight ) {\n" >> ProcessFix \
&& printf "                \$newRight->setLeftLinkedHit( \$newHit );\n" >> ProcessFix \
&& printf "              }\n" >> ProcessFix \
&& cat ProcessBefore ProcessFix ProcessAfter > ProcessRepeats \
&& rm ProcessBefore ProcessAfter ProcessFix

# install trinity
RUN cd /opt/dnaPipeTE/bin \
&& curl -k -L https://github.com/trinityrnaseq/trinityrnaseq/archive/Trinity-v2.5.1.tar.gz -o Trinity-v2.5.1.tar.gz \
&& tar -zxvf Trinity-v2.5.1.tar.gz \
&& cd trinityrnaseq* \
&& make 

# copy Java 1.8
RUN cd /opt/dnaPipeTE/bin \
&& wget https://ftp.osuosl.org/pub/blfs/conglomeration/openjdk/OpenJDK-1.8.0.141-x86_64-bin.tar.xz \
&& tar -xJf OpenJDK-1.8.0.141-x86_64-bin.tar.xz

# install blast+
RUN cd /opt/dnaPipeTE/bin \
&& curl -k -L ftp://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/2.2.28/ncbi-blast-2.2.28+-x64-linux.tar.gz -o ncbi-blast-2.2.28+-x64-linux.tar.gz \
&& tar -xvf ncbi-blast-2.2.28+-x64-linux.tar.gz \
&& rm ncbi-blast-2.2.28+-x64-linux.tar.gz

# copy docker-specific config file for dnaPipeTE
COPY config.ini /opt/dnaPipeTE

# install R and R packages
ENV R_VERSION=R-4.2.1
RUN apt-get -y --no-install-recommends install libpcre2-8-0 libpcre2-dev libcurl4-openssl-dev r-base r-base-dev
RUN curl https://cran.r-project.org/src/base/R-4/$R_VERSION.tar.gz -o $R_VERSION.tar.gz && \
    tar xvf $R_VERSION.tar.gz && \
    cd $R_VERSION && \
	./configure && make && make install

RUN Rscript -e "install.packages(\"ggplot2\", dependencies = TRUE, repos = \"https://cloud.r-project.org/\")" 
RUN Rscript -e "install.packages(\"tidyverse\", dependencies = TRUE, repos = \"https://cloud.r-project.org/\")"
RUN Rscript -e "install.packages(\"cowplot\", dependencies = TRUE, repos = \"https://cloud.r-project.org/\")"
RUN Rscript -e "install.packages(\"tidyr\", dependencies = TRUE, repos = \"https://cloud.r-project.org/\")"
RUN Rscript -e "install.packages(\"scales\", dependencies = TRUE, repos = \"https://cloud.r-project.org/\")"
RUN Rscript -e "install.packages(\"reshape2\", dependencies = TRUE, repos = \"https://cloud.r-project.org/\")"

RUN echo "PS1='(dnaPipeTE\$(pwd))\\\$ '" >> /etc/bash.bashrc
RUN echo "export JAVA_HOME=/opt/dnaPipeTE/bin/OpenJDK-1.8.0.141-x86_64-bin" >> /etc/bash.bashrc
RUN chmod +x /opt/dnaPipeTE/*

# install cd-hit
RUN wget https://github.com/weizhongli/cdhit/releases/download/V4.8.1/cd-hit-v4.8.1-2019-0228.tar.gz \
	&& tar -x -f cd-hit-v4.8.1-2019-0228.tar.gz \
    && cd cd-hit-v4.8.1-2019-0228 \
    && make && mkdir /opt/cd-hit && PREFIX=/opt/cd-hit make install \
    && chmod +x /opt/cd-hit/*

# make aliases to run xvfb with R and python3
RUN echo "alias Rscript='xvfb-run Rscript'" >> ~/.bashrc
RUN echo "alias R='xvfb-run R'" >> ~/.bashrc
RUN echo "alias python3='xvfb-run python3'" >> ~/.bashrc

# remove older R version
RUN apt-get -y remove r-base r-base-dev

# set env
ENV PATH=/bin:/sbin:/opt/dnaPipeTE/bin/OpenJDK-1.8.0.141-x86_64-bin/bin/:/opt/RepeatMasker:/opt/RepeatMasker/util:/opt/RepeatModeler:/opt/RepeatModeler/util:/opt/coseg:/opt/ucsc_tools:/opt/dnaPipeTE:/opt/dnaPT_utils:/opt/cd-hit/
ENV PATH=/usr/local/bin:/usr/bin:$PATH

WORKDIR /opt/dnaPipeTE