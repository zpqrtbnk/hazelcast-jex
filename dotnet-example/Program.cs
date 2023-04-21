using System;
using System.Threading.Tasks;
using Hazelcast;
using Hazelcast.DistributedObjects;
using Hazelcast.Serialization.Compact;
using System.Security.Authentication;

namespace Hazelcast.Jet.Example;

public class Program
{
    public static async Task Main(string[] args)
    {
        Console.WriteLine("Connect to cluster...");

        var options = BuildOptions(args);
        await using var client = await HazelcastClientFactory.StartNewClientAsync(options);

        Console.WriteLine("Connected");

        await using var sourceMap = await client.GetMapAsync<string, SomeThing>("streamed-map");
        await using var resultMap = await client.GetMapAsync<string, OtherThing>("result-map");

        // DEBUG
        //await DumpMap(sourceMap);
        //await DumpMap(resultMap);
        //Console.WriteLine(SchemaBuilder.ReportSchemas(client));

        // first time the example runs on the cluster, the client does not know about the schema
        // for OtherThing, and *neither* does the cluster = fail. setting a dummy value generates
        // the schema on the client
        await resultMap.SetAsync("dummy", new OtherThing());
        
        // insert a value in source
        var random = Random.Shared.Next(100);
        var key = "example-key-" + random;
        var value = new SomeThing { Value = random };
        Console.WriteLine($"Add entry to streamed-map: {key} = {value}");
        await sourceMap.SetAsync(key, value);
        Console.WriteLine("Added");

        // find value in result
        Console.WriteLine($"wait for entry with key {key} to appear in result-map");
        OtherThing result;
        var maxAttempts = 30;
        while ((result = await resultMap.GetAsync(key)) == null && --maxAttempts > 0)
            await Task.Delay(1000);

        Console.WriteLine(maxAttempts == 0 ? "Failed" : $"Found: {key} = {result}");
    }

    private static HazelcastOptions BuildOptions(String[] args)
    {

        return new HazelcastOptionsBuilder()
            .With(args)
            .With(o => {
                // must have a jet-enabled cluster with the job running
                // we'll provide these via command-line arguments
                //o.ClusterName = "dev";
                //o.Networking.Addresses.Add("127.0.0.1:5701");
                //o.Networking.Addresses.Add("192.168.1.49:5701");

                o.Networking.ConnectionRetry.ClusterConnectionTimeoutMilliseconds = 4000;

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

   }

    private static async Task DumpMap<TKey, TResult>(IHMap<TKey, TResult> map)
    {
        Console.WriteLine($"Entries in '{map.Name}' map:");
        await foreach (var entry in map)
            Console.WriteLine($"  {entry.Key}: {entry.Value}");
    }
}