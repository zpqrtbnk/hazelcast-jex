
using System.Text;
using Google.Protobuf;
using Grpc.Net.Client;
using Hazelcast.UserCode;
using Hazelcast.UserCode.Data;
using Hazelcast.UserCode.Transports.Grpc;
using Microsoft.Extensions.Options;
using Hazelcast.Jet;
using System.Globalization;
using Ionic.Zip;
using Hazelcast.DistributedObjects;
using Microsoft.Extensions.Logging;

namespace Hazelcast.Demo.GrpcClient;

public class Program
{
    public static async Task Main()
    {
        var hzoptions = new HazelcastOptionsBuilder()
            .With(o =>
            {
                o.Networking.Addresses.Add("localhost:5701");

                var compact = o.Serialization.Compact;

                // register serializers - we want this in order to use
                // the well-known polyglot type names and property names
                compact.AddSerializer(new SomeThingSerializer());
                compact.AddSerializer(new OtherThingSerializer());
            })
            .Build();

        // prepare
        string jobId;

        // FIXME understand
        // both the runtime and the client know about the serializers
        await using (var hzclient = await HazelcastClientFactory.StartNewClientAsync(hzoptions))
        {
            await using var hzmap = await hzclient.GetMapAsync<string, SomeThing>("temp-map");
            await hzmap.SetAsync("key", new SomeThing()); // force the schema on the cluster

            var jobNumId = await NewJobIdAsync(hzclient);
            jobId = JobIdToString(jobNumId);

            // upload the resource named resuilops
            var resourceId = "usercode";
            var path = "../../hazelcast-usercode/python/example";
            await UploadDirectoryResourceAsync(hzclient, jobNumId, resourceId, path);
            Console.WriteLine("Uploaded resource.");
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
        // var connectArgs = @"
        // {
        //     ""job"": {
        //         ""id"": ""%%JOBID%%"",
        //         ""resources"": [
        //             {
        //                 ""type"": ""DIRECTORY"",
        //                 ""id"": ""usercode""
        //             }
        //         ]
        //     },
        //     ""cluster"": {
        //         ""name"": ""dev"",
        //         ""address"": ""localhost:5701""
        //     }
            
        // }
        // ";
        var connectArgs = @"
        {
            ""job"": {
                ""id"": ""%%JOBID%%""
            },
            ""cluster"": {
                ""name"": ""dev"",
                ""address"": ""localhost:5701""
            }
            
        }
        ";
        connectArgs = connectArgs.Replace("%%JOBID%%", jobId);
        var connectMessage = new UserCodeMessage(id++, UserCodeMessageType.Connect, connectArgs);
        await stream.RequestStream.WriteAsync(connectMessage.ToGrpcMessage());
        await stream.ResponseStream.MoveNext(CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(10));
        var response = stream.ResponseStream.Current.ToMessage();
        Console.WriteLine($"response: {response.Type}");
        if (response.IsError)
        {
            Console.WriteLine("ERROR: " + response.PayloadString);
            return;
        }

        //Console.WriteLine("--------");
        //Console.WriteLine("send: methodNotSupported");
        //var errMessage = new UserCodeMessage(id++, "methodNotSupported");
        //await stream.RequestStream.WriteAsync(errMessage.ToGrpcMessage());
        //await stream.ResponseStream.MoveNext(CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(10)); // FIXME use everywhere!
        //response = stream.ResponseStream.Current.ToMessage();
        //Console.WriteLine($"response: {response.FunctionName}");
        //if (response.IsError)
        //{
        //    Console.WriteLine("EXPECTED ERROR: " + response.PayloadString);
        //}
        //else
        //{
        //    Console.WriteLine("ERROR: response is not error?!");
        //    return;
        //}

        Console.WriteLine("--------");
        Console.WriteLine("send: .USER_CODE");
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
            })
            .Build();
        var client = await UserCodeClient.StartNew(hazelcastOptions); // or pass the configure delegate?

        var payload = await client.ToByteArray(input);
        var message = new UserCodeMessage(id++, UserCodeMessageType.UserCode, payload);
        await stream.RequestStream.WriteAsync(message.ToGrpcMessage());
        await stream.ResponseStream.MoveNext(CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(10)); // FIXME use everywhere!
        response = stream.ResponseStream.Current.ToMessage();
        Console.WriteLine($"response: {response.Type}");
        if (response.IsError)
        {
            Console.WriteLine("ERROR: " + response.PayloadString);
            return;
        }

        var result = await client.ToObject<object>(response.PayloadBytes);
        Console.WriteLine("result:");
        Console.WriteLine(result);
        if (result is IMapEntry mapEntry)
        {
            Console.WriteLine($"key:   {mapEntry.GetKey<string>()?.ToString() ?? "<null>"}");
            Console.WriteLine($"value: {mapEntry.GetValue<OtherThing>()?.ToString() ?? "<null>"}");
            //Console.WriteLine($"value: {mapEntry.GetKey<object>()}");
        }

        Console.WriteLine("--------");
        Console.WriteLine("send: .COPY");
        var fileObject = new FileObject {Path = "path/to/random-file.txt", Bytes = File.ReadAllBytes("random-file.txt")};
        payload = await client.ToByteArray(fileObject);
        var copyMessage = new UserCodeMessage(id++, UserCodeMessageType.Copy, payload);
        await stream.RequestStream.WriteAsync(copyMessage.ToGrpcMessage());
        await stream.ResponseStream.MoveNext(CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(10));
        response = stream.ResponseStream.Current.ToMessage();
        Console.WriteLine($"response: {response.Type}");
        if (response.IsError)
        {
            Console.WriteLine("ERROR: " + response.PayloadString);
            return;
        }

        Console.WriteLine("--------");
        Console.WriteLine("send: .COPY_ZIP");
        fileObject = new FileObject { Path = "path/to/random-file.txt", ChunkCount = 1, ChunkNumber = 0, Bytes = File.ReadAllBytes("random-file.txt") };
        payload = await client.ToByteArray(fileObject);
        copyMessage = new UserCodeMessage(id++, UserCodeMessageType.CopyZip, payload);
        await stream.RequestStream.WriteAsync(copyMessage.ToGrpcMessage());
        await stream.ResponseStream.MoveNext(CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(10));
        response = stream.ResponseStream.Current.ToMessage();
        Console.WriteLine($"response: {response.Type}");
        if (response.IsError)
        {
            Console.WriteLine("ERROR: " + response.PayloadString);
        }
        else
        {
            Console.WriteLine("ERROR: SHOULD HAVE FAILED");
            return;
        }

        Console.WriteLine("--------");
        Console.WriteLine("send: .COPY");
        fileObject = new FileObject { Path = "/path/to/random-file.txt", ChunkCount = 1, ChunkNumber = 0, Bytes = File.ReadAllBytes("random-file.txt") };
        payload = await client.ToByteArray(fileObject);
        copyMessage = new UserCodeMessage(id++, UserCodeMessageType.Copy, payload);
        await stream.RequestStream.WriteAsync(copyMessage.ToGrpcMessage());
        await stream.ResponseStream.MoveNext(CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(10));
        response = stream.ResponseStream.Current.ToMessage();
        Console.WriteLine($"response: {response.Type}");
        if (response.IsError)
        {
            Console.WriteLine("ERROR: " + response.PayloadString);
        }
        else
        {
            Console.WriteLine("ERROR: SHOULD HAVE FAILED");
            return;
        }

        Console.WriteLine("--------");
        Console.WriteLine("send: .COPY");
        fileObject = new FileObject { Path = "path/../../../to/random-file.txt", ChunkCount = 1, ChunkNumber = 0, Bytes = File.ReadAllBytes("random-file.txt") };
        payload = await client.ToByteArray(fileObject);
        copyMessage = new UserCodeMessage(id++, UserCodeMessageType.Copy, payload);
        await stream.RequestStream.WriteAsync(copyMessage.ToGrpcMessage());
        await stream.ResponseStream.MoveNext(CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(10));
        response = stream.ResponseStream.Current.ToMessage();
        Console.WriteLine($"response: {response.Type}");
        if (response.IsError)
        {
            Console.WriteLine("ERROR: " + response.PayloadString);
        }
        else
        {
            Console.WriteLine("ERROR: SHOULD HAVE FAILED");
            return;
        }

        Console.WriteLine("--------");
        Console.WriteLine("send: .COPY_ZIP");
        fileObject = new FileObject { Path = "path/to/random-file.zip", ChunkCount = 1, ChunkNumber = 0, Bytes = File.ReadAllBytes("random-file.zip") };
        payload = await client.ToByteArray(fileObject);
        copyMessage = new UserCodeMessage(id++, UserCodeMessageType.CopyZip, payload);
        await stream.RequestStream.WriteAsync(copyMessage.ToGrpcMessage());
        await stream.ResponseStream.MoveNext(CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(10));
        response = stream.ResponseStream.Current.ToMessage();
        Console.WriteLine($"response: {response.Type}");
        if (response.IsError)
        {
            Console.WriteLine("ERROR: " + response.PayloadString);
            return;
        }

        Console.WriteLine("--------");
        Console.WriteLine("send: .COPY_ZIP");
        fileObject = new FileObject { Path = "random-file.zip", ChunkCount = 1, ChunkNumber = 0, Bytes = File.ReadAllBytes("random-file.zip") };
        payload = await client.ToByteArray(fileObject);
        copyMessage = new UserCodeMessage(id++, UserCodeMessageType.CopyZip, payload);
        await stream.RequestStream.WriteAsync(copyMessage.ToGrpcMessage());
        await stream.ResponseStream.MoveNext(CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(10));
        response = stream.ResponseStream.Current.ToMessage();
        Console.WriteLine($"response: {response.Type}");
        if (response.IsError)
        {
            Console.WriteLine("ERROR: " + response.PayloadString);
            return;
        }

        Console.WriteLine("--------");
        Console.WriteLine("send: .END");
        var endMessage = new UserCodeMessage(id++, UserCodeMessageType.End);
        await stream.RequestStream.WriteAsync(endMessage.ToGrpcMessage());
        await stream.ResponseStream.MoveNext(CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(10));
        response = stream.ResponseStream.Current.ToMessage();
        Console.WriteLine($"response: {response.Type}");
        if (response.IsError)
        {
            Console.WriteLine("ERROR: " + response.PayloadString);
            return;
        }

        Console.WriteLine("--------");
    }

    public static async Task<long> NewJobIdAsync(IHazelcastClient client)
    {
        await using var jetIdGenerator = await client.GetFlakeIdGeneratorAsync("__jet.ids");
        return await jetIdGenerator.GetNewIdAsync();
    }

    public static string JobIdToString(long jobId)
    {
        var buf = "0000-0000-0000-0000".ToCharArray();
        var hexStr = jobId.ToString("x");
        for (int i = hexStr.Length - 1, j = 18; i >= 0; i--, j--)
        {
            buf[j] = hexStr[i];
            if (j == 15 || j == 10 || j == 5)
            {
                j--;
            }
        }
        return new string(buf);
    }

    public static long JobIdFromString(string jobIdString)
    {
        // note: job ID will show as 0000-0000-0000-0000 on the platform ie 64bit long
        return long.Parse(jobIdString.Replace("-", ""), NumberStyles.HexNumber);
    }

    private static async Task UploadDirectoryResourceAsync(IHazelcastClient client, long jobId, string resourceId, string path)
    {
        // prefix is f. for file, c. for class (see job repository)
        //var id = Path.GetFileName(path);
        //var key = $"f.dotnet-{id}-";
        var key = $"f.{resourceId}";
        var rnd = Guid.NewGuid().ToString("N").Substring(0, 9);
        var zipPath = Path.Combine(Path.GetTempPath(), rnd + "-" + resourceId + ".zip");

        //Console.WriteLine($"upload {id} with key {key}");

        using (var zipFile = new ZipFile())
        {
            zipFile.CompressionMethod = CompressionMethod.Deflate;
            zipFile.AddDirectory(path);
            zipFile.Save(zipPath);
        }

        var logger = client.Options.LoggerFactory.CreateLogger("Program");
        try
        {
            var resourcesMapName = $"__jet.resources.{JobIdToString(jobId)}";
            await using var jobResources = await client.GetMapAsync<string, byte[]>(resourcesMapName);
            await new MapOutputStream(jobResources, key, logger).WriteFileAsync(zipPath);
        }
        finally
        {
            File.Delete(zipPath);
        }
    }
}

internal class MapOutputStream
{
    private const int ChunkSize = 1 << 17;

    private readonly IHMap<string, byte[]> _map;
    private readonly string _prefix;
    private readonly ILogger _logger;

    public MapOutputStream(IHMap<string, byte[]> map, string prefix, ILogger logger)
    {
        _map = map;
        _prefix = prefix;
        _logger = logger;
    }

    public async Task WriteFileAsync(string path)
    {
        var buffer = new byte[ChunkSize];
        var read = 1;
        var chunkIndex = 0;

        await using var fileStream = File.OpenRead(path);

        while (read > 0)
        {
            var readCount = 0;

            do
            {
                read = await fileStream.ReadAsync(buffer, readCount, buffer.Length - readCount);
                readCount += read;
            } while (readCount < buffer.Length && read != 0);

            if (readCount > 0)
            {
                if (readCount != buffer.Length)
                {
                    var buffer2 = new byte[readCount];
                    Array.Copy(buffer, buffer2, readCount);
                    buffer = buffer2;
                }

                _logger.LogDebug("upload chunk size " + buffer.Length + " bytes, to " + _prefix + "_" + chunkIndex);
                await _map.SetAsync(_prefix + "_" + chunkIndex++, buffer);
            }
        }

        buffer = new byte[4/*BytesExtensions.SizeOfInt*/];
        /*buffer.WriteInt(0, chunkIndex, Endianness.BigEndian);*/
        var value = chunkIndex;
        var unsigned = (uint) value;
        var position = 0;
        buffer[position] = (byte) (unsigned >> 24);
        buffer[position + 1] = (byte) (unsigned >> 16);
        buffer[position + 2] = (byte) (unsigned >> 8);
        buffer[position + 3] = (byte) unsigned;

        await _map.SetAsync(_prefix, buffer);
    }
}