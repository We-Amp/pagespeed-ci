gcloud compute ssh "$machine_name" -- bash << EOF
  set -e
  set -x
  if $use_rpms; then
    sudo yum -y install git redhat-lsb
  else
    sudo apt-get -y install git
  fi

  export MAKEFLAGS=-j8
  git config --global submodule.fetchJobs 6

  # CentOS 6's git is old enough that git clone -b <tag> doesn't work and
  # silently checks out HEAD. To be safe we use an explicit checkout below.
  git clone https://github.com/pagespeed/mod_pagespeed.git
  cd mod_pagespeed
  git fetch origin "${ref}:{$branch}"
  git checkout "$branch"
  install/build_release.sh --verbose --skip_psol
EOF

# gcloud compute copy-files "${machine_name}:mod_pagespeed/release/*" ~/release/
