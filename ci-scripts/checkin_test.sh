set -e
set -x
gcloud compute ssh "$machine_name" -- bash << EOF
  set -e
  set -x
  if $use_rpms; then
    sudo yum -y install git redhat-lsb php5-cgi
  else
    sudo apt-get -y install git
  fi

  export MAKEFLAGS=-j3
  git config --global submodule.fetchJobs 8

  # CentOS 6's git is old enough that git clone -b <tag> doesn't work and
  # silently checks out HEAD. To be safe we use an explicit checkout below.
  git clone https://github.com/pagespeed/mod_pagespeed.git
  cd mod_pagespeed
  git fetch origin "${ref}:{$branch}"
  git checkout "$branch"
  git submodule update --init --recursive
  install/build_development_apache.sh 2.2 prefork
  devel/checkin 
EOF

gcloud compute copy-files "${machine_name}:mod_pagespeed/release/*" ~/release/
