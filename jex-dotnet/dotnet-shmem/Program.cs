// Copyright (c) 2008-2023, Hazelcast, Inc. All Rights Reserved.
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
// http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

using System;
using System.Linq;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;
using Hazelcast.Configuration;
using Hazelcast.DependencyInjection;
using Hazelcast.UserCode;
using Hazelcast.UserCode.Data;
using Hazelcast.UserCode.Services;
using Hazelcast.UserCode.Utilities;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Hazelcast.Demo.Service;

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
        const string uidArdName = "--usercode:uid=";
        var uid = args.FirstOrDefault(x => x.StartsWith(uidArdName))?.Substring(uidArdName.Length);

        if (string.IsNullOrWhiteSpace(uid))
        {
            Console.WriteLine("usage: exe --usercode:uid=<uid>");
            return;
        }

        using var signalService = SignalService.Get();
        using var cancellation = new CancellationTokenSource();
        signalService.OnSignalCancel(cancellation);

        // create a service collection
        var services = new ServiceCollection();

        // build the IConfiguration
        var configuration = new ConfigurationBuilder()
            .AddHazelcastAndDefaults(args) // add default configuration (appsettings.json, etc) + Hazelcast-specific configuration
            .Build();

        // add logging to the container, the normal way
        services.AddLogging(builder => builder.AddConfiguration(configuration.GetSection("logging")).AddConsole());

        // can't use DI to configure Hazelcast as UserCodeServer wants to initialize it first *then* we can alter it

        // register the user code server
        // don't inject an Hazelcast client as options will be finalized after .CONNECT
        services.AddTransient<IUserCodeServer>(serviceProvider =>
        {
            // create the server, and serve the functions
            var userCodeServer = new UserCodeServer();
            userCodeServer.ConfigureOptions += optionsBuilder => ConfigureOptions(optionsBuilder, serviceProvider);
            userCodeServer.AddFunction<IMapEntry, IMapEntry>("doThingDotnet", DoThing);
            userCodeServer.AddFunction<IMapEntry, IMapEntry>("doThingPython", DoThing); // temp
            return userCodeServer;
        });

        // register the worker
        // FIXME ugly-ish, we should deal with the uid as true options
        services.AddTransient(serviceProvider => ActivatorUtilities.CreateInstance<Worker>(serviceProvider, uid));

        // create the service provider
        // will be disposed before the method exits
        // which will dispose (and shutdown) the Hazelcast client
        await using var serviceProvider = services.BuildServiceProvider();

        // gets the worker from the container, and run
        var worker = serviceProvider.GetRequiredService<Worker>();
        await worker.Run(cancellation.Token).ConfigureAwait(false);
    }

    private class Worker
    {
        private readonly IUserCodeServer _userCodeServer;
        private readonly ILogger<Worker> _logger;
        private readonly string _uid;

        public Worker(IUserCodeServer userCodeServer, ILogger<Worker> logger, string uid)
        {
            _userCodeServer = userCodeServer;
            _logger = logger;
            _uid = uid;
        }

        public async Task Run(CancellationToken cancellationToken)
        {
            // FIXME need a "nice" way to stop the service esp. in case of errors so that we close the mem file
            _logger.LogInformation("START");
            await using var service = new SharedMemoryService(true, null, _uid); // FIXME why IAsyncDisposable?!
            await service.Serve(_userCodeServer, cancellationToken);
            _logger.LogInformation("END");
        }
    }

    private static HazelcastOptionsBuilder ConfigureOptions(HazelcastOptionsBuilder builder, IServiceProvider serviceProvider)
    {
        return builder

            // configure serialization
            .With(options =>
            {
                // inject the logger factory
                options.LoggerFactory.ServiceProvider = serviceProvider;

                var compact = options.Serialization.Compact;

                // register serializers - we want this in order to use
                // well-known polyglot type-name and property names
                compact.AddSerializer(new SomeThingSerializer());
                compact.AddSerializer(new OtherThingSerializer());
            });
    }

    // NOTE: we cannot use a generic IMapEntry<,> here because of silly Java interop, we get
    // a non-generic entry, making it generic would allocate as we'd have to wrap the non-
    // generic one... unless we make the wrapper a plain struct? but still the server would
    // need to know how to go from non-generic to generic = how?

    private static ValueTask<IMapEntry> DoThing(IMapEntry input, UserCodeContext context)
    {
        var (key, value) = input.Of<string, SomeThing>();

        context.Logger.LogInformation("THIS IS A TEST YADA YADA");
        context.Logger.LogDebug($"doThingDotnet: input key={key}, value={value}.");

        // compute result
        var result = new OtherThing { Value = $"__{value.Value}__" };

        context.Logger.LogDebug($"doThingDotnet: output key={key}, value={result}.");

        return new ValueTask<IMapEntry>(IMapEntry.New(key, result));
    }
}