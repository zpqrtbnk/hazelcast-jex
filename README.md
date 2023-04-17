
# .NET Jet

A solution that allows users to run .NET transformations as part of a Jet pipeline,
by forking a .NET process and passing tasks between Java and .NET using a fast
shared-memory IPC mechanism.

From a high-level standpoint, this solution relies on:

* A `hazelcast-jet-dotnet` Java module that provides the Java-side plumbing
* A `Hazelcast.Net.Jet` .NET package that provides the .NET-side plumbing
* A .NET application that implements the .NET-side pipeline stage
* A Java application that defines the pipeline and submits it to the cluster

## Demonstration

### Clone this repository
Including its submodules:
```sh
git clone --recurse-submodules https://github.com/zpqrtbnk/hazelcast-jet-dotnet
```

### Build and pack the .NET client
(once stable, this step would *not* be required)
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
unzip hazelcast/distribution/target/hazelcast-5.3.0-SNAPSHOT.zip -d temp/hazelcast-5.3.0-SNAPSHOT
```

#### Build and publish the .NET service
```sh
cd dotnet-service
dotnet build
dotnet publish -c Release -r win-x64 -o target-sc/win-x64 --self-contained
dotnet publish -c Release -r win-x64 -o target/win-x64 --no-self-contained
dotnet publish -c Release -r win-x64 -o target-sc/linux-x64 --self-contained
dotnet publish -c Release -r win-x64 -o target/linux-x64 --no-self-contained
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
Connect...
Added entry: example-key-19 = SomeThing(Value=19)
Client has 2 schemas:
* typeName=other-thing id=-4539772739487884800
    value String
* typeName=some-thing id=5057135550981888295
    value Int32

Found result: example-key-19 = OtherThing(Value=__19__)
```

The added entry has been added to the `streamed-map` map, which has journaling enabled.
Thanks to journaling, the pipeline triggers and passes the entry value (a `SomeThing` object with an integer `Value` property) to the .NET transformation, which returns a transformed entry (a `OtherThing` object with a string `Value` property). The pipeline inserts this entry into a `result-map` map.
The example code then tries to find this entry in the map.

**FIXME: rest of this document is mostly junk to be cleaned up**

## Java `hazelcast-jet-dotnet`

A new `hazelcast-jet-dotnet` module is introduced in the `hazelcast` project.
Once stable, it would be deployed on members as part of the distribution. During the prototyping phase, it should *not* be included the distribution and should instead be attached to each job.

This module can:

This module exposes:
* Class `DotnetServiceConfig` which represents the configuration of the .NET service
* Class ...

## .NET `Hazelcast.Net.Jet`

A new `Hazelcast.Net.Jet` project is introduced in the `hazelcast-csharp-client` solution.
Once stable, it wolud be distributed as a separate package distributed on NuGet. During the prototyping phase, it must be built from the solution.

This project exposes the following classes:
* The `JetServer` class represents the server which processes requests from Java
* The `JetTask` class represents a task to be executed by the server for each request
* The `JetMessage` class represents a message exchanged between Java and .NET

## .NET application

An independent application is required, which will host the .NET server. This application will be started by Java when creating the job, on each member. The application can be a normal .NET application, in which case each member must have .NET installed and be able to execute .NET applications. Alternatively, it can be a self-contained single-file .NET executable, in which case nothing is required from the members.

```csharp
dotnet new console
dotnet add package Hazelcast.Net.Jet
dotnet build
dotnet publish -c Release -r win-x64 -o service/win-x64
dotnet publish -c Release -r linux-x64 -o service/linux-x64
dotnet publish -c Release -r osx-x64 -o service/osx-x64
```

The .NET service runs a `JetServer` instance, which handles the communication with Java.
The Jet server serves a `JetTask`.
A `JetTask` wraps a method that receives a request `JetMessage` and produces a response `JetMessage`.

A `JetMessage` consists in an array of `byte[]` buffers.

A `JetMessage<T>` is a `JetMessage` that knows that the first `byte[]` buffer is actually a `Data` serialized buffer, that the serialization service can de-serialize to an object of type `T`. In a similar way, a `JetMessage<T1, T2>` knows about the type of the first two buffers, etc. The strongly-typed objects can therefore be retrieved:

```csharp
// if request is a JetMessage<string, SomeThing>
var s = request.Item1;
var t = request.Item2;
// or, using deconstruction
var (s, t) = request;
```

```csharp
await using var jetServer = new JetServer(pipeName, pipeCount);
var jetTask = new JetTask<JetMessage<string, SomeThing>, JetMessage<string, OtherThing>>(request =>
{
    var (key, value) = request;
    return request.RespondWith(key, new OtherThing { Value = $"__{value}__" });
});
await jetServer.Serve(jetTask);
```

## Java application

At the moment, defining the pipeline and submitting the corresponding job to the cluster still requires Java code.


Submit

```sh
hz-cli [options] submit path/to/submit.jar path/to/service
```

## Technical details

Communication between the Java job and the .NET service is implemented via 