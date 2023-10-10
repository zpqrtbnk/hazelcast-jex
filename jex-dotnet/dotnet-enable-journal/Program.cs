namespace Hazelcast.Jex;

using Hazelcast;
using Hazelcast.Jet; // though it should NOT be there
using System.Security.Authentication;
using System.Text.Json;

public class Program
{
    public static async Task Main(string[] args)
    {
        var optionsBuilder = new HazelcastOptionsBuilder()
            .With(args);

        if (args.Length == 1)
        {
            var jsonText = File.ReadAllText(args[0]);
            var secrets = JsonSerializer.Deserialize<JsonElement>(jsonText);
            var clusterSecrets = secrets.GetProperty("cluster");
            var sslSecrets = secrets.GetProperty("ssl");
            optionsBuilder = optionsBuilder
            .With(config =>
                {
                    config.Networking.ConnectionRetry.ClusterConnectionTimeoutMilliseconds = 4000;
                    config.ClusterName = clusterSecrets.GetProperty("name").GetString();
                    config.Networking.Cloud.DiscoveryToken = clusterSecrets.GetProperty("discovery-token").GetString();
                    config.Networking.Cloud.Url = new Uri(clusterSecrets.GetProperty("api-base").GetString());
                    config.Metrics.Enabled = true;
                    config.Networking.Ssl.Enabled = true;
                    config.Networking.Ssl.ValidateCertificateChain = false;
                    config.Networking.Ssl.Protocol = SslProtocols.Tls12;
                    config.Networking.Ssl.CertificatePath = "/home/sgay/.hazelcast/configs/usercode.0/client.pfx";
                    config.Networking.Ssl.CertificatePassword = sslSecrets.GetProperty("key-password").GetString();
                });
       }

       var options = optionsBuilder
            .Build();
        await using var client = await HazelcastClientFactory.StartNewClientAsync(options);
        await client.EnableMapJournal("streamed-map");
    }
}

