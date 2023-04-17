
# .NET Jet

A .NET Jet solution is composed of four moving parts:

* A `hazelcast-jet-dotnet` Java module that provides the Java-side plumbing
* A `Hazelcast.Net.Jet` .NET package that provides the .NET-side plumbing
* A .NET application that implements the .NET-side pipeline stage
* A Java application that defines the pipeline and submits it to the cluster

git clone --recurse-submodules https://github.com/chaconinc/MainProject

## Demonstration

Clone this repository, including its submodules:
```sh
git clone --recurse-submodules https://github.com/zpqrtbnk/hazelcast-jet-dotnet
```

Build and pack the .NET client:
(once stable, this step would *not* be required)
```sh
cd hazelcast-csharp-client
pwsh ./hz.ps1 build,pack-nuget
```

Build the Hazelcast:
(once stable, this step would *not* be required)
(good luck with this)

Build and publish the .NET service:
```sh
cd dotnet-service
dotnet build
dotnet publish -c Release -r win-x64 -o target-sc/win-x64 --self-contained
dotnet publish -c Release -r win-x64 -o target/win-x64 --no-self-contained
dotnet publish -c Release -r win-x64 -o target-sc/linux-x64 --self-contained
dotnet publish -c Release -r win-x64 -o target/linux-x64 --no-self-contained
```

Build the Java pipeline definition:
```sh
cd java-pipeline
mvn package
```

Submit the 
```sh
hz-cli [options] $HZJAVA/extensions/dotnet/target/hazelcast-jet-dotnet-5.3.0-SNAPSHOT.jar \
                 -d dotnet-service/target-sc -x service
```

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

## Demonstration

Clone the `hazelcast-jet-dotnet` repository from `zpqrtbnk` with its submodules.

In the `hazelcast` directory, which should contain the `hazelcast` repository, build.
This will notably create the `hazelcast-jet-dotnet-5.3.0-SNAPSHOT.jar` in ??

In the `hazelcast-csharp-client`, which should contain the `hazelcast-csharp-client` repository, build.

Clone the `hazelcast-csharp-client` repository from `zpqrtbnk` and check out the `hazelcast-jet-dotnet` branch. Build (execute `./hz.ps1 build` from Powershell). This will notably create...

## Technical details

Communication between the Java job and the .NET service is implemented via 