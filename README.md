
# Hazelcast JEX

An experimental solution that allows users to run .NET and Python transformations 
as part of a Jet pipeline, by delegating work to an out-of-process "user code" service
which can be a forked process, or a separate container, and passing tasks between Java
and .NET or Python using either gRPC, or a fast shared-memory IPC mechanism.

*This project is in POC/WIP state. Don't expect it to be ready for production usage.*

## This Repository

This repository links to several submodules:
* `clc` forks from the Hazelcast CLC repository and adds code to upload Jet jobs as YAML text
* `hazelcast` forks from the Hazelcast repository (changes?)
* `hazelcast-csharp-client` forks from the Hazelcast .NET client repository and provides code to write Jet user code service in C#
* `hazelcast-docker` is the Hazelcast Docker repository (no changes)
* `hazelcast-enterprise` froms from the Hazelcast Enterprise repository and adds code to run UserCode
* `hazelcast-usercode` forks from the Hazelcast UserCode repository and provides Python runtime as well as the Java Jet JobBuilder
* `user-code-runtime` forks from the Hazelcast runtime repository (no changes)
* `vrd` forks from the Hazelcast VRD repository (no changes)

In addition, this repository provides various tool to help test the proposed features.

## Quick Start

Clone this repository, including its submodules:
```sh
git clone --recurse-submodules https://github.com/zpqrtbnk/hazelcast-jex
```

Then activate the `jex` command (ONLY in Bash):
```sh
source jex.sh
```

The `jex` alias becomes available. Try `jex help` to list commands.
Most operations are scripted via `jex`.

The script needs to be configured (see top of the script), but do NOT edit the script.
Instead, create a parallel `jex.sh.user` file and copy and customize the configuration section.

### Requirements

You will need 
* Bash (`demo.sh` is a Bash script)
* Powershell (i.e. `pwsh`, required to build the .NET client)
* .NET 7 (to run the .NET client)
* Mvn (to build the Java code)
* Python 3.9+ (to run the Python examples) with PIP
* Go 1.21+ (to build the CLC)
* Docker (in order to run the container demo)
* Kubernetes and Helm (in order to run the Kubernetes demo)


## Demos

### Description

The demos start a Kubernetes cluster (either locally or on Viridian) and submit a job which sources from the `streamed-map` journal,
then passes the received values (objects of class `SomeThing` with an integer `Value` property, that are compact-serialized) to
a Python runtime, which returns a transformed entry (objects of class `OtherThing` with a string `Value` property, also compact-serialized),
which is then sinked into a `result-map` map.

The actual example code inserts an entry into `streamed-map` and then waits for some time to see the corresponding entry
being inserted into `result-map` by the Jet job, if everything works as expected. Expect to see something similar to:

```text
Connect to cluster...
Connected
Add entry to streamed-map: example-key-20 = SomeThing(Value=20)
Added
wait for entry with key example-key-20 to appear in result-map
Found: example-key-20 = OtherThing(Value=__20__)
```

>[!WARNING]
>Beware! there are some hard-coded image names in the `jex-java/submit-java` code.

### Viridian Demo

```
jex build-clc
jex build-vrd
jex dk-initialize
jex login-quay
jex login-viridian

jex build-cluster-os
jex build-cluster-ee-nlc
jex build-dk-cluster-quay

jex build-dk-runtime-python quay.io/hz_stephane

jex create-viridian-cluster usercode.0
jex enable-journal usercode.0
jex build-jex-java
jex submit-java usercode.0 quay.io/hz_stephane [code] [secrets]
jex run-example usercode.0
```

You can use anything in place of `usercode.0` - that is the name of your cluster on Viridian. Replace `quay.io/hz_stephane` with whatever registry name you want to use for the Python Runtime docker image. Specify `code` in order to submit code (from the Python Runtime example) and `secrets` to submit the secrets.

If you specify `code` we'll use the base image, and transfer the code to the image, else we'll use the base+code image.

### Local Kubernetes Demo

Requires `~/.hazelcast/configs/k8` containing `config.json` and `config.yaml`.
Use the examples below but replace with the proper cluster name and address.

```
{
    "cluster": {
        "name": "dev"
        "address": "192.168.1.200:5701"
    }
}
```

```
cluster:
  name: dev
  address: 192.168.1.200:5701
```

```
jex build-clc
jex dk-initialize

jex build-cluster-os
jex build-cluster-ee
jex build-dk-cluster-local

jex build-dk-runtime-python zpqrtbnk 

jex start-k8-cluster
jex start-k8-controller
jex build-jex-java
jex submit-java k8 zpqrtbnk [code] [secrets]
jex run-example k8
```

Here we put the Python Runtime image on Docker Hub (under Stephan's `zpqrtbnk` account, you want to change this).
Rest works similar to Viridian.

### More Demos

In _theory_ the system also supports running local (non-Kubernetes) setups,
where the UserCode runs either in an already running service,
or is forked in a separate process.
These are currently being polished and will be demoed later.


## What's not working

These are being investigated... And the list is not complete at all...

* If you don't specify `secrets` if fails because the secrets are currently n/a on the runtime
* The regitry auth credentials for fetching the Python Runtime are somehow borked
* Jet resource directories must be flat and that is a pain, can it be fixed?
* Currently not implementing batches, only streaming, so?

