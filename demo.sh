#
# HAZELCAST JEX DEMO SCRIPT
#

# run '. ./demo.sh init' in order to initialize the demo environment

# NOTE
# add '--entrypoint /bin/bash' to override entrypoint and inspect the content of a container
# forward ports: kc port-forward --namespace default runtime-controller-68cc497fcb-bk56w 50051:50051
# shell into a k8 pod: kc exec -it hazelcast-0 -- /bin/bash


function init () {

    # NOTE
    # avoid editing demo.sh (and commiting changes to source revision)
    # instead, create a demo.sh.user file alongside demo.sh with only
    # the required changes

    # --- configure environment ---
    export DEMO=/path/to/hazelcast-jex # path to the demo root
    export MVN=mvn # name of Maven executable, can be 'mvn' or a full path
    export CLUSTERNAME=dev
    #export CLUSTERADDR=localhost:5701
    export CLUSTERADDR=192.168.1.200:5701
    export HZVERSION=5.4.0-SNAPSHOT # the version we're branching from
    export HZVERSION_DOCKER=5.3.2 # the base version we'll pull from docker
    export LOGGING_LEVEL=DEBUG
    export DOCKER_REPOSITORY=zpqrtbnk # repo name of our temp images
    export DOCKER_NETWORK=jex # the network name for our demo
    export MVN=mvn # name of Maven executable, can be 'mvn' or a full path
    export HELM=helm # name of Helm executable, can be 'mvn' or a full path
    export SANDBOX_KEY= # Viridian sandbox key (do NOT set it here but in the .user file)
    export SANDBOX_SECRET= # Viridian sandbox secret (same)
    # --- configure environment ---

    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
    if [ -f "$SCRIPT_DIR/demo.sh.user" ]; then
        source "$SCRIPT_DIR/demo.sh.user"
    fi

    export CLI=$DEMO/hazelcast/distribution/target/hazelcast-$HZVERSION/bin/hz-cli
    export CLZ=$DEMO/hazelcast/distribution/target/hazelcast-$HZVERSION/bin/hz
    export CLC="$DEMO/hazelcast-commandline-client/build/clc --config $DEMO/temp/clc-config.yml"
    export VRD=$DEMO/vrd/build/vrd
    export HAZELCAST_CONFIG=$DEMO/hazelcast-cluster.xml
    export PYTHON=python3 # linux
    if [ "$OSTYPE" == "msys " ]; then
        export PYTHON=python # windows
    fi

    #if [ -n "$SANDBOX_KEY" ]; then
    #    export CLC_VIRIDIAN_API_KEY=$SANDBOX_KEY
    #    export CLC_VIRIDIAN_API_SECRET=$SANDBOX_SECRET
    #fi

    if [ ! -d $DEMO/temp ]; then
        mkdir $DEMO/temp
    fi

    cat <<EOF > $DEMO/temp/clc-config.yml
cluster:
  name: $CLUSTERNAME
  address: $CLUSTERADDR
EOF

    $HELM repo add hzcharts https://hazelcast-charts.s3.amazonaws.com/

    alias demo=./demo.sh
    alias clz=$CLZ
    alias clc=$CLC
    alias helm=$HELM
    alias mvn=$MVN
    alias kc=kubectl
    alias dk=docker
    alias kca='kubectl get all'
    alias vrd=$VRD
    alias vrdlogin="$VRD --api-key $SANDBOX_KEY --api-secret $SANDBOX_SECRET login"

    # Bash on Windows may produce paths such as /c/path/to/lib and Java wants c:\path\to\lib
    # and, in this case, the cygpath command *should* be available - and then we will use it
    export CYGPATH=""
    if [ "$(command -v cygpath)" != "" ]; then
        export CYGPATH=cygpath
    fi
	
    export DEMO_COMMANDS=$(grep -E '^function\s[A-Za-z0-9_]*\s' demo.sh \
                             | cut -d " " -f 2\
                             | grep -E -v 'abspath|init' \
                          )
    complete -F _demo demo

    echo "configured with:"
    echo "    cluster name '$CLUSTERNAME'"
    echo "    member at '$CLUSTERADDR'"
    echo "initialized the following aliases:"
    echo "    demo: invokes the demo script"
    echo "    clc:  invokes the clc with the demo config"
    echo "    clz:  invokes the cluster hz script"
    echo "    vrd:  invokes vrd"
    echo "    mvn:  invokes Maven"
    echo "    helm: invokes Helm"
    echo "enjoy!"
    echo ""
}

function _demo() {
    local cur
    # COMP_WORDS is an array containing all individual words in the current command line
    # COMP_CWORD is the index of the word contianing the current cursor position
    # COMPREPLY is an array variable from which bash reads the possible completions
    cur=${COMP_WORDS[COMP_CWORD]}
    cur=${cur//-/_} # can use - or _
    COMPREPLY=()
    # compgen returns the array of elements from $DEMO_COMMANDS matching the current word
    COMPREPLY=( $( compgen -W "$DEMO_COMMANDS" -- $cur ) )
    return 0
}

function abspath () {
    (cd $(dirname $1); echo "$(pwd)/$(basename $1)")
}

# build the Hazelcast CLC (Go) project (in its submodule)
function build_clc () {
    (cd hazelcast-commandline-client &&
        CLC_VERSION=UNKNOWN
        GIT_COMMIT=
        LDFLAGS=""
        LDFLAGS="$LDFLAGS -X 'github.com/hazelcast/hazelcast-commandline-client/internal.GitCommit=$GIT_COMMIT'"
        LDFLAGS="$LDFLAGS -X 'github.com/hazelcast/hazelcast-commandline-client/internal.Version=$CLC_VERSION '"
        LDFLAGS="$LDFLAGS -X 'github.com/hazelcast/hazelcast-go-client/internal.ClientType=CLC'"
        LDFLAGS="$LDFLAGS -X 'github.com/hazelcast/hazelcast-go-client/internal.ClientVersion=$CLC_VERSION'"
        if [ "$OSTYPE" == "msys " ]; then
            go-winres make --in extras/windows/winres.json --product-version=$CLC_VERSION --file-version=$CLC_VERSION --out cmd/clc/rsrc
        fi
        go build -tags base,hazelcastinternal,hazelcastinternaltest -ldflags "$LDFLAGS" -o build/clc ./cmd/clc
    )
}

# build the Hazelcast OS (Java) project (in its submodule)
function build_cluster_os () {
    (
        cd hazelcast
        $MVN clean install -DskipTests -Dcheckstyle.skip=true
        cd distribution/target
        rm -rf hazelcast-$HZVERSION
        unzip hazelcast-$HZVERSION.zip
    )
}

# build the Hazelcast EE (Java) project (in its submodule)
function build_cluster_ee () {
    (
        cd hazelcast-enterprise
        $MVN -Pquick clean install
        cp hazelcast-enterprise-usercode/target/hazelcast-enterprise-usercode-$HZVERSION.jar \
           ../hazelcast/distribution/target/hazelcast-$HZVERSION/lib 
    )
}

# build the Hazelcast EE (Java) project (in its submodule)
function build_cluster_ee_nlc () {
    (
        cd hazelcast-enterprise
        $MVN -Pquick -Pno-license-checker-build clean install
        cd distribution/target
        rm -rf hazelcast-enterprise-$HZVERSION
        unzip hazelcast-enterprise-$HZVERSION.zip
        cd ../..
        cp hazelcast-enterprise-usercode/target/hazelcast-enterprise-usercode-$HZVERSION.jar \
           distribution/target/hazelcast-enterprise-$HZVERSION/lib 
    )
}

# build the Hazelcast .NET (C#) client project (in its submodule)
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

# build the various .NET projects used for the demo
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

# builds the Hazelcast cluster (OS+EE) Docker image
function dk_cluster_build () {

    dk_cluster_build_image $DOCKER_REPOSITORY/hazelcast:$HZVERSION_DOCKER
	
    docker tag $DOCKER_REPOSITORY/hazelcast:$HZVERSION_DOCKER $DOCKER_REPOSITORY/hazelcast:latest
    docker push $DOCKER_REPOSITORY/hazelcast:latest

    DEVTAG=dev.2
    docker tag $DOCKER_REPOSITORY/hazelcast:$HZVERSION_DOCKER $DOCKER_REPOSITORY/hazelcast:$DEVTAG
    docker push $DOCKER_REPOSITORY/hazelcast:$DEVTAG
}

function dk_quay_build () {

    #IMAGE=quay.io/hz_stephane/hazelcast_dev:stephane.gay
    IMAGE=quay.io/hazelcast_cloud/hazelcast-dev:stephane.gay
    dk_cluster_build_image_ee $IMAGE
    docker login -u $QUAY_USER -p $QUAY_PASSWORD quay.io
    docker push $IMAGE
}

function dk_cluster_build_image () {

    # build hazelcast image
    # from an existing official version (HZVERSION_DOCKER)
    # which we overwrite with our temp version (HZVERSION) files
	
    BUILD_CONTEXT=$DEMO/temp/docker-build-context
    if [ -d $BUILD_CONTEXT ]; then
        rm -rf $BUILD_CONTEXT
    fi
    mkdir $BUILD_CONTEXT
	
    cp hazelcast/distribution/target/hazelcast-$HZVERSION/lib/*.jar $BUILD_CONTEXT
    cp hazelcast-cluster-k8.xml $BUILD_CONTEXT/hazelcast.xml
    ls $BUILD_CONTEXT
    echo ""
	
    docker build \
        -t $1 \
        -f jobs/hazelcast.dockerfile \
        --build-arg="HZVERSION=$HZVERSION_DOCKER" \
        $BUILD_CONTEXT
		
    rm -rf $BUILD_CONTEXT
}

function dk_cluster_build_image_ee () {

    # build hazelcast EE image from scratch
    # from our own build of OS and EE for our temp version (HZVERSION)
	
    BUILD_CONTEXT=$DEMO/temp/docker-build-context
    if [ -d $BUILD_CONTEXT ]; then
        rm -rf $BUILD_CONTEXT
    fi
    mkdir $BUILD_CONTEXT

    # copy distribution from EE as expected by dockerfile
    cp hazelcast-enterprise/distribution/target/hazelcast-enterprise-$HZVERSION.zip \
       $BUILD_CONTEXT/hazelcast-enterprise-distribution.zip

    # for some silly reason that JAR is not in the distribution at the moment
    mkdir $BUILD_CONTEXT/lib
    cp hazelcast-enterprise/hazelcast-enterprise-usercode/target/hazelcast-enterprise-usercode-$HZVERSION-nlc.jar \
       $BUILD_CONTEXT/lib/

    # copy our own configuration file
    cp dk8/hazelcast-ee.xml \
       $BUILD_CONTEXT/hazelcast-usercode.xml

    # copy hazelcast-docker stuff
    cp -r hazelcast-docker/hazelcast-enterprise/* $BUILD_CONTEXT/

    ls -lR $BUILD_CONTEXT
    echo ""
	
    docker build \
        -t $1 \
        -f dk8/hazelcast-ee.dockerfile \
        --build-arg="HZVERSION=$HZVERSION_DOCKER" \
        $BUILD_CONTEXT
		
    rm -rf $BUILD_CONTEXT
}

# executes the python runtime as a process
# can be useful to test with the passthru runtime service
function runtime_python () {

    (
        VENV_PATH=$PWD/temp
        cd jex-python/python-grpc/publish/any
        $PYTHON usercode-runtime.py --grpc-port 5252 --venv-path=$VENV_PATH --venv-name=python-venv
    )
}

# executes the .NET+gRPC runtime as a process
# can be useful to test with the passthru runtime service
function runtime_dotnet_grpc () {
    (
        cd jex-dotnet/dotnet-grpc
        dotnet run
    )
}

# build the Python runtime Docker images
function dk_runtime_python_build () {

    # build a base image
    docker build \
        -t $DOCKER_REPOSITORY/python-usercode-base:latest \
        -f hazelcast-usercode/python/docker/dockerfile.base \
        hazelcast-usercode/python

	docker push $DOCKER_REPOSITORY/python-usercode-base:latest

    # build an example image (with actual usercode included)
    docker build \
        -t $DOCKER_REPOSITORY/python-usercode:latest \
        -f hazelcast-usercode/python/docker/dockerfile.example \
        hazelcast-usercode/python/example

	docker push $DOCKER_REPOSITORY/python-usercode:latest
}

# build the Dotnet runtime Docker images
function dk_runtime_dotnet_build () {

    # meh: build usercode vs usercode-base?

	docker build \
		-t $DOCKER_REPOSITORY/dotnet-usercode:latest \
		-f jobs/dotnet-container-grpc.dockerfile \
		jex-dotnet/dotnet-grpc/publish/single-file/linux-x64

    docker push $DOCKER_REPOSITORY/dotnet-usercode:latest 
}

# initialize Docker (custom network...)
function dk_initialize () {

	docker network ls | grep -q $DOCKER_NETWORK
	if [ $? -eq 1 ]; then
		docker network create $DOCKER_NETWORK
	fi
}

# run the docker member
function dk_cluster_run () {

	# removed:
	#   -v $DEMO/hazelcast-cluster.xml:/opt/hazelcast/hazelcast.xml \
	# configuration is now copied into the image when building
	# because it's hard to map a file in k8 setup (see hazelcast.dockerfile)
    #
    # BUT
    # this is not true, we use helm and charts and stuff, so this below
    # probably does not work, meh

	docker run --rm -it --net jex \
		-p 5701:5701 \
		--name member0 -h member0 \
		-e HAZELCAST_CONFIG=/data/hazelcast/hazelcast.xml \
		-e HZ_CLUSTERNAME=dev \
		-e HZ_RUNTIME_CONTROLLER_ADDRESS=10.106.74.139 \
		-e HZ_RUNTIME_CONTROLLER_PORT=50051 \
		$DOCKER_REPOSITORY/hazelcast:$HZVERSION_DOCKER
}

# start the k8 runtime controller
function k8_controller_start () {
	$HELM upgrade --install runtime-controller user-code-runtime/charts/runtime-controller
}

# stop the k8 runtime controller
function k8_controller_stop () {
	$HELM delete runtime-controller
}

# start the k8 cluster
function k8_cluster_start () {
	# beware! 
	# HZ_RUNTIME_CONTROLLER_ADDRESS/PORT configured in pod-...yaml
	#kubectl apply -f k8/service-hz-hazelcast.yaml
	#kubectl apply -f k8/pod-hz-hazelcast.yaml
	$HELM install hazelcast hzcharts/hazelcast \
		-f jobs/member-values.yaml
	
	# no idea how to get these to work => coded into values.yaml	
	#--set env.enabled=true \
	#--set env.vars.HAZELCAST_CONFIG=hazelcast.xml \
	#--set env.vars.HZ_CLUSTERNAME=dev \
	#--set env.vars.HZ_RUNTIME_CONTROLLER_ADDRESS=runtime-controller \
	#--set env.vars.HZ_RUNTIME_CONTROLLER_PORT=50051 \

}

# stop the k8 cluster
function k8_cluster_stop () {
	#kubectl delete service/hz-hazelcast-0 pod/hz-hazelcast-0
	#kubectl delete -f k8/pod-hz-hazelcast.yaml
	#kubectl delete -f k8/service-hz-hazelcast.yaml
	$HELM delete hazelcast
}

# get the k8 cluster logs
function k8_cluster_logs () {
	kubectl logs hazelcast-0
}

function k8_get () {
	kubectl get pod --output=wide
	kubectl get svc
}

# run the Python runtime via Docker (for passthru)
function dk_runtime_python_run () {

	# BEWARE!
    # the job need to know the address of the gRPC runtime server

    #IMAGE=$DOCKER_REPOSITORY/python-usercode
    IMAGE=$DOCKER_REPOSITORY/python-usercode-base

	docker run --rm -it --net jex \
		-p 5252:5252 \
		--name runtime -h runtime \
        $IMAGE
}

# run the Dotnet runtime via Docker (for passthru)
function dk_runtime_dotnet_run () {

	# BEWARE!
    # the job need to know the address of the gRPC runtime server

    IMAGE=$DOCKER_REPOSITORY/dotnet-usercode-base

	docker run --rm -it --net jex \
		-p 5252:5252 \
		--name runtime -h runtime \
        $IMAGE
}

# run a temp sh Docker container
function dk_sh () {

	docker run -it --rm --net jex \
		--name tempsh -h tempsh \
		busybox sh
}

# submit jobs, the .NET way
# OBSOLETE - should use the CLC now, e.g.:
# clc job submit jobs/dotnet-shmem.yml DOTNET_DIR=$DEMO/jex-dotnet/dotnet-shmem/publish/self-contained
# clc job submit jobs/dotnet-grpc.yml DOTNET_DIR=$DEMO/jex-dotnet/dotnet-grpc/publish/self-contained
# clc job submit jobs/python-grpc.yml PYTHON_DIR=$DEMO/jex-python/python-grpc/publish
# OBSOLETE - and, even that usage of CLC is using our own CODEC etc
function jet_submit_dotnet_OBSOLETE () {

    # examples
    # demo submit shmem jobs/dotnet-shmem.yml
    # demo submit grpc jobs/dotnet-grpc.yml
    # demo submit grpc jobs/python-grpc.yml


    TRANSPORT=$1    
    SOURCE=$2
    if [ -z "$TRANSPORT" ]; then echo "transport?"; return; fi
    if [ -z "$SOURCE" ]; then echo "source?"; return; fi
    SOURCE=$(abspath $SOURCE)
    echo "DEMO: submit $TRANSPORT $SOURCE" 

    if [ ! -f $SOURCE ]; then
        echo "ERR: file not found"
        return
    fi

    # submit the job (the dotnet way)
    # (eventually, this should be done by CLC)
    # submit:source points to the yaml file
    # submit:define:* provides replacement for $TOKEN in the yaml file
    (
        cd jex-dotnet/dotnet-submit
        dotnet run -- \
            --hazelcast:clusterName=$CLUSTERNAME --hazelcast:networking:addresses:0=$CLUSTERADDR \
            --submit:source=$SOURCE \
            --submit:define:DOTNET_DIR=$DEMO/jex-dotnet/dotnet-$TRANSPORT/publish/self-contained \
            --submit:define:PYTHON_DIR=$DEMO/jex-python/python-grpc/publish
    )
}

# run the demo example
# (puts stuff into a map and expects stuff to appear in another map)
function run_example () {

    # run the example
    (
        cd jex-dotnet/dotnet-example
        dotnet run -- \
            --hazelcast:clusterName=$CLUSTERNAME --hazelcast:networking:addresses:0=$CLUSTERADDR
	)
}

# test a gRPC runtime
function test_grpc () {
    (
        cd jex-dotnet/dotnet-grpc-client
        dotnet run 
    )
}

# build the Java submit JAR
function build_jet_submit_java () {
    (
        cd jex-java/java-pipeline
        $MVN clean package
    )
}

# submit a job via Java
function jet_submit_java () {
    (
        PIPELINE=java-pipeline-viridian
        #HZHOME=$DEMO/hazelcast/distribution/target/hazelcast-5.4.0-SNAPSHOT
        HZHOME=$DEMO/hazelcast-enterprise/distribution/target/hazelcast-enterprise-5.4.0-SNAPSHOT
        TARGET=$DEMO/jex-java/$PIPELINE/target
        CLASSPATH="$TARGET/python-jet-usercode-1.0-SNAPSHOT.jar:$HZHOME/lib:$HZHOME/lib/*"

        # trim CLASSPATH
        CLASSPATH="${CLASSPATH##:}"
        CLASSPATH="${CLASSPATH%%:}"

        # ensure CLASSPATH is windows style on Windows
        if [ -n "${CYGPATH}" ]; then
            CLASSPATH=$(cygpath -w -p "$CLASSPATH")
        fi

        # execute
        # -verbose:class
        java -classpath $CLASSPATH org.example.PythonJetUserCode
    )
}

CMDS=$1

if [ -z "$CMDS" ]; then
	echo "Uh, what am I supposed to do?"
	exit
fi

shift
for cmd in $(IFS=,;echo $CMDS); do
    cmd=${cmd//-/_}
    echo "DEMO: $cmd $@"
    eval $cmd $@
    if [ $? -ne 0 ]; then break; fi
done
