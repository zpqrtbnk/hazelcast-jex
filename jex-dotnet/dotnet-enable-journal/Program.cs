using Hazelcast.Demo;

namespace Hazelcast.Jex;

using Hazelcast;
using Hazelcast.Jet; // though it should NOT be there
using System.Security.Authentication;
using System.Text.Json;

public class Program
{
    public static async Task Main(string[] args)
    {
        if (args.Length != 1)
        {
            Console.WriteLine("usage: enable <config>");
            return;
        }

        var options = new HazelcastOptionsBuilder()
           //.With(args)
           .WithSecrets(args[0])
           .Build();
        await using var client = await HazelcastClientFactory.StartNewClientAsync(options);
        await client.EnableMapJournal("streamed-map");
    }
}

