
# Hazelcast JEX

An experimental solution that allows users to run .NET and Python transformations 
as part of a Jet pipeline, by forking processes and passing tasks between Java
and .NET or Python using either gRPC, or a fast shared-memory IPC mechanism.

*This project is in POC/WIP state. Don't expect it to be ready for production usage.*

## Demo

The entire demonstration is scripted via the `./demo.sh` shell script.

### Requirements

You will need 
* Bash (`demo.sh` is a Bash script)
* Powershell (i.e. `pwsh`, required to build the .NET client)
* .NET 7 (to run the .NET client)
* Python 3.9+ (to run the Python examples) with PIP
* Go 1.16+ (to build the CLC)
* Docker (in order to run the container demo)

### Build

First, clone this repository, including its submodules:
```sh
git clone --recurse-submodules https://github.com/zpqrtbnk/hazelcast-jex
```

Then, change to the `hazelcast-jex` directory and initialize the demo environment.
Edit the lines at the top of the `demo.sh` to suit your environment, then run
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

### Demo

Then,
* Run a cluster with `clz start`
* Submit a job with e.g. `clc job submit jobs/dotnet-grpc.yml DOTNET_DIR=./jex-dotnet/dotnet-grpc/publish/self-contained`
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

Depending on the `jobs/*.yml` file that you use, a different service can be used:
* The "process" service starts the user code runtime as a separate process.
* The "passthru" service assumes you have started the runtime already.
* The "container" service (work-in-progress) starts the user code runtime as a container.

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