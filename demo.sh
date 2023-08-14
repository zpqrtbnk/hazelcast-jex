
function init () {
    # initialize
    export DEMO=/c/Users/sgay/Code/hazelcast-jet-dotnet
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

function build_dotnet () {
    # build the Hazelcast .NET client
    # includes the new Hazelcast.Net.Jet NuGet package
    # and cleanup the package cache because we are not changing the version
    (cd hazelcast-csharp-client &&
        pwsh ./hz.ps1 build,pack-nuget &&
        rm -rf ~/.nuget/packages/hazelcast.net &&
        rm -rf ~/.nuget/packages/hazelcast.net.jet)
}

function build_demo () {

    # build the demo code
    # * a 'common' project = a library used by other projects
    # * a 'service' project = the server-side .NET code
    # * a 'submit' project = submits the job (eventually, will do with CLC)
    # * a 'example' project = the client-side .NET code

    # build the dotnet service that runs the transform
    (cd dotnet-demo && 
        dotnet build)

    # publish the service for the platforms we want to support
    # for now, we publish 'target' which are single-file executables (but require that .NET is installed)
    #                 and 'target-sc' which are self-contained executables (include .NET)
    for platform in win-x64 linux-x64 osx-arm64; do
    (cd dotnet-demo/dotnet-service &&
        dotnet publish -c Release -r $platform -o target/$platform --no-self-contained &&
        dotnet publish -c Release -r $platform -o target-sc/$platform --self-contained)
    done      
}

function submit () {
    # submit the job (the dotnet way)
    # (eventually, this should be done by CLC)
    # submit:source points to the yaml file
    # submit:yaml:* provides replacement for %TOKEN% in the yaml file
    (cd dotnet-demo/dotnet-submit &&
        dotnet run -- --hazelcast.clusterName=$CLUSTERNAME --hazelcast.networking.addresses.0=$CLUSTERADDR \
                    --submit:source=$DEMO/dotnet-demo/my-job-2.yml \
                    --submit:define:DOTNET_DIR=$DEMO/dotnet-demo/dotnet-service/target-sc)
}

function example () {
    # run the example
    (cd dotnet-demo/dotnet-example && 
        dotnet run -- --hazelcast.clusterName=$CLUSTERNAME --hazelcast.networking.addresses.0=$CLUSTERADDR)
}

# (ensure a standard Hazelcast server is running)
#$CLZ start

# verify that the job runs
#$CLC job list

# cancel the job with
#$CLC job cancel my-job

# example should run OK
# also verify the server log

CMDS=$1
for cmd in $(IFS=,;echo $CMDS); do
    cmd=${cmd//-/_}
    echo "DEMO: $cmd"
    eval $cmd $@
    if [ $? -ne 0 ]; then die; fi
done