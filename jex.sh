#
# HAZELCAST JEX JEX SCRIPT
#

# USAGE:
# 1. copy the configuration part (see below) into a 'jex.sh.user'
#    file and configure the various parts with your own values
# 2. run 'source jex.sh' once to initialize the environment and
#    register the 'jex' alias
# 3. now you can run 'jex help' to list available commands

if [ -z "$BASH_VERSION" ]; then
    echo "ERR: this script must run under bash"
    return 0
fi

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
export JEX=$SCRIPT_DIR

# include the jex.sh.user file, if it exists
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
if [ -f "$SCRIPT_DIR/jex.sh.user" ]; then
    source "$SCRIPT_DIR/jex.sh.user"
else
    echo "warn: Could not find script jex.sh.user, I am creating"
    echo "a dummy one for you, but you MUST edit it in order to"
    echo "configure me, else I cannot work!"
    echo ""
    cat <<EOF >"$SCRIPT_DIR/jex.sh.user"
#
# CONFIGURE JEX
#

# What Hazelcast version are we building?
HZVERSION=5.4.0-SNAPSHOT

# Where is Maven?
export MVN=mvn

# Where is Helm? Leave empty if you don't have Helm.
export HELM=

# Configure the Viridian API, key and secret
export SANDBOX_API=https://api.sandbox.viridian.hazelcast.cloud
export SANDBOX_KEY=
export SANDBOX_SECRET=

# Configure the Quay account
export QUAY_USER=
export QUAY_PASSWORD=

# Configure the Viridian cluster
# The name is the actual name you gave to the cluster, not its 'code'
# The tag is firstname.lastname (the tag of your Quay cluster image)
export CLUSTER_NAME=
export CLUSTER_TAG=

# Configure Docker, for local runs
# Configure the Docker repository where your images will be pushed
DOCKER_REPOSITORY=
# Configure a Docker network, or leave empty to use the default network
DOCKER_NETWORK=

# If you want to run locally, or on a local Kubernetes,
# you will need to use the license-checking EE build,
# and then you need to provide an EE license.
export HZ_LICENSEKEY=

# Do you want to enable the experimental job builder?
# Hint: you probably do NOT want to enable it.
# Any non-empty value means 'true'.
JOBBUILDER=

# These will be documented, eventually - don't touch them
export CLUSTERNAME=dev
export CLUSTERADDR=localhost:5701
export LOGGING_LEVEL=DEBUG
export HAZELCAST_CONFIG=$JEX/config/hazelcast-cluster.xml

EOF

fi

export CLI=$JEX/hazelcast-enterprise/distribution/target/hazelcast-enterprise-$HZVERSION/bin/hz-cli
export CLZ=$JEX/hazelcast-enterprise/distribution/target/hazelcast-enterprise-$HZVERSION/bin/hz
export CLC=$JEX/clc/build/clc
export VRD=$JEX/vrd/build/vrd


# bash can only return from a function OR top-level sourced script
# note: this will not work on non-bash shells!
(return 0 2>/dev/null) && SOURCED=1 || SOURCED=0


# source the script to initialize it
_initialize () {

    export PYTHON=python3 # linux
    if [ "$OSTYPE" == "msys" ]; then
        export PYTHON=python # windows
    fi

    if [ ! -d $JEX/temp ]; then
        mkdir $JEX/temp
    fi

    if [ -n "$HELM" ]; then
        $HELM repo list | grep -q hzcharts
        if [ $? == 1 ]; then
            $HELM repo add hzcharts https://hazelcast-charts.s3.amazonaws.com/
        else
            $HELM repo update hzcharts
        fi
    fi

    alias jex=$JEX/jex.sh
    alias clz=$CLZ
    alias clc=$CLC
    alias helm=$HELM
    alias mvn=$MVN
    alias kc=kubectl
    alias dk=docker
    alias kca='kubectl get all'
    alias vrd=$VRD
    alias crd="$CLC viridian"
    #alias vrdlogin="$VRD --api-key $SANDBOX_KEY --api-secret $SANDBOX_SECRET login"
    #alias crdlogin="$CLC viridian --api-key $SANDBOX_KEY --api-secret $SANDBOX_SECRET --api-base $SANDBOX_API login"

    # Bash on Windows may produce paths such as /c/path/to/lib and Java wants c:\path\to\lib
    # and, in this case, the cygpath command *should* be available - and then we will use it
    export CYGPATH=""
    if [ "$(command -v cygpath)" != "" ]; then
        export CYGPATH=cygpath
    fi
	
    # before gettings commands!
    export JEX_INITIALIZED=jex

    # see below, all attempts at dynamically doing this have failed so far
    JEX_COMMANDS=$( ./${BASH_SOURCE[0]} -commands )
    complete -F _jex_complete jex

    echo "Initialized. You can now use the 'jex' alias."
}


# source the script once to initialize it all
if [ $SOURCED == 1 ]; then
    _initialize
elif [ -z "$JEX_INITIALIZED"  ]; then
    echo "WARN: JEX has not been initialized yet."
    echo "Initialize JEX by running: 'source jex.sh' once."
    exit
fi


_commands () { echo $( declare -F | cut -d " " -f 3 | grep -ve '^_' | sort ); }


__help () { echo "Display JEX help"; }
help() {
    declared=$( declare -F | sed 's/declare -f //g' )
    declared=$( echo $declared | sed 's/ /@/g' )
	for i in $( _commands ); do
        if [[ "@$declared@" == *"@__$i@"* ]]; then
			d=$( __$i )
		else
			d="?"
		fi
        echo -e "${i//_/-}\t$d\n"
	done | column -t -s $'\t'
}


_jex_meh () {
    compgen -W "$1" -- $2 | sed 's/_/-/g'
}

_jex_complete () {
    # this runs local to the invoking script
    local cur
    # COMP_WORDS is an array containing all individual words in the current command line
    # COMP_CWORD is the index of the word containing the current cursor position
    # COMPREPLY is an array variable from which bash reads the possible completions
    cur=${COMP_WORDS[COMP_CWORD]}
    cur=${cur//-/_} # make sure we use _ for completion (but we'll print with -)
    COMPREPLY=()
    # compgen returns the array of elements from input matching the current word
    COMPREPLY=( $( compgen -W "$JEX_COMMANDS" -- $cur | sed 's/_/-/g' ) )
    #COMPREPLY=($(
        # any attempt at dynamically getting the commands fail
        # we can run a python script here, fine, but soon as we run a sh script, bang
        #cmds=$( ${BASH_SOURCE[0]} -commands ) # this fails
        #compgen -W "$cmds" -- $cur | sed 's/_/-/g'
    #))
    return 0
}


_abspath () {
    (cd $(dirname $1); echo "$(pwd)/$(basename $1)")
}


_classpath () {

    CLASSPATH=$1

    # trim CLASSPATH
    CLASSPATH="${CLASSPATH##:}"
    CLASSPATH="${CLASSPATH%%:}"

    # ensure CLASSPATH is windows style on Windows
    if [ -n "${CYGPATH}" ]; then
        CLASSPATH=$(cygpath -w -p "$CLASSPATH")
    fi

    echo $CLASSPATH
}


__enable_journal () { echo "Enables journal map via dynamic configuration (wip)"; }
enable_journal () {(
    cd jex-dotnet/dotnet-enable-journal
    CONFIG_ID=$1
    CLCHOME=$($CLC home)
    dotnet run -- $CLCHOME/configs/$CONFIG_ID
)}


__list_submodules () { echo "List the submodules"; }
list_submodules () {
    result=$(\
    git submodule foreach --quiet '\
        sha0=$( git -C .. ls-tree HEAD | grep -E "$sm_path\$" | cut -d \  -f 3 | cut -c-7 ) ;\
        sha1=$( git rev-parse HEAD | cut -c-7 ) ;\
        dirty="OK" ;\
        if [ "$sha0" != "$sha1" ]; then dirty="WARN"; fi ;\
        echo -n "$sm_path $sha0 $sha1 $dirty--NL--" ;\
    ')
    text="SUBMODULE TARGET CURRENT STATE--NL--$result"
    text=$(echo $text | sed 's/--NL--/\\n/g')
    echo -e $text | column -t -s ' '
}


__login_viridian () { echo "Log into Viridian Sandbox"; }
login_viridian () {
    $CLC viridian --api-base $SANDBOX_API --api-key $SANDBOX_KEY --api-secret $SANDBOX_SECRET login
}


__create_viridian_cluster () { echo "Create the Viridian cluster"; }
create_viridian_cluster () {
    NAME=$1
    if [ -z "$NAME" ]; then
        echo "missing cluster name"
        return
    fi
    $VRD create-cluster --name $NAME --image-tag $CLUSTER_TAG --hz-version 5.4.0 --timeout 3m
    $CLC viridian import-config $NAME
}


__build_clc () { echo "Build the CLC project"; }
build_clc () {(
    cd clc
    CLC_VERSION=v0.0.0-CUSTOMBUILD
    GIT_COMMIT=$(git rev-parse HEAD 2> /dev/null || echo unknown)
    LDFLAGS="-s -w"
    LDFLAGS="$LDFLAGS -X 'github.com/hazelcast/hazelcast-commandline-client/internal.GitCommit=$GIT_COMMIT'"
    LDFLAGS="$LDFLAGS -X 'github.com/hazelcast/hazelcast-commandline-client/internal.Version=$CLC_VERSION '"
    LDFLAGS="$LDFLAGS -X 'github.com/hazelcast/hazelcast-go-client/internal.ClientType=CLC'"
    LDFLAGS="$LDFLAGS -X 'github.com/hazelcast/hazelcast-go-client/internal.ClientVersion=$CLC_VERSION'"
    if [ "$OSTYPE" == "msys" ]; then
        echo "go-winres make"
        go-winres make --in extras/windows/winres.json --product-version=$CLC_VERSION --file-version=$CLC_VERSION --out cmd/clc/rsrc
    fi
    echo "go build"
    go build -tags base,std,hazelcastinternal,hazelcastinternaltest -ldflags "$LDFLAGS" -o build/clc ./cmd/clc
)}



__build_vrd () { echo "Build the VRD project"; }
build_vrd () {(
    cd vrd
    CLC_VERSION=v0.0.0-CUSTOMBUILD
    GIT_COMMIT=$(git rev-parse HEAD 2> /dev/null || echo unknown)
    LDFLAGS="-s -w"
    LDFLAGS="$LDFLAGS -X 'github.com/hazelcast/hazelcast-commandline-client/clc/cmd.MainCommandShortHelp=Viridian Deploy Tool'"
    LDFLAGS="$LDFLAGS -X 'github.com/hazelcast/hazelcast-commandline-client/internal.GitCommit=$GIT_COMMIT'"
    LDFLAGS="$LDFLAGS -X 'github.com/hazelcast/hazelcast-commandline-client/internal.Version=$CLC_VERSION '"
    LDFLAGS="$LDFLAGS -X 'github.com/hazelcast/hazelcast-go-client/internal.ClientType=CLC'"
    LDFLAGS="$LDFLAGS -X 'github.com/hazelcast/hazelcast-go-client/internal.ClientVersion=$CLC_VERSION'"
    LDFLAGS="$LDFLAGS -X 'github.com/hazelcast/hazelcast-commandline-client/internal/viridian.EnableInternalOps=yes'"
    if [ "$OSTYPE" == "msys" ]; then
        echo "go-winres make"
        go-winres make --in extras/windows/winres.json --product-version=$CLC_VERSION --file-version=$CLC_VERSION --out cmd/clc/rsrc
    fi
    echo "go build"
    CGO_ENABLED=0 go build -tags base,viridian,hazelcastinternal,hazelcastinternaltest -ldflags "$LDFLAGS" -o build/vrd ./cmd/clc
)}


__build_dk_controller () { echo "Build the Runtime Controller project and Docker image"; }
build_dk_controller () {(
    cd user-code-runtime

    CHART=charts/runtime-controller/Chart.yaml
    VALUES=charts/runtime-controller/values.yaml

    REPOSITORY=$($PYTHON scripts/repository.py $VALUES)
    VERSION=$($PYTHON scripts/version.py $CHART)

    # the Quay build - NOT what we want here!
    #docker build -t $REPOSITORY:$VERSION .

    # local build
    docker build -t $DOCKER_REPOSITORY/runtime-controller:$VERSION .
)}


__build_cluster_os () { echo "Build the Hazelcast OS project"; }
build_cluster_os () {(
    cd hazelcast

    $MVN clean install -DskipTests -Dcheckstyle.skip=true
)}


__build_cluster_ee () { echo "Build the Hazelcast EE project (with license check)"; }
build_cluster_ee () {(
	_build_cluster_ee
)}


__build_cluster_ee_nlc () { echo "Build the Hazelcast EE project (no license check)"; }
build_cluster_ee_nlc () {(
	_build_cluster_ee NLC
)}


_build_cluster_ee () {(

    # configure for license check
    NLC=""
    MVNLC=""
    if [ "$1" == "NLC" ]; then
      NLC="-nlc"
      MVNLC="-Pno-license-checker-build"
    fi

    # -nsu = no snapshot update (won't fetch latest snapshot of OS from network, use our local one!)
    cd hazelcast-enterprise
    $MVN -nsu -Pquick $MVNLC clean install
    if [ $? -ne 0 ]; then
        echo "ERR: Maven failed to build"
        return 1
    fi
    cd distribution/target
    rm -rf hazelcast-enterprise-$HZVERSION
    unzip hazelcast-enterprise-$HZVERSION.zip

    # temp for tests, setting LOGGING_LEVEL is too broad and verbose
    cat <<EOF >$JEX/hazelcast-enterprise/distribution/target/hazelcast-enterprise-$HZVERSION/config/log4j2.properties
logger.usercode.name=com.hazelcast.usercode
logger.usercode.level=$LOGGING_LEVEL
EOF

    # this file is not in the distribution
    cp $JEX/hazelcast-enterprise/hazelcast-enterprise-usercode/target/hazelcast-enterprise-usercode-$HZVERSION$NLC.jar \
       $JEX/hazelcast-enterprise/distribution/target/hazelcast-enterprise-$HZVERSION/lib 
)}


# build the Jet JobBuilder projet
__build_jobbuilder () { echo "Build the Jet JobBuilder project"; }
function build_jobbuilder () {(
    cd hazelcast-usercode/java/jet-job-builder
    $MVN -nsu clean install

    # merge into EE distribution
    cp $JEX/hazelcast-usercode/java/jet-job-builder/target/hazelcast-jet-jobbuilder-$HZVERSION.jar \
       $JEX/hazelcast-enterprise/distribution/target/hazelcast-enterprise-$HZVERSION/lib 
)}


# build the UserCode JobBuilder project
__build_jobbuilder_usercode () { echo "Build the UserCode JobBuilder project"; }
build_jobbuilder_usercode () {(
    cd hazelcast-usercode/java/usercode-job-builder
    $MVN -nsu clean install

    # merge into EE distribution
    cp $JEX/hazelcast-usercode/java/usercode-job-builder/target/hazelcast-usercode-jobbuilder-$HZVERSION.jar \
       $JEX/hazelcast-enterprise/distribution/target/hazelcast-enterprise-$HZVERSION/lib 
)}


__build_client_dotnet () { echo "Build the .NET client project"; }
build_client_dotnet () {(

    # build the Hazelcast .NET client, including the new packages
    # and cleanup the package cache because we are not bumping the version,
    # and we want to force projects that depend on the client to fetch the
    # updated dependency anyways
    cd hazelcast-csharp-client
    pwsh ./hz.ps1 build,pack-nuget
    rm -rf ~/.nuget/packages/hazelcast.net
    rm -rf ~/.nuget/packages/hazelcast.net.*
)}


__build_jex_dotnet () { echo "Build all the JEX .NET projects"; }
function build_jex_dotnet () {(

    # build the demo code
    # * a 'common' project = a library used by other projects
    # * a 'service' project = the server-side .NET code
    # * a 'submit' project = submits the job (eventually, will do with CLC)
    # * a 'example' project = the client-side .NET code

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
)}


__run_runtime_python () { echo "Run a Python runtime"; }
run_runtime_python () {(

    # code is provided
    #CODE_PATH=$JEX/hazelcast-usercode/python/example
    #CODE_NAME=usercode

    # code will be copied over
    CODE_PATH=!res ### how can we make it relative to <LATE-BINDING> ?
    CODE_NAME=usercode

    $PYTHON hazelcast-usercode/python/hazelcast_usercode serve \
        --server-mode=venv --venv-path=$JEX/temp --venv-name=python-venv \
        --code-path=$CODE_PATH --code-name=$CODE_NAME \
        --grpc-port 5252 --log-level=DEBUG
)}


__run_runtime_dotnet_grpc () { echo "Run a .NET runtime (gRPC)"; }
run_runtime_dotnet_grpc () {(

    cd jex-dotnet/dotnet-grpc
    dotnet run
)}


__run_dk_sh () { echo "Run a Docker busybox shell"; }
run_dk_sh () {

	docker run -it --rm --net jex \
		--name tempsh -h tempsh \
		busybox sh
}


__build_dk_cluster_local () { echo "Builder the cluster Docker image for local (requires non-NLC EE)"; }
build_dk_cluster_local () {

    # validate
    if [ ! -f "hazelcast-enterprise/hazelcast-enterprise-usercode/target/hazelcast-enterprise-usercode-$HZVERSION.jar" ]; then
        echo "Could not find the non-NLC enterprise JAR, are you sure you have build the EE project?"
        return 0
    fi

    IMAGE=$DOCKER_REPOSITORY/hazelcast:$HZVERSION

    _dk_cluster_prepare_image
    ls $JEX/temp/docker-source

    # build
    docker build \
        -t $IMAGE \
        -f dk8/hazelcast-ee.dockerfile \
        --build-arg="HZVERSION=$HZVERSION" \
        $DOCKER_SOURCE

    _dk_cluster_clear_image
	
    docker tag $DOCKER_REPOSITORY/hazelcast:$HZVERSION $DOCKER_REPOSITORY/hazelcast:latest
    docker push $DOCKER_REPOSITORY/hazelcast:latest
}


__build_dk_cluster_quay () { echo "Build the cluster Docker image for Quay (requires NLC EE)"; }
build_dk_cluster_quay () {(

    # validate
    if [ ! -f "hazelcast-enterprise/hazelcast-enterprise-usercode/target/hazelcast-enterprise-usercode-$HZVERSION-nlc.jar" ]; then
        echo "Could not find the NLC enterprise JAR, are you sure you have build the EE-NLC project?"
        return 0
    fi

    #IMAGE=quay.io/$QUAY_USER/hazelcast_dev:$CLUSTER_TAG
    IMAGE=quay.io/hazelcast_cloud/hazelcast-dev:$CLUSTER_TAG

    _dk_cluster_prepare_image

    # build and push (need to do both at once due to multi-platform)
    docker login -u $QUAY_USER -p $QUAY_PASSWORD quay.io
    docker buildx build --builder viridian --platform linux/amd64,linux/arm64 --push \
        -t $IMAGE \
        -f dk8/hazelcast-ee.dockerfile \
        --build-arg="HZVERSION=$HZVERSION" \
        $DOCKER_SOURCE

    _dk_cluster_clear_image
)}

_dk_cluster_prepare_image () {

    # build Hazelcast EE docker image from scratch
    # from our own build of OS and EE for version $HZVERSION

    DOCKER_SOURCE=$JEX/temp/docker-source
    if [ -d $DOCKER_SOURCE ]; then
        rm -rf $DOCKER_SOURCE
    fi
    mkdir $DOCKER_SOURCE

    ENTERPRISE=hazelcast-enterprise/distribution/target

    # copy distribution from EE as expected by dockerfile
    cp $ENTERPRISE/hazelcast-enterprise-$HZVERSION.zip $DOCKER_SOURCE/hazelcast-enterprise-distribution.zip

    # for some silly reason that JAR is not in the distribution at the moment
    mkdir $DOCKER_SOURCE/lib
    #ls hazelcast-enterprise/hazelcast-enterprise-usercode/target/hazelcast-enterprise-usercode-$HZVERSION*.jar
    cp hazelcast-enterprise/hazelcast-enterprise-usercode/target/hazelcast-enterprise-usercode-$HZVERSION*.jar $DOCKER_SOURCE/lib/

    # nor is that one
    if [ -n "$JOBBUILDER" ]; then
        cp $JEX/hazelcast-usercode/java/jet-job-builder/target/hazelcast-jet-jobbuilder-$HZVERSION.jar $DOCKER_SOURCE/lib/
        cp $JEX/hazelcast-usercode/java/usercode-job-builder/target/hazelcast-usercode-jobbuilder-$HZVERSION.jar $DOCKER_SOURCE/lib/
    fi

    # copy our own configuration file
    cp config/hazelcast-ee.xml $DOCKER_SOURCE/hazelcast-usercode.xml

    # copy hazelcast-docker stuff
    cp -r hazelcast-docker/hazelcast-enterprise/* $DOCKER_SOURCE/
}

_dk_cluster_buildx_image () {

    # build and push (need to do both at once due to multi-platform)
    docker buildx build --builder viridian --platform linux/amd64,linux/arm64 --push \
        -t $1 \
        -f dk8/hazelcast-ee.dockerfile \
        --build-arg="HZVERSION=$HZVERSION" \
        $DOCKER_SOURCE
}

_dk_cluster_clear_image () {		
    rm -rf $DOCKER_SOURCE
}


__build_dk_runtime_python () { echo "Build the Python runtime Docker images"; }
build_dk_runtime_python () {

    if [ -z "$1" ]; then
        echo "err: missing registry"
        return 1
    fi
    IMAGE_ROOT=$1
    shift

    IMAGE_SLIM=$IMAGE_ROOT/usercode-python-slim:latest
    IMAGE_ML=$IMAGE_ROOT/usercode-python-ml:latest
    IMAGE_SLIM_EXAMPLE=$IMAGE_ROOT/usercode-python-slim-example:latest

    # build and push images (need to do both at once due to multi-platorm)

    # build the slim base image
    docker buildx build --builder viridian --platform linux/amd64,linux/arm64 --push \
        -t $IMAGE_SLIM \
        -f hazelcast-usercode/python/docker/slim.dockerfile \
        hazelcast-usercode/python
        
    # todo: build a ML image with way more dependencies

    # build the slim+example (contains usercode) image
    docker buildx build --builder viridian --platform linux/amd64,linux/arm64 --push \
        -t $IMAGE_SLIM_EXAMPLE \
        --build-arg="FROMIMAGE=$IMAGE_SLIM" \
        -f hazelcast-usercode/python/docker/slim+example.dockerfile \
        hazelcast-usercode/python/example
}


__build_dk_runtime_dotnet () { echo "Build the .NET runtime Docker images (gRPC)"; }
build_dk_runtime_dotnet () {

    # meh: build usercode vs usercode-base?

	docker build \
		-t $DOCKER_REPOSITORY/dotnet-usercode:latest \
		-f jobs/dotnet-container-grpc.dockerfile \
		jex-dotnet/dotnet-grpc/publish/single-file/linux-x64

    docker push $DOCKER_REPOSITORY/dotnet-usercode:latest 
}

__dk_initialize () { echo "Initialize Docker (network, buildx...)"; }
dk_initialize () {

    if [ -n "$DOCKER_NETWORK" ]; then
    	docker network ls | grep -q $DOCKER_NETWORK
    	if [ $? -eq 1 ]; then
		    docker network create $DOCKER_NETWORK
	    fi
    fi

    docker buildx ls | grep -q viridian
    if [ $? -eq 1 ]; then
        docker buildx create --name viridian --driver docker-container 
    fi
}


__run_dk_cluster () { echo "Run a Docker cluster"; }
run_dk_cluster () {

	# removed:
	#   -v $JEX/hazelcast-cluster.xml:/opt/hazelcast/hazelcast.xml \
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
		$DOCKER_REPOSITORY/hazelcast:$HZVERSION
}


__run_dk_runtime_python () { echo "Run a Docker Python runtime"; }
run_dk_runtime_python () {

    # BEWARE! the job need to know the address of the gRPC runtime server

    # select the base or full image
    #IMAGE=$DOCKER_REPOSITORY/usercode-python-slim-example
    IMAGE=$DOCKER_REPOSITORY/usercode-python-slim

	docker run --rm -it --net jex \
		-p 5252:5252 \
		--name runtime -h runtime \
        $IMAGE
}


__run_dk_runtime_dotnet () { echo "Run a Docker .NET runtime (gRPC)"; }
run_dk_runtime_dotnet () {

	# BEWARE! the job need to know the address of the gRPC runtime server

    # select the base or full image
    #IMAGE=$DOCKER_REPOSITORY/dotnet-usercode
    IMAGE=$DOCKER_REPOSITORY/dotnet-usercode-base

	docker run --rm -it --net jex \
		-p 5252:5252 \
		--name runtime -h runtime \
        $IMAGE
}

__login_quay () { echo "Log into Quay and create the k8 secret"; }
login_quay () {

    docker login -u $QUAY_USER -p $QUAY_PASSWORD quay.io
    kubectl create secret generic quay-pull-secret \
        --from-file=.dockerconfigjson=$HOME/.docker/config.json \
        --type=kubernetes.io/dockerconfigjson
}


__start_k8_controller () { echo "Start the k8 runtime controller"; }
start_k8_controller () {

    # alt. helm install runtime-controller runtime-controller/runtime-controller --set ...
    # not entirely sure which is best - but with latest version we need to be logged into Quay
    $HELM upgrade --install runtime-controller user-code-runtime/charts/runtime-controller \
        --set imagePullSecrets[0].name=quay-pull-secret
}


__stop_k8_controller () { echo "Stop the k8 runtime controller"; }
stop_k8_controller () {

	$HELM delete runtime-controller
}


__restart_k8_cluster () { echo "Restart the k8 cluster"; }
restart_k8_cluster() {
    stop_k8_cluster
    start_k8_cluster
}


__start_k8_cluster () { echo "Start the k8 cluster"; }
start_k8_cluster () {

    # BEWARE! runtime controller address and port, etc in helm-ckyster.yaml 

    $HELM repo update

    $HELM install hazelcast hzcharts/hazelcast-enterprise \
        -f config/helm-cluster.yaml \
        --set hazelcast.licenseKey=$HZ_LICENSEKEY
}


__stop_k8_cluster () { echo "Strop the k8 cluster"; }
stop_k8_cluster () {

	$HELM delete hazelcast
}


__show_k8_cluster_logs () { echo "Show the k8 cluster logs"; }
show_k8_cluster_logs () {
	kubectl logs hazelcast-0
}


__show_k8 () { echo "Show the k8 state"; }
 show_k8 () {
	kubectl get pod --output=wide
	kubectl get svc
}


# submit jobs, the .NET way - OBSOLETE, should use CLC now and our .NET version is broken
function _OBSOLETE_submit_dotnet () {

    # examples
    # demo submit shmem jobs/dotnet-shmem.yml
    # demo submit grpc jobs/dotnet-grpc.yml
    # demo submit grpc jobs/python-grpc.yml

    TRANSPORT=$1    
    SOURCE=$2
    if [ -z "$TRANSPORT" ]; then echo "transport?"; return; fi
    if [ -z "$SOURCE" ]; then echo "source?"; return; fi
    SOURCE=$(_abspath $SOURCE)
    echo "JEX: submit $TRANSPORT $SOURCE" 

    if [ ! -f $SOURCE ]; then
        echo "ERR: file not found"
        return
    fi

    (
        cd jex-dotnet/dotnet-submit
        dotnet run -- \
            --hazelcast:clusterName=$CLUSTERNAME --hazelcast:networking:addresses:0=$CLUSTERADDR \
            --submit:source=$SOURCE \
            --submit:define:DOTNET_DIR=$JEX/jex-dotnet/dotnet-$TRANSPORT/publish/self-contained \
            --submit:define:PYTHON_DIR=$JEX/jex-python/python-grpc/publish
    )
}


__build_jex_java () { echo "Build all the jex Java projects"; }
build_jex_java () {(
	cd jex-java/java-submit
	$MVN -nsu clean package
)}


__submit_java () { echo "Submit job to cluster from Java"; }
submit_java () {(

    # args: <config-id> <image-base> [code,secrets]

    if [ -z "$1" ]; then
        echo "err: missing config id"
        return
    fi
    CONFIG_ID=$1
    shift

    if [ -z "$1" ]; then
        echo "err: missing image base"
        return
    fi
    IMAGE_BASE=$1
    shift

    IMAGE="$IMAGE_BASE/usercode-python-slim-example:latest"
    CODE=""
    SECRETS=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            code)
                CODE="--code-path=$JEX/hazelcast-usercode/python/example"
                IMAGE="$IMAGE_BASE/usercode-python-slim:latest"
                shift
                ;;
            secrets)
                SECRETS="--submit-secrets"
                shift
                ;;
            *)
                echo "meh?"
                exit 1
                ;;
        esac
    done
    
    # FIXME WIP
    REGAUTH=
    #REGAUTH="--registry-auth={"auths":{"quay.io":{"auth":"aHpfc3RlcGhhbmU6d1lqUmZpTkU5bld4a0hBeWlqTW9mS2ZpUHltUnNOeThYWWsvaXlxbjE5ZUIxVmg4U2taVjBYVFBsNkVodjh0MEdsOUJMSndpTjBuNEZuQ0xoNHdkQ1E9PQ=="}}}

    HZHOME=$JEX/hazelcast-enterprise/distribution/target/hazelcast-enterprise-$HZVERSION
    TARGET=$JEX/jex-java/java-submit/target
    CLASSPATH="$TARGET/java-submit-1.0-SNAPSHOT.jar:$HZHOME/lib:$HZHOME/lib/*"
    CLCHOME=$($CLC home)

    # using the base image + uploading the code, or
    # if $2 is 'full', using the example full image which contains the code already
    java -classpath $(_classpath $CLASSPATH) org.example.Submit \
        --secrets-path $CLCHOME/configs/$CONFIG_ID \
        --runtime-image $IMAGE \
        $CODE $SECRETS $REGAUTH
)}


__run_example () { echo "Run the .NET example app"; }
run_example () {(

    CONFIG_ID=$1
    CLCHOME=$($CLC home)
    cd jex-dotnet/dotnet-example
    dotnet run -- $CLCHOME/configs/$CONFIG_ID #--hazelcast:clusterName=$CLUSTERNAME --hazelcast:networking:addresses:0=$CLUSTERADDR
)}


__run_test_grpc () { echo "Run the .NET gRPC test app"; }
run_test_grpc () {(

    cd jex-dotnet/dotnet-grpc-client
    dotnet run 
)}

CMDS=$1

if [ -z "$CMDS" ]; then
    if [ $SOURCED == 1 ]; then
        return
    else
    	echo "Uh, what am I supposed to do?"
        echo "Hint: try 'jex help' to list commands, or tab-completion"
    	exit
    fi
fi

shift
for cmd in $(IFS=,;echo $CMDS); do
    cmd=${cmd//-/_}
    declare -F $cmd >/dev/null
    if [ $? == 0 ]; then
        eval $cmd $@
        if [ $? -ne 0 ]; then break; fi
    else
        echo "Not a command: $cmd"
        echo "Hint: try 'jex help' to list commands, or tab-completion"
        break
    fi
done
echo ""

# APPENDIX: NOTES

# add '--entrypoint /bin/bash' to override entrypoint and inspect the content of a container
# forward ports: kc port-forward --namespace default runtime-controller-68cc497fcb-bk56w 50051:50051
# shell into a k8 pod: kc exec -it hazelcast-0 -- /bin/bash

# eof
