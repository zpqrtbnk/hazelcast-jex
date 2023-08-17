
function init () {
    # initialize
    export DEMO=/c/Users/sgay/Code/hazelcast-jex
    export MVN=$DEMO/../mvn/apache-maven-3.8.1/bin/mvn
    export CLUSTERNAME=dev
    export CLUSTERADDR=localhost:5701
    export HZVERSION=5.4.0-SNAPSHOT
    export CLI=$DEMO/hazelcast/distribution/target/hazelcast-$HZVERSION/bin/hz-cli
    export CLZ=$DEMO/hazelcast/distribution/target/hazelcast-$HZVERSION/bin/hz
    export CLC=hazelcast-commandline-client/build/clc.exe
    export HAZELCAST_CONFIG=$DEMO/hazelcast-cluster.xml
    export LOGGING_LEVEL=DEBUG

    alias demo=./demo.sh
}

# build the Hazelcast CLC project
function build_clc () {
    (cd hazelcast-commandline-client &&
        CLC_VERSION=UNKNOWN
        GIT_COMMIT=
        LDFLAGS=""
        LDFLAGS="$LDFLAGS -X 'github.com/hazelcast/hazelcast-commandline-client/internal.GitCommit=$GIT_COMMIT'"
        LDFLAGS="$LDFLAGS -X 'github.com/hazelcast/hazelcast-commandline-client/internal.Version=$CLC_VERSION '"
        LDFLAGS="$LDFLAGS -X 'github.com/hazelcast/hazelcast-go-client/internal.ClientType=CLC'"
        LDFLAGS="$LDFLAGS -X 'github.com/hazelcast/hazelcast-go-client/internal.ClientVersion=$CLC_VERSION'"
        go-winres make --in extras/windows/winres.json --product-version=$CLC_VERSION --file-version=$CLC_VERSION --out cmd/clc/rsrc &&
        go build -tags base,hazelcastinternal,hazelcastinternaltest -ldflags "$LDFLAGS" -o build/clc.exe ./cmd/clc)
}

function configure_clc () {    
    # configure CLC
    # FIXME there has to be a better way?!
    cat <<EOF > $TEMP/clc-config.yml
    cluster:
    name: $CLUSTERNAME
    address: $CLUSTERADDR
EOF
    $CLC config add $TEMP/clc-config.yml
    rm $TEMP/clc-config.yml
}

function build_cluster () {
    # build the Hazelcast project
    # includes the packages
    (cd hazelcast &&
        $MVN package -DskipTests -Dcheckstyle.skip=true &&
        cd distribution/target &&
        rm -rf hazelcast-$HZVERSION && 
        unzip hazelcast-$HZVERSION.zip)
}

function build_client_dotnet () {
    # build the Hazelcast .NET client
    # includes the new Hazelcast.Net.Jet NuGet package
    # and cleanup the package cache because we are not changing the version
    (cd hazelcast-csharp-client &&
        pwsh ./hz.ps1 build,pack-nuget &&
        rm -rf ~/.nuget/packages/hazelcast.net &&
        rm -rf ~/.nuget/packages/hazelcast.net.jet &&
        rm -rf ~/.nuget/packages/hazelcast.net.usercode)
}

function build_demo_dotnet () {

    # build the demo code
    # * a 'common' project = a library used by other projects
    # * a 'service' project = the server-side .NET code
    # * a 'submit' project = submits the job (eventually, will do with CLC)
    # * a 'example' project = the client-side .NET code

    (
        cd jex-dotnet

        # build the dotnet jex code
        dotnet build

        # publish the dotnet service for the platforms we want to support
        # the project file specifies:
        #   <PublishSingleFile>true</PublishSingleFile>
        #   <PublishTrimmed>false</PublishTrimmed>
        # and then we publish
        #    publish/single-file/* which are single-file executables (but require that .NET is installed)
        #    publish/self-contained/* which are self-contained executables (include .NET)
        (
            cd dotnet-shmem
            rm -rf publish
            for platform in win-x64 linux-x64 osx-arm64; do
                dotnet publish -c Release -r $platform -o publish/single-file/$platform --self-contained false
                dotnet publish -c Release -r $platform -o publish/self-contained/$platform --self-contained true
            done
        )
        (
            cd dotnet-grpc
            rm -rf publish
            for platform in win-x64 linux-x64 osx-arm64; do
                dotnet publish -c Release -r $platform -o publish/single-file/$platform --self-contained false
                dotnet publish -c Release -r $platform -o publish/self-contained/$platform --self-contained true
            done
        )
    )
}

function build_demo_python () {

    (
        cd jex-python

        PUBLISH=$PWD/python-grpc/publish/
        rm -rf $PUBLISH
        mkdir $PUBLISH
        PUBLISH=$PUBLISH/any
        mkdir $PUBLISH
        (
            cd grpc-runtime
            find . -type f -name '*.py' -exec cp --parents {} $PUBLISH \;
        )
        (
            cd python-grpc
            cp requirements.txt $PUBLISH
            cp *.py $PUBLISH
        )
    )
}

function runtime_python () {

    (
        VENV_PATH=$PWD/temp
        cd jex-python/python-grpc/publish/any
        python usercode-runtime.py --grpc-port 5252 --venv-path=$VENV_PATH --venv-name=python-venv
    )
}

function runtime_dotnet_grpc () {
    (
        cd jex-dotnet/dotnet-grpc
        dotnet run
    )
}

function submit () {

    SOURCE=$1
    echo "DEMO: submit $SOURCE" # fixme make it absolute?

    if [ ! -f $SOURCE ]; then
        echo "ERR: file nout found"
        return
    fi

    # submit the job (the dotnet way)
    # (eventually, this should be done by CLC)
    # submit:source points to the yaml file
    # submit:define:* provides replacement for %TOKEN% in the yaml file
    (
        cd jex-dotnet/dotnet-submit
        dotnet run -- \
            --hazelcast:clusterName=$CLUSTERNAME --hazelcast:networking:addresses:0=$CLUSTERADDR \
            --submit:source=$SOURCE \
            --submit:define:DOTNET_DIR=$DEMO/dotnet-demo/dotnet-$USERCODE_TRANSPORT/publish/self-contained
    )
}

function example () {

    # run the example
    (
        cd jex-dotnet/dotnet-example
        dotnet run -- \
            --hazelcast:clusterName=$CLUSTERNAME --hazelcast:networking:addresses:0=$CLUSTERADDR)
}

function test_grpc () {
    (
        cd jex-dotnet/dotnet-grpc-client
        dotnet run 
    )
}

# (ensure a standard Hazelcast server is running)
#$CLZ start

# verify that the job runs
#$CLC job list

# cancel the job with
#$CLC job cancel my-job

# example should run OK
# also verify the server log

# see 
# https://stackoverflow.com/questions/3898665/what-is-in-bash
# https://www.thegeekstuff.com/2010/05/bash-shell-special-parameters/

CMDS=$1
shift
for cmd in $(IFS=,;echo $CMDS); do
    cmd=${cmd//-/_}
    echo "DEMO: $cmd $@"
    eval $cmd $@
    if [ $? -ne 0 ]; then break; fi
done