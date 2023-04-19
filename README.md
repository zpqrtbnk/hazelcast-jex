
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

## Viridian Demonstration

In order to submit the job to Viridian, using SSL, one need to use the Enterprise command-line.
In the code below, `hz-cli` is from the Enterprise distribution.

As long as the .NET module is not part of that distribution, a `CLASSPATH` is required.

```sh
export CLASSPATH=temp/hazelcast-5.3.0-SNAPSHOT/lib/hazelcast-jet-dotnet-5.3.0-SNAPSHOT.jar
hz-cli -f viridian.yml submit \
    java-pipeline/target/dotnet-jet-1.0-SNAPSHOT.jar \
    -d dotnet-service/target-sc -x service
```

For now, we have two problems with Viridian
* Don't know how to enable journaling for the `streamed-map`
* Viridian fails to recreate the service directory = permission issue, will need a fix at Viridian platform level
  (but fixed on our test cluster)

* cannot attach subdirectories, refactoring...


(cd hazelcast && mvn install -DskipTests -Dcheckstyle.skip=true)
(cd java-pipeline && mvn package)
hz-cle -v -f viridian.yml submit java-pipeline/target/dotnet-jet-1.0-SNAPSHOT.jar -d dotnet-service/target-sc -x service

hz-cle -f hazelcast-client-with-ssl.yml submit /c/Users/sgay/Code/hazelcast-jet-dotnet/hazelcast/extensions/dotnet/tar
get/hazelcast-jet-dotnet-5.3.0-SNAPSHOT.jar     -d /c/Users/sgay/Code/hazelcast-jet-dotnet/dotnet-service/target-sc
-x service

WORKS??

hz-cle -f hazelcast-client-with-ssl.yml submit /c/Users/sgay/Code/hazelcast-jet-dotnet/java-pipeline/target/dotnet-jet-1.0-SNAPSHOT.jar -d /c/Users/sgay/Code/hazelcast-jet-dotnet/dotnet-service/target-sc -x service

FAILS??

**FIXME: rest of this document is mostly junk to be cleaned up**
**FIXME: rest of this document is mostly junk to be cleaned up**
**FIXME: rest of this document is mostly junk to be cleaned up**
**FIXME: rest of this document is mostly junk to be cleaned up**
**FIXME: rest of this document is mostly junk to be cleaned up**

## Java `hazelcast-jet-dotnet`

A new `hazelcast-jet-dotnet` module is introduced in the `hazelcast` project.
Once stable, it would be deployed on members as part of the distribution. During the prototyping phase, it should *not* be included the distribution and should instead be attached to each job.

This module implements the .NET pipeline stage.

This module exposes:
* Class `DotnetServiceConfig` which represents the configuration of the .NET service
* Class `DotnetService` which is the .NET service
* Class `JetMessage` which represents a message exchanged between Java and .NET
* Class `DotnetTransforms` which has only 1 static method and should merge with the service?
* Other things (service context...) which should not be exposed?

Plus all the internal plumbing to fork the .NET process and communicate with it.

## .NET `Hazelcast.Net.Jet`

A new `Hazelcast.Net.Jet` project is introduced in the `hazelcast-csharp-client` solution.
Once stable, it wolud be distributed as a separate package distributed on NuGet. During the prototyping phase, it must be built from the solution.

This project exposes the following classes:
* The `JetServer` class represents the server which processes requests from Java
* The `JetTask` class represents a task to be executed by the server for each request
* The `JetMessage` class represents a message exchanged between Java and .NET
* What else?

This package is meant to be used by users to create their .NET services.

## .NET service

An independent application is required, which will host the .NET service. This application will be started by Java when creating the job, on each member. The application can be a normal .NET application, in which case each member must have .NET installed and be able to execute .NET applications. Alternatively, it can be a self-contained .NET executable, in which case nothing is required from the members.

```csharp
dotnet new console
dotnet add package Hazelcast.Net.Jet
(edits...)
dotnet build
dotnet publish -c Release -r win-x64 -o target-sc/win-x64 --self-contained
```

The executable needs to be published for the target platforms that run members. This can be `win-x64` if all members run Windows, or `linux-x64` or `osx-x64` if they run Linux or MacOS. It can also be a combination of platforms: the Java module will pick the appropriate executable depending on the executing platform.

From an application standpoint, the `Main` method needs to create and execute a `JetServer` instance, which handles the communication with Java. A `JetServer` serves a `JetTask`, which wraps a method that receives a request `JetMessage` and must produce a response `JetMessage`.

A `JetMessage` is, in its most simple form, an array of `byte[]` coming from Java. However, strongly-types messages already exist. For instance, a `JetMessage<T>` is a `JetMessage` that knows that its first `byte[]` buffer is actually a `Data` serialized buffer, that the serialization service can de-serialize to an object of type `T`. In a similar way, a `JetMessage<T1, T2>` knows about the type of the first two buffers, etc. And, serialization is managed transparently.

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

    var jetTask = new JetTask<JetMessage<string, SomeThing>, JetMessage<string, OtherThing>>(request =>
    {
        var (key, value) = request;
        return request.RespondWith(key, new OtherThing { Value = $"__{value}__" });
    });

    await using var jetServer = new JetServer(pipeName, pipeCount);
    await jetServer.Serve(jetTask);
}
```

TODO: insert note about configuring the task, and serialization

## Java application

At the moment, defining the pipeline and submitting the corresponding job to the cluster still requires Java code.

NOTE: attached directories are NOT recursive!!!!

Submit

```sh
hz-cli [options] submit path/to/submit.jar path/to/service
```

## Technical details

Communication between the Java job and the .NET service is implemented via 