
# Hazelcast JEX

An experimental solution that allows users to run .NET and Python transformations 
as part of a Jet pipeline, by delegating work to an out-of-process "user code" service
which can be a forked process, or a separate container, and passing tasks between Java
and .NET or Python using either gRPC, or a fast shared-memory IPC mechanism.

*This project is in POC/WIP state. Don't expect it to be ready for production usage.*

## In this Repository

This repository links to four submodules:
* `hazelcast` forks from the Hazelcast repository and provides the Java code to run
the entire user code system in the member
* `hazelcast-commandline-client` forks from the Hazelcast CLC repository and provides
code to upload Jet jobs defined as YAML text
* `hazelcast-csharp-client` forks from the Hazelcast .NET client repository and
provides code to write Jet user code service in C#
* `user-code-runtime` is the user code runtime controller that can run containers in
a Kubernetes (Viridian) environment

## How To

All operations are scripted via the `./demo.sh` shell script. This script can be
personalized via a `./demo.sh.user` file, see details at the top of `demo.sh`.

### Requirements

You will need 
* Bash (`demo.sh` is a Bash script)
* Powershell (i.e. `pwsh`, required to build the .NET client)
* .NET 7 (to run the .NET client)
* Mvn (to build the Java code)
* Python 3.9+ (to run the Python examples) with PIP
* Go 1.16+ (to build the CLC)
* Docker (in order to run the container demo)
* Kubernetes and Helm (in order to run the Kubernetes demo)

### Build

First, clone this repository, including its submodules:
```sh
git clone --recurse-submodules https://github.com/zpqrtbnk/hazelcast-jex
```

Then, change to the `hazelcast-jex` directory and initialize the demo environment.
Create a `demo.sh.user` file as per the instructions at the top of `demo.sh`, edit
to suit your environment, then run 
```sh
. ./demo.sh init
```

This will give you the `demo` alias, amongst other things. Using this alias,
* Build the Hazelcast Java project with `demo build-cluster`
* Build the Hazelcast .NET client with `demo build-client-dotnet`
* Build the Hazelcast .NET demo code with `demo build-demo-dotnet`
* Build the Hazelcast Python demo code with `demo build-demo-python`
* Build the Hazelcast Command Line Client project with `demo build-clc`
* Build the Docker images with `demo build-docker`

### Simple Process Demo

Then,
* Run a cluster with `clz start`
* Submit a job with e.g. `clc job submit jobs/dotnet-process-grpc.yml DOTNET_DIR=./jex-dotnet/dotnet-grpc/publish/single-file`
* Verifiy that the job is running with `clc job list`
* Run an example to validate that the job is running with `demo example`

The example *should* produce something like:
```text
Connect to cluster...
Connected
Add entry to streamed-map: example-key-20 = SomeThing(Value=20)
Added
wait for entry with key example-key-20 to appear in result-map
Found: example-key-20 = OtherThing(Value=__20__)
```

The added entry has been added to the `streamed-map` map, which has journaling enabled.
Thanks to journaling, the pipeline triggers and passes the entry value (a `SomeThing` object with an integer `Value` property) to the .NET transformation, which returns a transformed entry (a `OtherThing` object with a string `Value` property). The pipeline inserts this entry into a `result-map` map.
The example code then tries to find this entry in the map.

### Other Demos

Depending on the `jobs/*.yml` file that you use, a different service can be used:
* The "process" service starts the user code runtime as a separate process.
* The "passthru" service assumes you have started the runtime already.
* The "container" service starts the user code runtime as a container.

### Kubernetes Demo

Build everything as per the instructions above.

Make sure that the docker images have been pushed to docker hub.

> Or? Do we need this? How's Helm and k8 finding the images?

Then,
* `demo k8-start-controller` should start a controller service in k8
* `demo k8-start-member` should start a member service in k8
* `clc job submit jobs/python-grpc-container.yml` should submit the Python job
* `demo example` should run the example... and work

## Code

### Hazelcast

The original Jet Python extension `hazelcast-jet-python` has been altered during
experiments and *should probably rolled back to its original state*.

A new Jet extension `hazelcast-jet-usercode` provides a user code stage provider
for adding a user code stage via the YAML job builder.

In the `hazelcast` main module, code in `com.hazelcast.jet` support the YAML job
builder.

A new module `hazelcast-usercode` provides ...

## What's not working

These are being investigated...

* Python logs do not bubble up to Java logs correctly
* Jet resource directories must be flat and that is a pain, can it be fixed?
* Currently not implementing batches, only streaming, so?

More work to do:
* Implement more Yaml support (for Kafka etc)
* Implement the existing Python ML example as a Yaml pipeline
* Implement a .COPYTO function to copy files to a running runtime
* General work on securing the communication between member & runtime
* Java should test for python+pip presence, but how?
* Must verify that in container mode we pass the right address to grpc

In addition, most of the codebase is POC-quality and needs to be revisited, cleaned up, etc.

## Viridian Demo

There is no Viridian demo.

This cannot run on Viridian for now, because Viridian will not restore the Jet job attached resources,
nor will it accept to fork a process, be it .NET or Python, from the Java member process.

Until this is addressed, there is not much we can do.

See also: [user-code-sidecar](https://github.com/hazelcast/user-code-sidecar/tree/master/example-python) repository.