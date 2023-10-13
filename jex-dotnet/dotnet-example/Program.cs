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
using Hazelcast.DistributedObjects;
using Microsoft.Extensions.Logging;
using System.Security.Authentication;
using System.Text.Json;
using System.IO;
using System.Text;
using System.Text.Json.Nodes;

namespace Hazelcast.Demo.Example;

public class Program
{
    public static async Task Main(string[] args)
    {
        if (args.Length != 1) {
            Console.WriteLine("usage: example <config>");
            return;
        }

        Console.WriteLine("Connect to cluster...");

        var options = new HazelcastOptionsBuilder()
            .With(o =>
            {
                // add serializers so that we have the polyglot type name
                var compact = o.Serialization.Compact;
                compact.AddSerializer(new SomeThingSerializer());
                compact.AddSerializer(new OtherThingSerializer());
            })
            .WithSecrets(args[0])
            .Build();

        await using var client = await HazelcastClientFactory.StartNewClientAsync(options);
        
        Console.WriteLine("Connected");

        await using var sourceMap = await client.GetMapAsync<string, SomeThing>("streamed-map");
        await using var resultMap = await client.GetMapAsync<string, OtherThing>("result-map");

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
}
