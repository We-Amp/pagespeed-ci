gcloud compute ssh "$machine_name" -- bash << EOF
  set -e
  set -x
  export MAKEFLAGS=-j4
  sudo apt-get update -q
  sudo apt-get install -q -y git build-essential zlib1g-dev libpcre3-dev unzip uuid-dev
  git config --global url.https://github.com/apache/.insteadOf git://git.apache.org/
  git config --global submodule.fetchJobs 4
  git clone https://github.com/pagespeed/ngx_pagespeed.git gittest 
  cd gittest
  git fetch origin "${REF}:{$SHA}"
  git checkout "$SHA"
  scripts/build_ngx_pagespeed.sh --devel --assume-yes
  # need to set +e here, because run_tests may leave dangling processes upon failure
  set +e  
  RUN_CONTROLLER_TEST=on test/run_tests.sh ~/gittest/testing-dependencies/mod_pagespeed/ ~/gittest/nginx/sbin/nginx
  exit_status="\$?"
  sudo service apache2 stop
  sudo killall memcached
  sudo killall nginx
  sudo killall php-cgi
  exit "\$exit_status"
EOF
