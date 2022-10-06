# dnaPipeTE: docker edition [![status](https://img.shields.io/badge/status:-v1.4_"container"-green)]() [![status: support](https://img.shields.io/badge/support:-yes-green)]()

********************************************************************************************************************
This branch is a modified version of the original dnaPipeTE distribution. Originally branched from [v1.3.1](https://github.com/clemgoub/dnaPipeTE/tree/vers1.3) to fit a dedicated docker container. 
It has since been updated to version 1.4 "container". Since version 1.3.1, all new releases of dnaPipeTE are "container" versions.

This repository only host the core code for dnaPipeTE and is a dependency of actual Dockerfile for dnaPipeTE hosted on the master branch.
Up-to-date and previous docker images for dnaPipeTE are available **here**.

********************************************************************************************************************

Changes from dnaPipeTE 1.3 "non-container":
- `dnaPipeTE.py`
   - The docker-specific [config.ini](https://gitlab.in2p3.fr/stephane.delmotte/dnapipete/-/blob/master/config.ini) has to be used.
   - blast2: the database (annotated dnaPipeTE contigs) is not merged with Repbase anymore for this blast, as Repbase in not freely accessible anymore. This was in case low-copy TE were missed but present in Repbase, they could be saved. However there is virtually no influence on the results.

Changes from dnaPipeTE 1.3.1 "container":
- `dnaPipeTE.py`
   - bug fix for issues #12,#55,#73
   - change version name 1.3.1 to 1.4 "container"
- remove `png` outputs for barplot and piecharts in order to avoid warnings in new 1.4 container.
- see all change from 1.3.1c to 1.4c in the [main dnaPipeTE page](https://github.com/clemgoub/dnaPipeTE/tree/master)