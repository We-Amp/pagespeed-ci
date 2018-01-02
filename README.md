# pagespeed-ci
PageSpeed CI Scripts


Run CI Driver:

Add .token file, containing API token for pagespeed-ci github user.
Then, run:
oschaaf@ps-ci:~/newci⟫ sudo python3 ci.py 



Sample runs:

# Set the project of interest
gcloud config set project pagespeed-ci
CLOUDSDK_COMPUTE_ZONE=us-east1-c ./ci_run.sh --ref=refs/pull/1696/merge  --build_branch=047e2c30d2ecc8c298594e676dad6db3cda8ec17 --script=build_release.sh --centos
CLOUDSDK_COMPUTE_ZONE=us-east1-c ./ci_run.sh --build_branch 35 --script=checkin_test.sh


Start webserver:
Install .net core: https://www.microsoft.com/net/learn/get-started/linuxubuntu
$/var/www/ci/MPSCI⟫ dotnet restore && sudo dotnet run
