echo install dotnet
curl -s https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
sudo mv microsoft.gpg /etc/apt/trusted.gpg.d/microsoft.gpg
sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/microsoft-ubuntu-xenial-prod xenial main" > /etc/apt/sources.list.d/dotnetdev.list'

echo setup google cloud storage FUSE
export GCSFUSE_REPO=gcsfuse-`lsb_release -c -s`
echo "deb http://packages.cloud.google.com/apt $GCSFUSE_REPO main" | sudo tee /etc/apt/sources.list.d/gcsfuse.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

sudo apt-get update
sudo apt-get install dotnet-sdk-2.0.2
sudo apt-get install gcsfuse authbind

sudo touch /etc/authbind/byport/80
sudo touch /etc/authbind/byport/443
sudo chmod 777 /etc/authbind/byport/80
sudo chmod 777 /etc/authbind/byport/443


# install python3
sudo apt-get install python3


if [ ! -f newci/.token ]; then
    echo "Please give a github OAuth token for accessing the api"
    read token
    echo token > newci/.token
fi

pushd MPSCI
dotnet restore
popd

#if [ ! -d newci/ci-out-gfs ]; then
#    pushd newci
#    mkdir newci/ci-out-gfs
    # Set up default service account
    # gcloud auth application-default login
#    popd
#fi
#gcsfuse pagespeed-ci newci/ci-out-gfs
