# pagespeed-ci
PageSpeed CI Scripts


Run CI Driver:

oschaaf@ps-ci:~/newci⟫ python3 ci.py 



Sample runs:

# Set the project of interest
gcloud config set project hello-world-314

CLOUDSDK_COMPUTE_ZONE=us-east1-c ./ci_run.sh --build_branch 35 --script=build_release.sh --centos
CLOUDSDK_COMPUTE_ZONE=us-east1-c ./ci_run.sh --build_branch 35 --script=checkin_test.sh


Start webserver:
$/var/www/ci/MPSCI⟫ dotnet restore && ASPNETCORE_ENVIRONMENT=Development dotnet run
