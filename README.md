
# Hazelcast JEX

An experimental solution that allows users to run .NET and Python transformations 
as part of a Jet pipeline, by forking processes and passing tasks between Java
and .NET or Python using either gRPC, or a fast shared-memory IPC mechanism.

*This project is in POC/WIP state. Don't expect it to be ready for production usage.*

## Demo

The entire demonstration is scripted in the `./demo.sh` shell script.

First, clone this repository, including its submodules:
```sh
git clone --recurse-submodules https://github.com/zpqrtbnk/hazelcast-jex
```

Then, follow the script to:
* Edit the top of the demo.sh script with your details
* Initialize the demo env with '. ./demo.sh'
* Build the Hazelcast Java project with 'demo build-cluster'
* Build the Hazelcast .NET client with 'demo build-demo'
* Run a cluster with '$CLZ start'
* Submit a job with 'demo submit'
* Run an example to validate that the job is running with 'demo example'
* Cancel the job with '$CLC job cancel my-job'

Requirements: Bash, Powershell (pwsh), .NET 7.

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

## Viridian Demo

There is no Viridian demo.

This cannot run on Viridian for now, because Viridian will not restore the Jet job attached resources,
nor will it accept to fork a process, be it .NET or Python, from the Java member process.

Until this is addressed, there is not much we can do.

See also: [user-code-sidecar](https://github.com/hazelcast/user-code-sidecar/tree/master/example-python) repository.