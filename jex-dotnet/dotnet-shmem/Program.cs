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
using System.Threading;
using System.Threading.Tasks;
using Hazelcast.Demo;
using Hazelcast.UserCode.Data;
using Hazelcast.UserCode;
using Hazelcast.UserCode.Services;
using Microsoft.Extensions.Logging;
using YamlDotNet.Core.Tokens;

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
        string pipeUid;

        if (args.Length != 1 || string.IsNullOrWhiteSpace(pipeUid = args[0].Trim()))
        {
            Console.WriteLine("usage: exe <pipe-uid>");
            return;
        }

        // create the server, and serve the functions
        await using var userCodeServer = new UserCodeServer();
        userCodeServer.ConfigureOptions += ConfigureOptions;
        userCodeServer.AddFunction<IMapEntry, IMapEntry>("doThingDotnet", DoThing);

        await using var service = new SharedMemoryService(true, null, pipeUid); // FIXME why IAsyncDisposable?!
        await service.Serve(userCodeServer, CancellationToken.None);
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