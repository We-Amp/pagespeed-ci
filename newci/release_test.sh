#!/bin/bash
set +e
set +x

TEST_TMP_DIR=/home/oschaaf/ci-out/mod_pagespeed/${SHA}/${TEMPLATE}-build-release-test-tmpdir
TEST_APACHE2_DIR=/home/oschaaf/ci-out/mod_pagespeed/${SHA}/${TEMPLATE}-build-release-test-apache2dir
ARTIFACT_DIR=/home/oschaaf/ci-out/mod_pagespeed/${SHA}/${TEMPLATE}-build-release-test-artifacts

if [ -d "$TEST_TMP_DIR" ]; then
  rm -rf "$TEST_TMP_DIR"
fi
if [ -d "$TEST_APACHE2_DIR" ]; then
  rm -rf "$TEST_APACHE2_DIR"
fi
if [ -d "$ARTIFACT_DIR" ]; then
  rm -rf "$ARTIFACT_DIR"
fi

exit_status=0
SPEC_32_BIT=""

if [[ "$TEMPLATE" == *"x86"* ]]; then
  SPEC_32_BIT="--32bit"
fi

ssh -t -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$IP <<EOF
  set -x
  export MAKEFLAGS=-j20
  git config --global url.https://github.com/apache/.insteadOf git://git.apache.org/
  git config --global submodule.fetchJobs 10
  sudo apt-get update
  set -e
  git clone https://github.com/pagespeed/mod_pagespeed.git gittest 
  cd gittest
  git fetch origin "${REF}:{$SHA}"
  git checkout "$SHA"
  install/build_release.sh --verbose --skip_psol ${SPEC_32_BIT}
EOF

exit_status="$?"
echo "test exit status: $exit_status. attempt to copy over logs and stuff"
ssh -t -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$IP <<EOF
  set -x
  sudo chmod -R a+r /tmp
EOF

mkdir "$TEST_TMP_DIR"
mkdir "$TEST_APACHE2_DIR"
mkdir "$ARTIFACT_DIR"
rsync -arvce "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" ubuntu@$IP:/tmp/ "$TEST_TMP_DIR" > /dev/null || true
rsync -arvce "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" ubuntu@$IP:~/apache2/ "$TEST_APACHE2_DIR" > /dev/null || true
rsync -arvce "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" ubuntu@$IP:~/gittest/release/ "$ARTIFACT_DIR" > /dev/null || true

exit "$exit_status"
