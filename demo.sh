
function init () {

    # --- configure environment ---
    export DEMO=/home/sgay/shared/hazelcast-jex # path to the demo root
    export MVN=mvn # name of Maven executable, can be 'mvn' or a full path
    export CLUSTERNAME=dev
    #export CLUSTERADDR=localhost:5701
	export CLUSTERADDR=192.168.1.200:5701
    export HZVERSION=5.4.0-SNAPSHOT # the version we're branching from
	export HZVERSION_DOCKER=5.3.2 # the base version we'll pull from docker
    export LOGGING_LEVEL=DEBUG
	export DOCKER_REPOSITORY=zpqrtbnk # repo name of our temp images
	export DOCKER_NETWORK=jex # the network name for our demo
    # --- configure environment ---

    export CLI=$DEMO/hazelcast/distribution/target/hazelcast-$HZVERSION/bin/hz-cli
    export CLZ=$DEMO/hazelcast/distribution/target/hazelcast-$HZVERSION/bin/hz
    export CLC="$DEMO/hazelcast-commandline-client/build/clc --config $DEMO/temp/clc-config.yml"
	export HELM=$DEMO/temp/helm-v3.12.3/helm
    export HAZELCAST_CONFIG=$DEMO/hazelcast-cluster.xml
	export PYTHON=python3 # linux
	if [ "$OSTYPE" == "msys " ]; then
		export PYTHON=python # windows
	fi

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
	
	export DEMO_COMMANDS=$(grep -E '^function\s[A-Za-z0-9_]*\s' demo.sh \
	                       | cut -d " " -f 2\
						   | grep -E -v 'abspath|init' \
						   )
	complete -F _demo demo

	echo "configured with:"
	echo "    member at $CLUSTERADDR"
    echo "initialized the following aliases:"
    echo "    demo: invokes the demo script"
    echo "    clc:  invokes the clc with the demo config"
    echo "    clz:  invokes the cluster hz script"
    echo "enjoy!"
    echo ""
}

function _demo() {
	local cur
    # COMP_WORDS is an array containing all individual words in the current command line
    # COMP_CWORD is the index of the word contianing the current cursor position
    # COMPREPLY is an array variable from which bash reads the possible completions
    cur=${COMP_WORDS[COMP_CWORD]}
    COMPREPLY=()
    # compgen returns the array of elements from $DEMO_COMMANDS matching the current word
    COMPREPLY=( $( compgen -W "$DEMO_COMMANDS" -- $cur ) )
    return 0
}

function abspath () {
    (cd $(dirname $1); echo "$(pwd)/$(basename $1)")
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

# build the Hazelcast cluster (Java) project
function build_cluster () {
    # build the Hazelcast project
    # includes the packages
    (cd hazelcast &&
        $MVN package -DskipTests -Dcheckstyle.skip=true &&
        cd distribution/target &&
        rm -rf hazelcast-$HZVERSION && 
        unzip hazelcast-$HZVERSION.zip)
}

# build the Hazelcast .NET client project
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

# build the various Python resources used for the demo
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
            #find . -type f -name '*.py' -exec cp --parents {} $PUBLISH \;
            find . -type f -name '*.py' ! -name '__*' -exec cp {} $PUBLISH \;
        )
        (
            cd python-grpc
            cp requirements.txt $PUBLISH
            cp *.py $PUBLISH
        )
    )
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

# builds docker python image
function build_docker_python () {

	# build python image
	docker build \
		-t $DOCKER_REPOSITORY/jet-python-grpc:latest \
		-f jobs/python-container-grpc.dockerfile \
		jex-python/python-grpc/publish/any	
		
	# for k8 to find it?
	docker push $DOCKER_REPOSITORY/jet-python-grpc:latest
}

# builds docker dotnet image 
function build_docker_dotnet () {

	# build dotnet image
	docker build \
		-t $DOCKER_REPOSITORY/jet-dotnet-grpc:latest \
		-f jobs/dotnet-container-grpc.dockerfile \
		jex-dotnet/dotnet-grpc/publish/single-file/linux-x64
}

# builds docker hazelcast image
function build_docker_hazelcast () {

	# cannot run that bare one, need to add our own Java code
	#docker pull hazelcast/hazelcast:$HZVERSION_DOCKER
	
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
		-t $DOCKER_REPOSITORY/hazelcast:$HZVERSION_DOCKER \
		-f jobs/hazelcast.dockerfile \
		--build-arg="HZVERSION=$HZVERSION_DOCKER" \
		$BUILD_CONTEXT
		
	rm -rf $BUILD_CONTEXT
	
	docker tag $DOCKER_REPOSITORY/hazelcast:$HZVERSION_DOCKER $DOCKER_REPOSITORY/hazelcast:latest
}

# builds docker images
function build_docker () {

	docker network ls | grep -q $DOCKER_NETWORK
	if [ $? -eq 1 ]; then
		docker network create $DOCKER_NETWORK
	fi

	build_docker_python
	build_docker_dotnet
	build_docker_hazelcast
}

# NOTE
# add --entrypoint /bin/bash to override entrypoint and inspect the container!
# forward ports: kc port-forward --namespace default runtime-controller-68cc497fcb-bk56w 50051:50051
# shell into a k8 pod: kc exec -it hazelcast-0 -- /bin/bash

# runs the docker member
function run_docker_member () {

	# removed:
	#   -v $DEMO/hazelcast-cluster.xml:/opt/hazelcast/hazelcast.xml \
	# configuration is now copied into the image when building
	# because it's hard to map a file in k8 setup (see hazelcast.dockerfile)

	docker run --rm -it --net jex \
		-p 5701:5701 \
		--name member0 -h member0 \
		-e HAZELCAST_CONFIG=/data/hazelcast/hazelcast.xml \
		-e HZ_CLUSTERNAME=dev \
		-e HZ_RUNTIME_CONTROLLER_ADDRESS=10.106.74.139 \
		-e HZ_RUNTIME_CONTROLLER_PORT=50051 \
		$DOCKER_REPOSITORY/hazelcast:$HZVERSION_DOCKER
}

function k8_start_controller () {
	$HELM upgrade --install runtime-controller user-code-runtime/charts/runtime-controller
}

function k8_stop_controller () {
	$HELM delete runtime-controller
}

function k8_start_member () {
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

function k8_stop_member () {
	#kubectl delete service/hz-hazelcast-0 pod/hz-hazelcast-0
	#kubectl delete -f k8/pod-hz-hazelcast.yaml
	#kubectl delete -f k8/service-hz-hazelcast.yaml
	$HELM delete hazelcast
}

function k8_logs_member () {
	kubectl logs service/hz-hazelcast-0
}

function k8_get () {
	kubectl get pod --output=wide
	kubectl get svc
}

# runs the k8 member
# (the plain docker member cannot talk to the runtime controller)
function run_k8_member () {

	# FIXME but what about the freaking configuration file?!
	# can it be done with --overrides without it being too crazy?
	# -> we copy it into the image :(
	#
	# and then, that member goes crazy trying to talk to controller
	# = DO NOT USE

	kubectl run --rm member0 \
		-i --tty \
		--restart=Never \
		--expose --port=5701 \
		--env="HAZELCAST_CONFIG=hazelcast.xml" \
		--env="HZ_CLUSTERNAME=dev" \
		--env="HZ_RUNTIME_CONTROLLER_ADDRESS=runtime-controller" \
		--env="HZ_RUNTIME_CONTROLLER_PORT=50051" \
		--image=$DOCKER_REPOSITORY/hazelcast:$HZVERSION_DOCKER
}

# runs the docker python runtime (for passthru)
function run_docker_runtime_python () {

	# BEWARE!
	# the job yaml need to be updated to specify the grpc.address=runtime
	# so that Java knows where to reach the Python gRPC runtime server

	docker run --rm -it --net jex \
		-p 5252:5252 \
		--name runtime -h runtime \
		$DOCKER_REPOSITORY/jet-python-grpc
}

function run_docker_runtime_dotnet () {

	# BEWARE! 
	# (see python)

	docker run --rm -it --net jex \
		-p 5252:5252 \
		--name runtime -h runtime \
		$DOCKER_REPOSITORY/jet-dotnet-grpc
}

# runs a temp sh
function run_docker_sh () {

	docker run -it --rm --net jex \
		--name tempsh -h tempsh \
		busybox sh
}

# submit jobs, the .NET way - OBSOLETE - should use the CLC now
# e.g.:
# clc job submit jobs/dotnet-shmem.yml DOTNET_DIR=$DEMO/jex-dotnet/dotnet-shmem/publish/self-contained
# clc job submit jobs/dotnet-grpc.yml DOTNET_DIR=$DEMO/jex-dotnet/dotnet-grpc/publish/self-contained
# clc job submit jobs/python-grpc.yml PYTHON_DIR=$DEMO/jex-python/python-grpc/publish
function submit () {

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
# will put stuff into a map and expect stuff to appear in another map
# magic
function example () {

    # run the example
    (
        cd jex-dotnet/dotnet-example
        dotnet run -- \
            --hazelcast:clusterName=$CLUSTERNAME --hazelcast:networking:addresses:0=$CLUSTERADDR
	)
}

# run a gRPC test client
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
