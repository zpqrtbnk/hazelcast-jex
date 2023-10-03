#
# HAZELCAST JEX JEX SCRIPT
#

# run '. ./jex.sh init' in order to initialize the environment

# NOTE
# add '--entrypoint /bin/bash' to override entrypoint and inspect the content of a container
# forward ports: kc port-forward --namespace default runtime-controller-68cc497fcb-bk56w 50051:50051
# shell into a k8 pod: kc exec -it hazelcast-0 -- /bin/bash


function init () {

    # NOTE
    # avoid editing jex.sh (and commiting changes to source revision)
    # instead, create a jex.sh.user file alongside jex.sh with only
    # the required changes, this file is .gitignored.

    # --- configure environment ---
    export JEX=/path/to/hazelcast-jex # path to the jex root
    export CLUSTERNAME=dev
    export CLUSTERADDR=localhost:5701
    export HZVERSION=5.4.0-SNAPSHOT # the version we're branching from
    export HZVERSION_DOCKER=5.3.2 # the base version we'll pull from docker
    export LOGGING_LEVEL=DEBUG
    export DOCKER_REPOSITORY=zpqrtbnk # repo name of our temp images
    export DOCKER_NETWORK=jex # the network name for our demo
    export MVN=mvn # name of Maven executable, can be 'mvn' or a full path
    export HELM=helm # name of Helm executable, can be 'mvn' or a full path
    export SANDBOX_KEY= # Viridian sandbox key (do NOT set it here but in the .user file)
    export SANDBOX_SECRET= # Viridian sandbox secret (same)
    export HZ_LICENSEKEY= # a license key
    # --- configure environment ---

    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
    if [ -f "$SCRIPT_DIR/jex.sh.user" ]; then
        source "$SCRIPT_DIR/jex.sh.user"
    fi

    export CLI=$JEX/hazelcast-enterprise/distribution/target/hazelcast-enterprise-$HZVERSION/bin/hz-cli
    export CLZ=$JEX/hazelcast-enterprise/distribution/target/hazelcast-enterprise-$HZVERSION/bin/hz
    export CLC="$JEX/hazelcast-commandline-client/build/clc --config $JEX/temp/clc-config.yml"
    export VRD=$JEX/vrd/build/vrd
    export HAZELCAST_CONFIG=$JEX/config/hazelcast-cluster.xml
    export PYTHON=python3 # linux
    if [ "$OSTYPE" == "msys" ]; then
        export PYTHON=python # windows
    fi

    #if [ -n "$SANDBOX_KEY" ]; then
    #    export CLC_VIRIDIAN_API_KEY=$SANDBOX_KEY
    #    export CLC_VIRIDIAN_API_SECRET=$SANDBOX_SECRET
    #fi

    if [ ! -d $JEX/temp ]; then
        mkdir $JEX/temp
    fi

    cat <<EOF > $JEX/temp/clc-config.yml
cluster:
  name: $CLUSTERNAME
  address: $CLUSTERADDR
EOF

    $HELM repo add hzcharts https://hazelcast-charts.s3.amazonaws.com/

    alias jex=./jex.sh
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
	
    export JEX_COMMANDS=$( grep -E '^function\s[A-Za-z0-9][A-Za-z0-9_]*(\s|\()' jex.sh | cut -d " " -f 2 )
    complete -F _jex jex

    echo "configured with:"
    echo "    cluster name '$CLUSTERNAME'"
    echo "    member at '$CLUSTERADDR'"
    echo "initialized the following aliases:"
    echo "    jex:  invokes the jex script"
    echo "    clc:  invokes the clc with the demo config"
    echo "    clz:  invokes the cluster hz script"
    echo "    vrd:  invokes vrd"
    echo "    mvn:  invokes Maven"
    echo "    helm: invokes Helm"
    echo "enjoy!"
    echo ""
}

function _jex() {
    local cur
    # COMP_WORDS is an array containing all individual words in the current command line
    # COMP_CWORD is the index of the word contianing the current cursor position
    # COMPREPLY is an array variable from which bash reads the possible completions
    cur=${COMP_WORDS[COMP_CWORD]}
    cur=${cur//-/_} # can use - or _
    COMPREPLY=()
    # compgen returns the array of elements from $JEX_COMMANDS matching the current word
    COMPREPLY=( $( compgen -W "$JEX_COMMANDS" -- $cur | sed 's/_/-/g' ) )
    return 0
}

function _abspath () {
    (cd $(dirname $1); echo "$(pwd)/$(basename $1)")
}

function _classpath () {

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

# gets the Viridian secrets, using the CLC link
# usage: jex get_secrets https://....
function get_secrets () {

    SECRETS=$JEX/temp/viridian-secrets
    curl -o $SECRETS.zip $1
    if [ ! -d "$SECRETS" ]; then
        mkdir $SECRETS
    fi
    unzip -d $SECRETS $SECRETS.zip
    rm $SECRETS.zip
    DIR=$( ls $SECRETS | grep hazelcast-cloud )
    VIRIDIAN_ID=$( echo $DIR | cut -d '-' -f 7 )
    mv $SECRETS/$DIR $SECRETS/$VIRIDIAN_ID
    echo "JEX: retrieved secrets for Viridian cluster $VIRIDIAN_ID"
    echo $VIRIDIAN_ID > $SECRETS/id
}

# build the Hazelcast CLC (Go) project
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

# build the Hazelcast OS (Java) project
function build_cluster_os () {(
    cd hazelcast

    $MVN clean install -DskipTests -Dcheckstyle.skip=true
)}

# build the Hazelcast EE (Java) project
# and patch + unzip the distribution
function build_cluster_ee () {(

    # configure for license check
    NLC=""
    MVNLC=""
    if [ "$1" == "NLC" ]; then
      NLC="-nlc"
      MVNLC="-Pno-license-checker-build"
    fi

    cd hazelcast-enterprise
    $MVN -Pquick $MVNLC clean install
    cd distribution/target
    rm -rf hazelcast-enterprise-$HZVERSION
    unzip hazelcast-enterprise-$HZVERSION.zip

    # temp for tests, setting LOGGING_LEVEL is too broad and verbose
    cat <<EOF >> $JEX/hazelcast-enterprise/distribution/target/hazelcast-enterprise-$HZVERSION/config/log4j2.properties
logger.usercode.name=com.hazelcast.usercode
logger.usercode.level=DEBUG
EOF

    # this file is not in the distribution
    cd ../..
    cp hazelcast-enterprise-usercode/target/hazelcast-enterprise-usercode-$HZVERSION$NLC.jar \
        distribution/target/hazelcast-enterprise-$HZVERSION/lib 
)}

# build the Hazelcast .NET (C#) client project
function build_client_dotnet () {(

    # build the Hazelcast .NET client, including the new packages
    # and cleanup the package cache because we are not bumping the version,
    # and we want to force projects that depend on the client to fetch the
    # updated dependency anyways
    cd hazelcast-csharp-client
    pwsh ./hz.ps1 build,pack-nuget
    rm -rf ~/.nuget/packages/hazelcast.net
    rm -rf ~/.nuget/packages/hazelcast.net.*
)}

# build the various .NET projects used for the demos
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

# executes the python runtime as a process
# can be useful to test with the passthru runtime service
function runtime_python () {(

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

# executes the .NET+gRPC runtime as a process
# can be useful to test with the passthru runtime service
function runtime_dotnet_grpc () {(

    cd jex-dotnet/dotnet-grpc
    dotnet run
)}

# run a temp Docker container running busybox sh
function dk_sh () {

	docker run -it --rm --net jex \
		--name tempsh -h tempsh \
		busybox sh
}

# builds the Hazelcast cluster (OS+EE) Docker single-platform image and push to registry
# (assuming that the OS+EE projects have been built already)
function _OBSOLETE_dk_cluster_build_local () {

    dk_cluster_build_image $DOCKER_REPOSITORY/hazelcast:$HZVERSION_DOCKER
	
    docker tag $DOCKER_REPOSITORY/hazelcast:$HZVERSION_DOCKER $DOCKER_REPOSITORY/hazelcast:latest
    docker push $DOCKER_REPOSITORY/hazelcast:latest
}

# builds the Hazelcast cluster (OS+EE) Docker multi-platform image and push to Quay
# (assuming that the OS+EE projects have been built already)
function dk_cluster_build_quay () {(

    #IMAGE=quay.io/hz_stephane/hazelcast_dev:stephane.gay
    IMAGE=quay.io/hazelcast_cloud/hazelcast-dev:stephane.gay
    docker login -u $QUAY_USER -p $QUAY_PASSWORD quay.io
    _dk_cluster_build_image $IMAGE
)}

function _dk_cluster_build_image () {

    # build Hazelcast EE docker image from scratch
    # from our own build of OS and EE for version $HZVERSION

    # configure for license check
    NLC=""
    if [ $NO_LICENSE_CHECK -eq 1 ]; then
      NLC="-nlc"
    fi
	
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
    cp $ENTERPRISE/hazelcast-enterprise-usercode-$HZVERSION$NLC.jar $DOCKER_SOURCE/lib/

    # copy our own configuration file
    cp config/hazelcast-ee.xml $DOCKER_SOURCE/hazelcast-usercode.xml

    # copy hazelcast-docker stuff
    cp -r hazelcast-docker/hazelcast-enterprise/* $DOCKER_SOURCE/

    # build and push (need to do both at once due to multi-platform)
    docker buildx build --builder viridian --platform linux/amd64,linux/arm64 --push \
        -t $1 \
        -f dk8/hazelcast-ee.dockerfile \
        --build-arg="HZVERSION=$HZVERSION_DOCKER" \
        $DOCKER_SOURCE
		
    rm -rf $DOCKER_SOURCE
}

# build the Python runtime Docker images
function dk_runtime_build_python () {

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
function dk_runtime_build_dotnet () {

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
		$DOCKER_REPOSITORY/hazelcast:$HZVERSION_DOCKER
}

# run the Python runtime via Docker (for passthru)
function dk_runtime_run_python () {

    # BEWARE! the job need to know the address of the gRPC runtime server

    # select the base or full image
    #IMAGE=$DOCKER_REPOSITORY/python-usercode
    IMAGE=$DOCKER_REPOSITORY/python-usercode-base

	docker run --rm -it --net jex \
		-p 5252:5252 \
		--name runtime -h runtime \
        $IMAGE
}

# run the Dotnet runtime via Docker (for passthru)
function dk_runtime_run_dotnet () {

	# BEWARE! the job need to know the address of the gRPC runtime server

    # select the base or full image
    #IMAGE=$DOCKER_REPOSITORY/dotnet-usercode
    IMAGE=$DOCKER_REPOSITORY/dotnet-usercode-base

	docker run --rm -it --net jex \
		-p 5252:5252 \
		--name runtime -h runtime \
        $IMAGE
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

	# BEWARE! runtime controller address and port, etc in member-values.yaml 
	$HELM install hazelcast hzcharts/hazelcast -f config/member-values.yaml
}

# stop the k8 cluster
function k8_cluster_stop () {

	$HELM delete hazelcast
}

# get the k8 cluster logs
function k8_cluster_logs () {
	kubectl logs hazelcast-0
}

# get a detailed report on our k8 environment
function k8_show () {
	kubectl get pod --output=wide
	kubectl get svc
}

# submit jobs, the .NET way
# OBSOLETE - should use the CLC now, e.g.:
# clc job submit jobs/dotnet-shmem.yml DOTNET_DIR=$JEX/jex-dotnet/dotnet-shmem/publish/self-contained
# clc job submit jobs/dotnet-grpc.yml DOTNET_DIR=$JEX/jex-dotnet/dotnet-grpc/publish/self-contained
# clc job submit jobs/python-grpc.yml PYTHON_DIR=$JEX/jex-python/python-grpc/publish
# OBSOLETE - and, even that usage of CLC is using our own CODEC etc
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

    # submit the job (the dotnet way)
    # (eventually, this should be done by CLC)
    # submit:source points to the yaml file
    # submit:define:* provides replacement for $TOKEN in the yaml file
    (
        cd jex-dotnet/dotnet-submit
        dotnet run -- \
            --hazelcast:clusterName=$CLUSTERNAME --hazelcast:networking:addresses:0=$CLUSTERADDR \
            --submit:source=$SOURCE \
            --submit:define:DOTNET_DIR=$JEX/jex-dotnet/dotnet-$TRANSPORT/publish/self-contained \
            --submit:define:PYTHON_DIR=$JEX/jex-python/python-grpc/publish
    )
}

# build the "submit the python job on local via java" java code
function build_submit_local_java () {(

    PIPELINE=java-pipeline
    cd jex-java/$PIPELINE
    $MVN clean package
)}

# build the "submit the python job on viridian via java" java code
function build_submit_viridian_java () {(

    PIPELINE=java-pipeline-viridian
    cd jex-java/$PIPELINE
    $MVN clean package
)}

# submit the python job on local via java
function submit_local_java () {(

    PIPELINE=java-pipeline
    HZHOME=$JEX/hazelcast-enterprise/distribution/target/hazelcast-enterprise-$HZVERSION
    TARGET=$JEX/jex-java/$PIPELINE/target
    CLASSPATH="$TARGET/python-jet-usercode-1.0-SNAPSHOT.jar:$HZHOME/lib:$HZHOME/lib/*"
    echo $CLASSPATH

    USERCODE_PATH=$JEX/hazelcast-usercode/python/example
    SECRETS_PATH="NULL" # $JEX/temp/viridian-secrets/$VIRIDIAN_ID

    # args are: usercode-path, secrets-path (or NULL)
    java -classpath $(_classpath $CLASSPATH) org.example.SubmitPythonJetUserCode \
        $USERCODE_PATH \
        $SECRETS_PATH
)}

# submit the python job on viridian via java
function submit_viridian_java () {(

    VIRIDIAN_ID=$( cat $JEX/temp/viridian-secrets/id )

    PIPELINE=java-pipeline-viridian
    HZHOME=$JEX/hazelcast-enterprise/distribution/target/hazelcast-enterprise-$HZVERSION
    TARGET=$JEX/jex-java/$PIPELINE/target
    CLASSPATH="$TARGET/python-jet-usercode-1.0-SNAPSHOT.jar:$HZHOME/lib:$HZHOME/lib/*"
    echo $CLASSPATH

    java -classpath $(_classpath $CLASSPATH) org.example.SubmitPythonJetUserCode \
        $JEX/temp/viridian-secrets/$VIRIDIAN_ID \
        $JEX/hazelcast-usercode/python/example/usercode # fixme 
)}

# run the demo example
# (puts stuff into a map and expects stuff to appear in another map, if the python job is running)
function run_example () {(

    cd jex-dotnet/dotnet-example
    dotnet run -- --hazelcast:clusterName=$CLUSTERNAME --hazelcast:networking:addresses:0=$CLUSTERADDR
)}

# run the gRPC test client
# (against a locally-running gRPC runtime)
function run_grpc_test () {(

    cd jex-dotnet/dotnet-grpc-client
    dotnet run 
)}

CMDS=$1

if [ -z "$CMDS" ]; then
	echo "Uh, what am I supposed to do?"
	exit
fi

shift
for cmd in $(IFS=,;echo $CMDS); do
    cmd=${cmd//-/_}
    echo "JEX: $cmd $@"
    eval $cmd $@
    if [ $? -ne 0 ]; then break; fi
done
