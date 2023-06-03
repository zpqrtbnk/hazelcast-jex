using System.Reflection;

using Hazelcast;
using Hazelcast.Jet;
using Hazelcast.Jet.Submit;

using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Console;

// TODO do something about the trailing dash?
// TODO document the entire .NET code (JetServer...)
// TODO pass in a "method name" to the service on each call = can support more than 1 method
// TODO can the server queue requests on each pipe?
// TODO test shared-memory in docker environment
// TODO massively complete the Java Yaml handling code
// TODO test runtime compilation of Java from the Yaml

public class Program
{
    public static async Task Main(string[] args)
    {
        Console.WriteLine("Connect to cluster...");

        var options = BuildOptions(args);
        await using var client = await HazelcastClientFactory.StartNewClientAsync(options);
        
        Console.WriteLine("Connected");

        // obtain the jet client
        var jetClient = new JetClient(client);

        // submit the job
        Console.WriteLine("Submit job");
        var job = JetJob.FromYaml(Yaml1);
        const string dotnetDir = "c:\\Users\\sgay\\Code\\hazelcast-jet-dotnet\\dotnet-service\\target-sc";
        foreach (var directory in Directory.GetDirectories(dotnetDir))
        {
            job.AttachDirectory(id: $"dotnet-{Path.GetFileName(directory)}-", path: directory);
        }
        await jetClient.SubmitJobAsync(job);
        Console.WriteLine("Submitted");

        Console.WriteLine("Job is " + job.GetType());
        Console.WriteLine("Yaml:\n" + job.GetType().GetProperty("Yaml", BindingFlags.Public | BindingFlags.Instance).GetValue(job));
    }

    // add dotnet-res: dotnet
    // indicates the 'dotnet' in 'dotnet-linux-x64-'
    // and deal with the trailing dash

/*
  resources:
    - id: dotnet-linux-x64-   
      type: DIRECTORY
    - id: dotnet-win-x64-
      type: DIRECTORY
*/
    private const string Yaml1 = @"
job:
  name: my-job
  pipeline:
    - pipeline:
        - source: map-journal
          map-name: ""streamed-map""
          journal-initial-position: START_FROM_CURRENT
        - transform: dotnet
          parallelism:
            processors: 2
            operations: 2
          preserve-order: true
          dotnet-dir: ""$DOTNET_DIR""
          dotnet-exe: ""service""
          dotnet-method: ""doThingDotnet""
        - sink: map
          map-name: ""result-map""
";

    private static HazelcastOptions BuildOptions(String[] args)
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