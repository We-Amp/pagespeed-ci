#!/bin/bash
set -x
sleep 5
exit_status=0
ssh -t -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$IP <<EOF
  set -e
  set -x
  export MAKEFLAGS=-j20
  git config --global submodule.fetchJobs 8
  git clone https://github.com/oschaaf/mod_pagespeed.git gittest 
  cd gittest
  git fetch origin "${REF}:{$SHA}"
  git checkout "$SHA"
  install/build_release.sh --verbose --skip_psol
EOF

exit_status="$?"
echo "test exit status: $exit_status"
scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r ubuntu@$IP:~/gittest/release/ /home/oschaaf/ci-out/mod_pagespeed/${SHA}/
exit $exit_status
