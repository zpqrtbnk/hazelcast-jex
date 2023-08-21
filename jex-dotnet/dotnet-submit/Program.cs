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

using System.Reflection;
using System.Text.RegularExpressions;
using Hazelcast.Jet;
using Hazelcast.Jet.Submit;
using Microsoft.Extensions.Logging;

// TODO do something about the trailing dash?
// TODO document the entire .NET code (JetServer...)
// TODO pass in a "method name" to the service on each call = can support more than 1 method
// TODO can the server queue requests on each pipe?
// TODO test shared-memory in docker environment
// TODO massively complete the Java Yaml handling code
// TODO test runtime compilation of Java from the Yaml

namespace Hazelcast.Demo.SubmitJob;

public class Program
{
    public static async Task Main(string[] args)
    {
        var programOptions = new ProgramOptions(); // syntax: --submit:source=source.yml --submit:var:DOTNET_DIR=path/to/target
        var options = BuildOptions(args, programOptions);

        if (!File.Exists(programOptions.Source))
        {
            Console.WriteLine("Err: file not found.");
            return;
        }

        Console.WriteLine("Connect to cluster...");
        await using var client = await HazelcastClientFactory.StartNewClientAsync(options);
       
        Console.WriteLine("Connected");

        // obtain the jet client
        var jetClient = client.Jet();

        // test the jet client
        var debugResult = await jetClient.DebugAsync("ping");
        Console.WriteLine("Debug output:");
        Console.WriteLine(debugResult);

        // prepare the job
        Console.WriteLine("Prepare job");
        var yaml = await File.ReadAllTextAsync(programOptions.Source);
        //if (programOptions.Yaml != null)
        //    foreach (var (key, value) in programOptions.Yaml)
        //        yaml = Regex.Replace(yaml, @"(?<!\$)\$" + key, value);
        if (programOptions.Define != null)
        {
            // TODO: move to a utility class
            // TODO: compile/generate regex
            yaml = Regex.Replace(
                yaml,
                @"(.|^)\$([A-Z_]*)",
                match => 
                    match.Groups[1].Value == "\\" ? "$" + match.Groups[2].Value :
                    programOptions.Define.TryGetValue(match.Groups[2].Value, out var value) ? match.Groups[1].Value + value :
                    match.Value
            );
        }

        // TODO: remove, debugging
        Console.WriteLine(yaml);

        // create and submit the job
        var job = JetJob.FromYaml(yaml);
        Console.WriteLine("Submit job");
        await jetClient.SubmitJobAsync(job);
        Console.WriteLine("Submitted");

        Console.WriteLine($"Submitted {job.GetType()} with yaml:");
        Console.WriteLine(job.GetType().GetProperty("Yaml", BindingFlags.Public | BindingFlags.Instance).GetValue(job));
    }

    // add dotnet-res: dotnet
    // indicates the 'dotnet' in 'dotnet-linux-x64-'
    // and deal with the trailing dash

    private static HazelcastOptions BuildOptions(String[] args, ProgramOptions programOptions)
    {
        // return new HazelcastOptionsBuilder()
        //     .With(args)
        //     .With(o =>
        //     {
        //         // Your Viridian cluster name.
        //         o.ClusterName = "pr-dblpuha6";
        //         // Your discovery token and url to connect Viridian cluster.
        //         o.Networking.Cloud.DiscoveryToken = "sRpToloYGAHHbMwmJ1amqV9lRTembAjkXIuWHj66iddvW1O3Ml";
        //         o.Networking.Cloud.Url = new Uri("https://api.viridian.hazelcast.com");
        //         // Enable metrics to see on Management Center.
        //         o.Metrics.Enabled = true;
        //         // Configure SSL.
        //         o.Networking.Ssl.Enabled = true;
        //         o.Networking.Ssl.ValidateCertificateChain = false;
        //         o.Networking.Ssl.Protocol = SslProtocols.Tls12;
        //         o.Networking.Ssl.CertificatePath = "viridian-client.pfx";
        //         o.Networking.Ssl.CertificatePassword = "f804354890e";

        //         // Register Compact serializer of City class.
        //         //o.Serialization.Compact.AddSerializer(new CitySerializer());
        //     })
        //     .WithConsoleLogger()
        //     .Build();

        return new HazelcastOptionsBuilder()
            .With(args)
            .Bind("submit", programOptions)
            .With(o => {
                // must have a jet-enabled cluster with the job running
                // we'll provide these via command-line arguments
                //o.ClusterName = "dev";
                //o.Networking.Addresses.Add("127.0.0.1:5701");
                //o.Networking.Addresses.Add("192.168.1.49:5701");

                o.Networking.ConnectionRetry.ClusterConnectionTimeoutMilliseconds = 4000;

                o.LoggerFactory.Creator = () => LoggerFactory.Create(loggingBuilder =>
                        loggingBuilder
                            .AddFilter("Hazelcast.Jet", LogLevel.Debug)
                            //.AddFilter()
                            //.AddConfiguration(configuration.GetSection("logging"))
                            // https://docs.microsoft.com/en-us/dotnet/core/extensions/console-log-formatter
                            .AddSimpleConsole(o =>
                            {
                                o.SingleLine = true;
                                o.TimestampFormat = "hh:mm:ss.fff ";
                            }));
            })
            .Build();

   }
}