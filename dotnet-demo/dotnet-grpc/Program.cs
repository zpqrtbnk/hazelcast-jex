using Hazelcast.UserCode;
using Hazelcast.UserCode.Data;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Hazelcast.Jet.Demo.Service;

// NOTES:
// the plan here is to have a Hazelcast.Net.Jet.Service project that produces
// a console executable that runs "a service" and that service would be provided
// by a library built by the user (so the user would NOT build the actual
// service executable) -- but for now, it's all one unique thing in dotnet-service.
//
// for instance, the user would only implement the TransformDoThing method below
// in their own DLL (a library) and flag the method with an attribute, for instance
// [JetMethod("doThingDotnet")] - and it would be detected by the service


public class Program
{
    public static async Task Main(params string[] args)
    {
        var builder = WebApplication.CreateBuilder(args);

        // Additional configuration is required to successfully run gRPC on macOS.
        // For instructions on how to configure Kestrel and gRPC clients on macOS, visit https://go.microsoft.com/fwlink/?linkid=2099682

        // configure GRPC port (should this be an arg?)
        builder.WebHost.ConfigureKestrel(options =>
        {
            options.ListenLocalhost(5252);
        });

        // Add services to the container.
        builder.Services.AddGrpc();

        builder.Services.AddSingleton<IUserCodeServer>(_ =>
        {
            // create the server, and serve the functions
            var userCodeServer = new UserCodeServer();
            userCodeServer.ConfigureOptions += ConfigureOptions;
            userCodeServer.AddFunction<IMapEntry, IMapEntry>("doThingDotnet", DoThing);
            return userCodeServer;
        });

        var app = builder.Build();

        // Configure the HTTP request pipeline.
        app.MapGrpcService<Hazelcast.UserCode.Services.GrpcService>();
        app.MapGet("/", () => "Communication with gRPC endpoints must be made through a gRPC client. To learn how to create a client, visit: https://go.microsoft.com/fwlink/?linkid=2086909");

        await app.RunAsync();
    }

    private static HazelcastOptionsBuilder ConfigureOptions(HazelcastOptionsBuilder builder)
    {
        return builder

            // configure serialization
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

            // enable logging to console, with DEBUG level for the JetServer
            .WithConsoleLogger()
            .WithLogLevel<UserCodeServer>(LogLevel.Debug);
    }

    // NOTE: we cannot use a generic IMapEntry<,> here because of silly Java interop, we get
    // a non-generic entry, making it generic would allocate as we'd have to wrap the non-
    // generic one... unless we make the wrapper a plain struct? but still the server would
    // need to know how to go from non-generic to generic = how?

    private static IMapEntry DoThing(IMapEntry input, UserCodeContext context)
    {
        var (key, value) = input.Of<string, SomeThing>();

        context.Logger.LogDebug($"doThingDotnet: input key={key}, value={value}.");

        // compute result
        var result = new OtherThing { Value = $"__{value.Value}__" };

        context.Logger.LogDebug($"doThingDotnet: output key={key}, value={result}.");

        return IMapEntry.New(key, result);
    }
}