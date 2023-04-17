using System;
using System.Threading.Tasks;
using Hazelcast.Serialization.Compact;
using System.Security.Authentication;

namespace Hazelcast.Jet.Example;

public class Program
{
    public static async Task Main(string[] args)
    {
        

        var localOptions = new HazelcastOptionsBuilder()
            .With(args)
            .With(o => {
                // must have a jet-enabled cluster with the job running
                o.ClusterName = "dev";
                //o.Networking.Addresses.Add("127.0.0.1:5701");
                //o.Networking.Addresses.Add("192.168.1.49:5701");
                //o.Networking.ConnectionRetry.ClusterConnectionTimeoutMilliseconds = 4000;

                var compact = o.Serialization.Compact;

                // add serializers so that we have the polyglot type name
                compact.AddSerializer(new SomeThingSerializer());
                compact.AddSerializer(new OtherThingSerializer());

                // BUT with this only, we have 'Value' fields instead of 'value'
                // use the reflection serializer BUT use the polyglot type name
                //compact.SetTypeName<SomeThing>("some-thing");
                //compact.SetTypeName<OtherThing>("other-thing");

            })
            .Build();

        var options = localOptions;

        Console.WriteLine("Connect...");
        await using var client = await HazelcastClientFactory.StartNewClientAsync(options);

        await using var sourceMap = await client.GetMapAsync<string, SomeThing>("streamed-map");
        await using var resultMap = await client.GetMapAsync<string, OtherThing>("result-map");

        //Console.WriteLine("In source map:");
        //await foreach (var entry in sourceMap)
        //    Console.WriteLine($"  {entry.Key}: {entry.Value}");

        //Console.WriteLine("In result map:");
        //await foreach (var entry in resultMap)
        //    Console.WriteLine($"  {entry.Key}: {entry.Value}");

        // first time the example runs on the cluster, the client does not know about the schema
        // for OtherThing, and *neither* does the cluster = fail. setting a dummy value generates
        // the schema on the client
        await resultMap.SetAsync("dummy", new OtherThing());
        
        // insert a value in source
        var random = Random.Shared.Next(100);
        var key = "example-key-" + random;
        var value = new SomeThing { Value = random };
        await sourceMap.SetAsync(key, value);
        Console.WriteLine($"Added entry: {key} = {value}");

        // FIXME DEBUGGING
        Console.WriteLine(SchemaBuilder.ReportSchemas(client));

        // find value in result
        OtherThing result;
        var maxAttempts = 30;
        while ((result = await resultMap.GetAsync(key)) == null && --maxAttempts > 0)
            await Task.Delay(1000);

        Console.WriteLine(maxAttempts == 0 ? "Failed" : $"Found result: {key} = {result}");
    }
}