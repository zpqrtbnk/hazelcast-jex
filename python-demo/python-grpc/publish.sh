rm -rf publish/
mkdir publish/
#cp -R ../../python/grpc-runtime/* publish/
PUBLISH=$PWD/publish/
(cd ../../python/grpc-runtime && find . -type f -name '*.py' -exec cp --parents {} $PUBLISH \;)
cp ./requirements.txt publish/
cp ./usercode-functions.py publish/