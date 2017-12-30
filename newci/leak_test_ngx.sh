#!/bin/bash
ssh -t -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$IP -- bash << EOF
  set -e
  set -x
  export MAKEFLAGS=-j20
  sudo apt-get update
  git config --global url.https://github.com/apache/.insteadOf git://git.apache.org/
  git config --global submodule.fetchJobs 10
  git clone https://github.com/pagespeed/ngx_pagespeed.git gittest 
  cd gittest
  git fetch origin "${REF}:{$SHA}"
  git checkout "$SHA"
  scripts/build_ngx_pagespeed.sh --devel --assume-yes
  # need to set +e here, because run_tests may leave dangling processes upon failure
  set +e
  USE_VALGRIND=true test/run_tests.sh ~/gittest/testing-dependencies/mod_pagespeed/ ~/gittest/nginx/sbin/nginx
  exit_status="\$?"
  sudo service apache2 stop
  sudo killall memcached
  sudo killall nginx
  sudo killall php-cgi
  sudo killall memcheck-amd64-
  sudo killall memcheck-x86-
  exit "\$exit_status"
EOF
