
# JET.NET

A solution that allows users to run .NET transformations as part of a Jet pipeline,
by forking a .NET process and passing tasks between Java and .NET using a fast
shared-memory IPC mechanism.

From a high-level standpoint, this solution relies on:

* A `hazelcast-jet-dotnet` Java module that provides the Java-side plumbing
* A `Hazelcast.Net.Jet` .NET package that provides the .NET-side plumbing
* A .NET application that implements the .NET-side pipeline stage
* A Java application that defines the pipeline and submits it to the cluster

*This project is in POC/WIP state. Don't expect it to be ready for production usage.*

## Demonstration

Note: the entire demonstration can be triggered with the `./demo.sh` shell script.

### Clone this repository
Including its submodules:
```sh
git clone --recurse-submodules https://github.com/zpqrtbnk/hazelcast-jet-dotnet
```

### Build and pack the .NET client
(once stable, this step would *not* be required)

Requirements: Powershell (pwsh), .NET 7.

```sh
cd hazelcast-csharp-client
pwsh ./hz.ps1 build,pack-nuget
```

### Build Hazelcast
(once stable, this step would *not* be required)
(current module code for dotnet does not pass style checks)
```sh
mvn install -DskipTests -Dcheckstyle.skip=true
```

And unzip the distribution
(we're going to need scripts)
```sh
mkdir temp
unzip hazelcast/distribution/target/hazelcast-5.3.0-SNAPSHOT.zip -d temp
```

#### Build and publish the .NET service

Replace `<os>` and `<arch>` with the OS and architecture you indend to run the service on.
You can publish for several combinations of OS and architecture.
OS can be: `win`, `linux`, `osx`. Architecture can be: `x64`, `arm64`.

```sh
cd dotnet-service
dotnet build
dotnet publish -c Release -r win-x64 -o target-sc/<os>-<arch> --self-contained
dotnet publish -c Release -r win-x64 -o target/<os>-<arch> --no-self-contained
```

### Build the Java pipeline definition
```sh
cd java-pipeline
mvn package
```

### Prepare a cluster
You must have a cluster running with Jet and resource uploading being enabled.
For the sake of the demo, a map `streamed-map` must be configured with journaling.
For instance, the following member configuration file is appropriate:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<hazelcast xmlns="http://www.hazelcast.com/schema/config"
           xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
           xsi:schemaLocation="http://www.hazelcast.com/schema/config
           http://www.hazelcast.com/schema/config/hazelcast-config-5.0.xsd">

  <cluster-name>dev</cluster-name>

  <!-- we need jet with resources upload -->
  <jet enabled="true" resource-upload-enabled="true"></jet>

  <!-- we need a journaled map -->
  <map name="streamed-map">
    <event-journal enabled="true">
      <capacity>5000</capacity>
      <time-to-live-seconds>60</time-to-live-seconds>
    </event-journal>
  </map>

</hazelcast>
```

Such a file is present in the `java-pipeline` directory and therefore the server can be started with:
```sh
HAZELCAST_CONFIG=./java-pipeline/dotjet.xml
temp/hazelcast-5.3.0-SNAPSHOT/bin/hz start
```

### Submit the pipeline job
(for relative paths reasons in various places, be sure to be in the root directory)
```sh
temp/hazelcast-5.3.0-SNAPSHOT/bin/hz-cli [options] submit \
    java-pipeline/target/dotnet-jet-1.0-SNAPSHOT.jar \
    -d dotnet-service/target-sc -x service
```
With [options] being the connection info to a running cluster. For instance it can be `-tdev@127.0.0.1:5701` or `-f hazelcast-client.yml`.

You can then see the running job with:
```sh
temp/hazelcast-5.3.0-SNAPSHOT/bin/hz-cli [options] list-jobs
```

### Use the pipeline
(replace the server address appropriately)
```sh
cd dotnet-example
dotnet build
dotnet run -- --hazelcast.clusteName=dev --hazelcast.networking.addresses.0=127.0.0.1:5701
```

You *should* see something like:
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

## Viridian Demonstration

In order to submit the job to Viridian, using SSL, one need to use the Enterprise command-line.
In the code below, `hz-cli` is from the Enterprise distribution.

As long as the .NET module is not part of that distribution, a `CLASSPATH` is required.

```sh
export CLASSPATH=hazelcast/distribution/target/hazelcast-5.3.0-SNAPSHOT/lib/hazelcast-jet-dotnet-5.3.0-SNAPSHOT.jar
hz-cli -f viridian.yml submit \
    java-pipeline/target/dotnet-jet-1.0-SNAPSHOT.jar \
    -d dotnet-service/target-sc -x service
```

For now, we have two problems with Viridian
* Don't know how to enable journaling for the `streamed-map`. Maybe using dynamic config with something along `hazelcastInstance.getConfig().addMapConfig(myMapConfig)`) somewhere Java-side?
* Viridian has some permission issues (reported, will be fixed) which prevents the correct re-creation of attached directories. However, once that is fixed, we have no permission to execute the .NET process, which seems logical. This is being discussed with the Viridian team.

Note: was (re) building and testing as:
```sh
export CLASSPATH=hazelcast/extensions/dotnet/target/hazelcast-jet-dotnet-5.3.0-SNAPSHOT.jar
(cd hazelcast && mvn install -DskipTests -Dcheckstyle.skip=true)
(cd java-pipeline && mvn package)
hz-cli -f viridian.yml submit java-pipeline/target/dotnet-jet-1.0-SNAPSHOT.jar -d dotnet-service/target-sc -x service
```

## Components

### Java `hazelcast-jet-dotnet`

A new `hazelcast-jet-dotnet` module is introduced in the `hazelcast` project.
Once stable, it would be deployed on members as part of the distribution. 
During the prototyping phase, it should *not* be included the distribution and should instead be attached to each job.

This module implements the .NET pipeline stage.

This module exposes:
* Class `DotnetServiceConfig` which represents the configuration of the .NET service
* Class `DotnetService` which is the .NET service
* Class `JetMessage` which represents a message exchanged between Java and .NET
* Class `DotnetTransforms` which has only 1 static method and should merge with the service?
* Other things (service context...) which should not be exposed?

Plus all the internal plumbing to fork the .NET process and communicate with it.

### .NET `Hazelcast.Net.Jet`

A new `Hazelcast.Net.Jet` project is introduced in the `hazelcast-csharp-client` solution.
Once stable, it wolud be distributed as a separate package distributed on NuGet. 
During the prototyping phase, it must be built from the solution.

This project exposes the following classes:
* The `JetServer` class represents the server which processes requests from Java
* The `JetTask` class represents a task to be executed by the server for each request
* The `JetMessage` class represents a message exchanged between Java and .NET
* What else?

This package is meant to be used by users to create their .NET services.

### .NET service

An independent application is required, which will host the .NET service. This application will be started by Java when creating the job, on each member. The application can be a normal .NET application, in which case each member must have .NET installed and be able to execute .NET applications. Alternatively, it can be a self-contained .NET executable, in which case nothing is required from the members, as .NET will be part of the executable. The executable can run on Windows or Linux or any platform that supports .NET.

The executable needs to be published for the target platforms that run members. This can be `win-x64` if all members run Windows, or `linux-x64` or `osx-x64` if they run Linux or MacOS. It can also be a combination of platforms: the Java module will pick the appropriate executable depending on the executing platform.

From an application standpoint, the `Main` method needs to create and execute a `JetServer` instance, which handles the communication with Java. A `JetServer` serves a method that receives a request `JetMessage` and must produce a response `JetMessage`.

A `JetMessage` is, in its most simple form, an array of `byte[]` (i.e. an array of byte arrays) coming from Java. However, strongly-types messages are supported. For instance, a `JetMessage<T>` is a `JetMessage` that knows that its first `byte[]` buffer is actually a `Data` serialized buffer, that the serialization service can de-serialize to an object of type `T`. In a similar way, a `JetMessage<T1, T2>` knows about the type of the first two buffers, etc. And, serialization is managed transparently.

Java passes three parameters to the service:
* A *pipeName* which is the name of the "pipe" it wants the .NET service to open in order to communicate
* A *pipeCount* which is the number of distinct "pipes" it wants the .NET service to open
* A *methodName* which can be used by one service to implement different methods

The simplest service application code would therefore look like:

```csharp
public static async Task Main(string[] args)
{
    var pipeName = args[0];
    var pipeCount = int.Parse(args[1]);

    await using var jetServer = new JetServer(pipeName, pipeCount);
    await jetServer.Serve<JetMessage<string, OtherThing>, JetMessage<string, SomeThing>>(request =>
    {
        var (key, value) = request;
        return request.RespondWith(key, new OtherThing { Value = $"__{value}__" });
    });
}
```

TODO: insert note about configuring the task, and serialization

## Java application

At the moment, defining the pipeline and submitting the corresponding job to the cluster still requires Java code.

NOTE: attached directories are NOT recursive! 
The Java application attaches one directory per platform (Windows, Linux...).
When executing, the `DotnetService` will only recreate the directory relevant to the local platform.
This means that it could be possible to submit the job to a cluster composed of mixed platforms.

Submit

```sh
hz-cli [options] submit path/to/submit.jar path/to/service
```

## Technical details

Communication between the Java job and the .NET service is implemented via efficient circular-buffer shared-memory IPC.