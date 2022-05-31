FROM dfam/tetools:latest
USER root

RUN apt-get update -qq \
&& apt-get -y --no-install-recommends install git make g++ zlib1g-dev libxml2-dev bowtie2 unzip r-base r-base-dev \
&& git clone --branch docker --single-branch https://github.com/clemgoub/dnaPipeTE /opt/dnaPipeTE

COPY initdocker.sh /opt/dnaPipeTE
RUN /opt/dnaPipeTE/initdocker.sh

COPY config.ini /opt/dnaPipeTE
RUN Rscript -e "install.packages(\"ggplot2\", dependencies = TRUE, repos = \"http://cran.univ-lyon1.fr\")"

RUN echo "PS1='(dnaPipeTE\$(pwd))\\\$ '" >> /etc/bash.bashrc
RUN echo "export JAVA_HOME=/opt/dnaPipeTE/bin/OpenJDK-1.8.0.141-x86_64-bin" >> /etc/bash.bashrc

ENV PATH=/bin:/sbin:/opt/dnaPipeTE/bin/OpenJDK-1.8.0.141-x86_64-bin/bin/:/opt/RepeatMasker:/opt/RepeatMasker/util:/opt/RepeatModeler:/opt/RepeatModeler/util:/opt/coseg:/opt/ucsc_tools
ENV PATH=/usr/bin:/usr/local/bin:$PATH