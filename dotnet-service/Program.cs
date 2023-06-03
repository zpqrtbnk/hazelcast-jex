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
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using Hazelcast.Jet;
using Hazelcast.Jet.Serve;

namespace Hazelcast.Jet.Service;

public class Program
{
    public static async Task Main(params string[] args)
    {
        string pipeName;
        string functionName;

        if (args.Length != 2 ||
            string.IsNullOrWhiteSpace(pipeName = args[0].Trim()) ||
            !int.TryParse(args[1], out var pipeCount) ||
            pipeCount <= 0)
        {
            Console.WriteLine("usage: exe <pipe-name> <pipe-count> <function-name>");
            Console.WriteLine("Starts the .NET server with <pipe-count> pipes named <pipe-name>-N");
            return;
        }

        // create the server, and serve the transformation
        await using var jetServer = new JetServer(pipeName, pipeCount);
        jetServer.ConfigureOptions += ConfigureOptions;
        jetServer.Transform<JetMessage<string, SomeThing>, JetMessage<string, OtherThing>>("doThingDotnet", TransformDoThing);
        await jetServer.Serve();
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
            .WithLogLevel<JetServer>(LogLevel.Debug);
    }

    private static JetMessage<string, OtherThing> TransformDoThing(JetMessage<string, SomeThing> request)
    {
        var context = request.ServerContext;

        // FIXME troubleshooting
        //if (request == null) throw new Exception("request is null"); // can't be, a struct!!
        if (request.Buffers == null) throw new Exception("request.buffers is null");
        if (request.Buffers.Length != 2) throw new Exception("request.buffers.length != 2");

        var (key, value) = request;

        context.Logger.LogDebug($"{context.PipeNumber}:doThingDotnet:{request.OperationId} input key={key}, value={value}.");

        // compute result
        var result = new OtherThing { Value = $"__{value.Value}__" };

        context.Logger.LogDebug($"{context.PipeNumber}:doThingDotnet:{request.OperationId} output key={key}, value={result}.");

        // write back
        return request.RespondWith(key, result);
    }
}

