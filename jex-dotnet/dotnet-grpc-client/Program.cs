using Grpc.Net.Client;
using Hazelcast.UserCode.Data;
using Hazelcast.UserCode.ClientServer.Data;
using Hazelcast.UserCode.ClientServer;
using Hazelcast.UserCode.ClientServer.Grpc;
using System.Globalization;
using Grpc.Core;
using System.IO.Compression;
using Hazelcast.DistributedObjects;
using Hazelcast.UserCode.ClientServer.Grpc.Proto;
using Microsoft.Extensions.Logging;

namespace Hazelcast.Demo.GrpcClient;

public class Program
{
    private const int GrpcMessageMaxSize = 2 * 1024 * 1024; // is 2MB ok?
    private static readonly TimeSpan GrpcTimeout = TimeSpan.FromSeconds(120); // longer that the CONNECT timeout, server-side

    private class GrpcCall : IDisposable
    {
        private readonly GrpcChannel _channel;
        private readonly AsyncDuplexStreamingCall<Message, Message> _stream;

        private GrpcCall(GrpcChannel channel, AsyncDuplexStreamingCall<Message, Message> stream)
        {
            _channel = channel;
            _stream = stream;
        }

        public static GrpcCall Open(string address, GrpcChannelOptions options)
        {
            var channel = GrpcChannel.ForAddress(address, options);
            var grpc = new Hazelcast.UserCode.ClientServer.Grpc.Proto.Transport.TransportClient(channel);
            var stream = grpc.invoke();
            return new GrpcCall(channel, stream);
        }

        public IClientStreamWriter<Message> RequestStream => _stream.RequestStream;

        public IAsyncStreamReader<Message> ResponseStream => _stream.ResponseStream;

        public MessageIdProvider MessageId { get; } = new MessageIdProvider();

        public void Dispose()
        {
            _stream.Dispose();
            _channel.Dispose();
        }
    }

    public static async Task Main()
    {
/*
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
*/
	string jobId = "";

        // now, the schema should be on the cluster
        // when the gRPC service receives a SomeThing instance
        // it will get the corresp schema from the server

        // configure gRPC, see: https://learn.microsoft.com/en-us/aspnet/core/grpc/configuration
        var grpcOptions = new GrpcChannelOptions();
        using var call1 = GrpcCall.Open("http://localhost:5252", grpcOptions);

        // let's pretend that *we* are the usercode for now
        // in reality, would need to send the code for the proper platform/architecture
        // and... how can we know? should we be able to ASK the runtime for this?
        var thisDll = typeof(Program).Assembly.Location;
        if (!await SendCopyDirectory(call1, "usercode", Path.GetDirectoryName(thisDll))) return;

        // connect
        if (!await SendConnect(call1, "dev", "localhost:5701", jobId))
        {
            return;
        }

        // prepare a client
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

        static bool WriteResult(object result)
        {
            Console.WriteLine("result:");
            switch (result)
            {
                case string s:
                    Console.WriteLine($"string: {s}");
                    break;
                case IMapEntry mapEntry:
                    Console.WriteLine($"key:   {mapEntry.GetKey<string>()?.ToString() ?? "<null>"}");
                    Console.WriteLine($"value: {mapEntry.GetValue<OtherThing>()?.ToString() ?? "<null>"}");
                    break;
                case null:
                    Console.WriteLine("<null>");
                    return false; // error
                default:
                    Console.WriteLine($"{result.GetType()}: {result}");
                    break;
            }

            return true;
        }

        // user code
        var result = await SendUserCode(call1, client, "this is a test");
        if (!WriteResult(result)) return;

        // user code
        result = await SendUserCode(call1, client, "this is another test");
        if (!WriteResult(result)) return;

        // test file copy
        if (await SendCopyZip(call1, "path/to/random-file.txt", "Program.cs"))
        {
            Console.WriteLine("error: should have failed (not a valid zip)");
            return;
        }

        if (await SendCopy(call1, "/path/to/random-file.txt", "Program.cs"))
        {
            Console.WriteLine("error: should have failed (path is absolute)");
            return;
        }

        if (await SendCopy(call1, "path/../../../to/random-file.txt", "Program.cs"))
        {
            Console.WriteLine("error: should have failed (path leads to outside of resources directory)");
            return;
        }

        if (await SendCopyDirectory(call1, "..", Path.GetDirectoryName(thisDll)))
        {
            Console.WriteLine("error: should have failed (path leads to outside of resources directory)");
            return;
        }

        if (await SendCopyDirectory(call1, "", Path.GetDirectoryName(thisDll)))
        {
            Console.WriteLine("error: should have failed (no path)");
            return;
        }

        // end
        if (!await SendEnd(call1)) return;

        // after END has been sent, the client MUST terminate the gRPC call
        call1.Dispose();

        // FIXME that won't work if the DLL name is not expected by the server
        // well well well...

        // and open a new one if needed
        using var call2 = GrpcCall.Open("http://localhost:5252", grpcOptions);

        // FIXME
        // in Python we can do res:usercode and that is the path to the directory
        // in .NET we do res:usercode/MyCode.dll and that is the path to the dll
        // these are just conventions, or?!
        // should we say that the path is always the path to a directory
        // and the name is dll+type?
        // but in Python you cannot rename the Transform method...
        //
        // and then...
        // this fails to load dotnet-usercode.dll dependencies such as dotnet-common.dll

        // again
        if (await SendConnect(call2, "dev", "localhost:5701", jobId, usercodeFile: "res:usercode/dotnet-usercode.dll"))
        {
            Console.WriteLine("error: should have failed, no user code");
            return;
        }

        // copy
        var otherDir = "../dotnet-usercode/bin/Debug/net7.0";
        if (!await SendCopyDirectory(call2, "usercode", otherDir)) return;

        // again
        // AND we have modified the usercodeFile, no need to set it here again
        if (!await SendConnect(call2, "dev", "localhost:5701", jobId)) return;

        // user code
        var random = Random.Shared.Next(0, 100);
        var someThing = new SomeThing { Value = random };
        var input = IMapEntry.New($"key-{random}", someThing);
        result = await SendUserCode(call2, client, input);
        if (!WriteResult(result)) return;

        // end
        if (!await SendEnd(call2)) return;
        call2.Dispose();

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

        // FIXME redo with non-IONIC
        //using (var zipFile = new ZipFile())
        //{
        //    zipFile.CompressionMethod = CompressionMethod.Deflate;
        //    zipFile.AddDirectory(path);
        //    zipFile.Save(zipPath);
        //}

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

    private static async Task<object?> SendUserCode(GrpcCall call,
        UserCodeClient client,
        object input)
    {
        var payload = await client.ToByteArray(input);
        var responsePayload = await SendUserCode(call, payload);
        if (responsePayload == null) return null;
        return await client.ToObject<object>(responsePayload);
    }

    private static async Task<bool> SendConnect(GrpcCall call,
        string clusterName, string clusterAddress, string jobId, 
        string? usercodeFile = null, string? usercodeType = null)
    {
        var connectArgs = $@"
        {{
            ""job"": {{
                ""id"": ""{jobId}""
            }},
            ""cluster"": {{
                ""name"": ""{clusterName}"",
                ""address"": ""{clusterAddress}""
            }},
            ""usercode"": {{
                {(usercodeFile == null ? "" : $"\"file\": \"{usercodeFile}\"")}
                {(usercodeFile != null && usercodeType != null ? ", " : "")}
                {(usercodeType == null ? "" : $"\"type\": \"{usercodeType}\"")}
            }}
        }}
        ";

        Console.WriteLine("--------");
        Console.WriteLine("send: .CONNECT");
        var copyMessage = new UserCodeMessage(call.MessageId.Next(), UserCodeMessageType.Connect, connectArgs);
        await call.RequestStream.WriteAsync(copyMessage.ToGrpcMessage());
        await call.ResponseStream.MoveNext(CancellationToken.None).WaitAsync(GrpcTimeout);
        var response = call.ResponseStream.Current.ToMessage();
        if (response.IsError)
        {
            Console.WriteLine("error: " + response.PayloadString);
            return false;
        }

        Console.WriteLine("success");
        return true;
    }

    private static async Task<byte[]?> SendUserCode(GrpcCall call,
        byte[] input)
    {
        Console.WriteLine("--------");
        Console.WriteLine("send: .USER_CODE");
        var copyMessage = new UserCodeMessage(call.MessageId.Next(), UserCodeMessageType.UserCode, input);
        await call.RequestStream.WriteAsync(copyMessage.ToGrpcMessage());
        await call.ResponseStream.MoveNext(CancellationToken.None).WaitAsync(GrpcTimeout);
        var response = call.ResponseStream.Current.ToMessage();
        if (response.IsError)
        {
            Console.WriteLine("error: " + response.PayloadString);
            return null;
        }

        Console.WriteLine("success");
        return response.PayloadBytes;
    }

    private static async Task<bool> SendEnd(GrpcCall call)
    {
        Console.WriteLine("--------");
        Console.WriteLine("send: .END");
        var payload = Array.Empty<byte>();
        var copyMessage = new UserCodeMessage(call.MessageId.Next(), UserCodeMessageType.End, payload);
        await call.RequestStream.WriteAsync(copyMessage.ToGrpcMessage());
        await call.ResponseStream.MoveNext(CancellationToken.None).WaitAsync(GrpcTimeout);
        var response = call.ResponseStream.Current.ToMessage();
        if (response.IsError)
        {
            Console.WriteLine("error: " + response.PayloadString);
            return false;
        }

        Console.WriteLine("success");
        return true;
    }

    private static async Task<bool> SendCopyDirectory(GrpcCall call,
        string path, string directory)
    {
        if (!Path.IsPathRooted(directory)) directory = Path.Combine(Directory.GetCurrentDirectory(), directory);
        directory = Path.GetFullPath(directory);
        if (!Directory.Exists(directory))
        {
            throw new Exception($"err: directory {directory} does not exist.");
        }
        var zipFile = Path.Join(Path.GetTempPath(), $"hz-zip-{Guid.NewGuid()}.zip");
        ZipFile.CreateFromDirectory(directory, zipFile);
        var success = await SendCopyZip(call, path, zipFile);
        File.Delete(zipFile);
        return success;
    }

    private static async Task<bool> SendCopy(GrpcCall call,
        string resourcePath, byte[] bytes, bool zip, int chunkCount, int chunkNumber)
    {
        Console.WriteLine("--------");
        Console.WriteLine($"send: .COPY{(zip ? "_ZIP" : "")} {chunkNumber+1}/{chunkCount}");
        var fileObject = new FileObject {Path = resourcePath, Bytes = bytes, ChunkCount = chunkCount, ChunkNumber = chunkNumber};
        var payload = fileObject.ToByteArray();
        var copyMessage = new UserCodeMessage(call.MessageId.Next(), zip ? UserCodeMessageType.CopyZip : UserCodeMessageType.Copy, payload);
        await call.RequestStream.WriteAsync(copyMessage.ToGrpcMessage());
        await call.ResponseStream.MoveNext(CancellationToken.None).WaitAsync(GrpcTimeout);
        var response = call.ResponseStream.Current.ToMessage();
        if (response.IsError)
        {
            Console.WriteLine("error: " + response.PayloadString);
            return false;
        }

        Console.WriteLine("success");
        return true;
    }

    private static async Task<bool> SendCopy(GrpcCall call,
        string resourcePath, string bytesPath, bool zip, int chunkSize)
    {
        var bytes = await File.ReadAllBytesAsync(bytesPath);
        var len = bytes.Length;
        var pos = 0;
        var chunkCount = (int) Math.Ceiling( (double) len / chunkSize );
        var chunkNumber = 0;
        while (len > 0)
        {
            var size = len > chunkSize ? chunkSize : len;
            var payload = new byte[size];
            Array.Copy(bytes, pos, payload, 0, size);
            if (!await SendCopy(call, resourcePath, payload, zip, chunkCount, chunkNumber++)) return false;
            pos += chunkSize;
            len -= chunkSize;
        }
        return true;
    }

    private static Task<bool> SendCopy(GrpcCall call,
        string resourcePath, string bytesPath, int chunkSize = GrpcMessageMaxSize)
    {
        return SendCopy(call, resourcePath, bytesPath, false, chunkSize);
    }

    private static Task<bool> SendCopyZip(GrpcCall call,
        string resourcePath, string bytesPath, int chunkSize = GrpcMessageMaxSize)
    {
        return SendCopy(call, resourcePath, bytesPath, true, chunkSize);
    }
}

internal class MessageIdProvider
{
    private int _messageId;

    public int Next() => _messageId++;
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
