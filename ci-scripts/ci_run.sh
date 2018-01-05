#!/bin/bash
#
# Copyright 2016 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Author: oschaaf@we-amp.com
# Based on Steve Hill's build_on_vm script.
#
# For testing mod_pagespeed on a gcloud VM.
#
# You may want to set CLOUDSDK_COMPUTE_REGION and/or CLOUDSDK_CORE_PROJECT,
# or set your gcloud defaults befor running this:
# https://cloud.google.com/sdk/gcloud/reference/config/set

set -u

ref="refs/heads/master"
branch=master
delete_existing_machine=false
image_family=ubuntu-1404-lts
keep_machine=false
machine_name=
use_existing_machine=false
script=build_release.sh
name="noname"

options="$(getopt --long build_branch:,centos,delete_existing_machine \
  --long image_family:,machine_name:,use_existing_machine \
  --long name:, --long script:, --long ref:, -o '' -- "$@")"
if [ $? -ne 0 ]; then
  echo"Usage: $(basename "$0") [options] -- [build_release.sh options]" >&2
  echo "  --build_branch=<branch>    mod_pagespeed branch to build" >&2
  echo "  --centos                   Shortcut for --image_family=centos-6" >&2
  echo "  --delete_existing_machine  If the VM already exists, delete it" >&2
  echo "  --image_family=<family>    Image family used to create VM" >&2
  echo "                             See: gcloud compute images list" >&2
  echo "  --machine_name             VM name to create" >&2
  echo "  --use_existing_machine     Re-run build on exiting VM" >&2
  echo "  --script                   CI Script to run" >&2
  echo "  --ref=<ref>                Git refspec" >&2
  exit 1
fi

set -e
eval set -- "$options"

while [ $# -gt 0 ]; do
  case "$1" in
    --build_branch) branch="$2"; shift 2 ;;
    --script) script="$2"; shift 2 ;;
    --ref) ref="$2"; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --centos) image_family="centos-6"; shift ;;
    --delete_existing_machine) delete_existing_machine=true; shift ;;
    --image_family) image_family="$2"; shift 2 ;;
    --keep_machine) keep_machine=true; shift ;;
    --machine_name) machine_name="$2"; shift 2 ;;
    --use_existing_machine) use_existing_machine=true; shift ;;
    --) shift; break ;;
    *) echo "getopt error" >&2; exit 1 ;;
  esac
done

echo "Building ref: $ref, branch $branch, script $script"


if $use_existing_machine && $delete_existing_machine; then
  echo "Supply only one of --delete_existing_machine and" \
       "--use_existing_machine" >&2
  exit 1
fi

if ! type gcloud >/dev/null 2>&1; then
  echo "gcloud is not in your PATH. See: https://cloud.google.com/sdk/" >&2
  exit 1
fi

use_rpms=false

case "$image_family" in
  centos-*) image_project=centos-cloud ; use_rpms=true ;;
  ubuntu-*) image_project=ubuntu-os-cloud ;;
  *) echo "This script doesn't recognize image family '$image_family'" >&2;
     exit 1 ;;
esac

if [ -z "$machine_name" ]; then
  bit_suffix=
  for flag in "$@"; do
    if [ "$flag" = "--32bit" ]; then
      bit_suffix='-32'
      break
    fi
  done

  # gcloud is pretty fussy about machine names.
  sanitized_branch="$(tr _ - <<< "$branch" | tr -d . | cut -c 1-10)"
  
  machine_name="${USER}-ci-${name}-${image_family}${bit_suffix}"
  machine_name+="-${sanitized_branch}-mps-build${bit_suffix}"
fi

instances=$(gcloud compute instances list --filter="name=( '$machine_name' )")
if [ -n "$instances" ]; then
  if $delete_existing_machine; then
    gcloud -q compute instances delete "$machine_name"
    instances=
  elif ! $use_existing_machine; then
    echo "Instance '$machine_name' already exists." >&2
    exit 1
  fi
fi
gcloud config set compute/zone us-east1-c
if [ -z "$instances" ] || ! $use_existing_machine; then
  gcloud compute instances create "$machine_name" \
	 --image-family="$image_family" --image-project="$image_project" \
         --custom-cpu=2 --custom-memory=6GB \
	 --boot-disk-type=pd-ssd
fi


function savelog {
    gcloud compute ssh "$machine_name" -- bash << EOF
  echo "**** start dump logs"

  function dumplog() {
    echo "#### start dump \$1"
    cat "\$1"
    echo "#### end dump \$1"
  }

  shopt -s globstar nullglob dotglob
cd /tmp
for f in \$(find . | grep .log) ; do
  dumplog "\$f"
done


  echo "**** end dump logs"
EOF
}

function cleanup {
  savelog || true
  if ! $keep_machine; then
    echo -e "\nDelete GCE instance $machine_name"
    gcloud -q compute instances delete "$machine_name"
  fi
}

function fail_build {
    echo -e "\nBuild failed on $machine_name"
    cleanup
}

# Display an error including the machine name if we die in the script below.
trap '[ $? -ne 0 ] && fail_build' EXIT

count=1
until gcloud compute ssh "$machine_name" -- bash << EOF
  ls
EOF

do
  if [ $count -eq 30 ]
  then
       printf "GCE ssh failed to connect: max retries exceeded: ${count}\n"
       exit 1
  fi
  sleep 10
  ((count++))
done

export use_rpms
export machine_name
export ref
export branch
timeout 20000 ./$script
exit_status=$?
cleanup
echo "exit status $exit_status"
exit $exit_status
