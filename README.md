# pagespeed-ci
PageSpeed CI Scripts


Run CI Driver:

oschaaf@ps-ci:~/newci⟫ python3 ci.py 

Sample runs:

CLOUDSDK_COMPUTE_ZONE=us-central1-a ./ci_run.sh --build_branch 35 --script=build_release.sh --centos
CLOUDSDK_COMPUTE_ZONE=us-central1-a ./ci_run.sh --build_branch 35 --script=checkin_test.sh


Start webserver:
$/var/www/ci/MPSCI⟫ dotnet restore && ASPNETCORE_ENVIRONMENT=Development dotnet run
