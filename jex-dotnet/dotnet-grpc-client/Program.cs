
using System.Text;
using Google.Protobuf;
using Grpc.Net.Client;
using Hazelcast.UserCode;
using Hazelcast.UserCode.Data;
using Hazelcast.UserCode.Transports.Grpc;
using Microsoft.Extensions.Options;

namespace Hazelcast.Demo.GrpcClient;

public class Program
{
    public static async Task Main()
    {
        Console.WriteLine("Schemas:");
        Console.WriteLine("  SomeThing: " + SomeThingSerializer.CompactSchema.Id);
        Console.WriteLine("  OtherThing: " + OtherThingSerializer.CompactSchema.Id);

        var hzoptions = new HazelcastOptionsBuilder()
            .With(o =>
            {
                o.Networking.Addresses.Add("localhost:5701");

                var compact = o.Serialization.Compact;

                // register serializers - we want this in order to use
                // the well-known polyglot type names and property names
                compact.AddSerializer(new SomeThingSerializer());
                compact.AddSerializer(new OtherThingSerializer());

                // client is *not* going to fetch schemas from a server
                // we have to provide them
                //compact.SetSchema<SomeThing>(SomeThingSerializer.CompactSchema, true);
                //compact.SetSchema<OtherThing>(OtherThingSerializer.CompactSchema, true);
            })
            .Build();

        await using (var hzclient = await HazelcastClientFactory.StartNewClientAsync(hzoptions))
        {
            await using var hzmap = await hzclient.GetMapAsync<string, SomeThing>("temp-map");
            await hzmap.SetAsync("key", new SomeThing()); // force the schema on the cluster
        }

        // now, the schema should be on the cluster
        // when the gRPC service receives a SomeThing instance
        // it will get the corresp schema from the server

        using var channel = GrpcChannel.ForAddress("http://localhost:5252");
        var grpc = new Transport.TransportClient(channel);
        var stream = grpc.invoke();
        var id = 0L;

        Console.WriteLine("--------");
        Console.WriteLine("send: .CONNECT");
        var connectMessage = new UserCodeMessage(id++, ".CONNECT", "localhost:5701"); // FIXME args?!
        await stream.RequestStream.WriteAsync(connectMessage.ToGrpcMessage());
        await stream.ResponseStream.MoveNext(CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(10));
        var response = stream.ResponseStream.Current.ToMessage();
        Console.WriteLine($"response: {response.FunctionName}");
        if (response.IsError)
        {
            Console.WriteLine("ERROR: " + response.PayloadString);
            return;
        }

        Console.WriteLine("--------");
        Console.WriteLine("send: methodNotSupported");
        var errMessage = new UserCodeMessage(id++, "methodNotSupported");
        await stream.RequestStream.WriteAsync(errMessage.ToGrpcMessage());
        await stream.ResponseStream.MoveNext(CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(10)); // FIXME use everywhere!
        response = stream.ResponseStream.Current.ToMessage();
        Console.WriteLine($"response: {response.FunctionName}");
        if (response.IsError)
        {
            Console.WriteLine("EXPECTED ERROR: " + response.PayloadString);
        }
        else
        {
            Console.WriteLine("ERROR: response is not error?!");
            return;
        }

        Console.WriteLine("--------");
        Console.WriteLine("send: doThingPython");
        var random = Random.Shared.Next(0, 100);
        var someThing= new SomeThing { Value = random };
        var input = IMapEntry.New($"key-{random}", someThing);

        var hazelcastOptions = new HazelcastOptionsBuilder()
            .With(options =>
            {
                var compact = options.Serialization.Compact;

                // register serializers - we want this in order to use
                // well-known polyglot type-name and property names
                compact.AddSerializer(new SomeThingSerializer());
                compact.AddSerializer(new OtherThingSerializer());

                // client is *not* going to fetch schemas from a server
                // we have to provide them
                compact.SetSchema<SomeThing>(SomeThingSerializer.CompactSchema, true);
                compact.SetSchema<OtherThing>(OtherThingSerializer.CompactSchema, true);
            })
            .Build();
        var client = new UserCodeClient(hazelcastOptions); // or pass the configure delegate?

        var payload = client.ToByteArray(input);
        var message = new UserCodeMessage(id++, "doThingPython", payload);
        await stream.RequestStream.WriteAsync(message.ToGrpcMessage());
        await stream.ResponseStream.MoveNext(CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(10)); // FIXME use everywhere!
        response = stream.ResponseStream.Current.ToMessage();
        Console.WriteLine($"response: {response.FunctionName}");
        if (response.IsError)
        {
            Console.WriteLine("ERROR: " + response.PayloadString);
            return;
        }

        var result = client.ToObject(response.PayloadBytes);
        Console.WriteLine("result:");
        Console.WriteLine(result);
        if (result is IMapEntry mapEntry)
        {
            Console.WriteLine($"key:   {mapEntry.GetKey<string>()?.ToString() ?? "<null>"}");
            Console.WriteLine($"value: {mapEntry.GetValue<OtherThing>()?.ToString() ?? "<null>"}");
            //Console.WriteLine($"value: {mapEntry.GetKey<object>()}");
        }

        Console.WriteLine("--------");
        Console.WriteLine("send: .END");
        var endMessage = new UserCodeMessage(id++, ".END");
        await stream.RequestStream.WriteAsync(endMessage.ToGrpcMessage());
        await stream.ResponseStream.MoveNext(CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(10));
        response = stream.ResponseStream.Current.ToMessage();
        Console.WriteLine($"response: {response.FunctionName}");
        if (response.IsError)
        {
            Console.WriteLine("ERROR: " + response.PayloadString);
            return;
        }

        Console.WriteLine("--------");
    }
}