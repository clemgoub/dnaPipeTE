# dnaPipeTE: docker edition [![status](https://img.shields.io/badge/status:-v1.3.docker-orange)]() [![status: support](https://img.shields.io/badge/support:-no-red)]()

********************************************************************************************************************
This branch is a modified version of [dnaPipeTE v1.3](https://github.com/clemgoub/dnaPipeTE/tree/master) to fit a dedicated docker container (currently under development)
This repository is not the docker version of dnaPipeTE, which will be released **here**.

Changes with dnaPipeTE 1.3:
- `dnaPipeTE.py`
   - The docker-specific [config.ini](https://gitlab.in2p3.fr/stephane.delmotte/dnapipete/-/blob/master/config.ini) has to be used.
   - blast2: the database (annotated dnaPipeTE contigs) is not merged with Repbase anynore for this blast, as Repbase in not freely accessible anymore. This was in case low-copy TE were missed but present in Repbase, they could be saved. However there is virtualy no influence on the results.

