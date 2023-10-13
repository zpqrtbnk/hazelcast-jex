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

using Microsoft.Extensions.Logging;
using System.Text.Json.Nodes;

namespace Hazelcast.Demo;

/// <summary>
/// Provides extension methods for the <see cref="HazelcastOptionsBuilder"/> class.
/// </summary>
public static class HazelcastOptionsBuilderExtensions
{
    // FIXME
    public static HazelcastOptionsBuilder WithLogLevel<T>(this HazelcastOptionsBuilder builder, LogLevel level)
    {
        return builder.With($"Logging:LogLevel:{typeof(T).FullName}", level.ToString());
    }

    /// <summary>
    /// Sets the logger factory
    /// </summary>
    /// <param name="builder">The options builder.</param>
    /// <param name="hazelcastLogLevel">The Hazelcast log level.</param>
    /// <returns>The options builder.</returns>
    public static HazelcastOptionsBuilder WithConsoleLogger(this HazelcastOptionsBuilder builder, LogLevel hazelcastLogLevel = LogLevel.Information)
    {
        return builder
            .WithDefault("Logging:LogLevel:Default", "None")
            .WithDefault("Logging:LogLevel:System", "Information")
            .WithDefault("Logging:LogLevel:Microsoft", "Information")
            .WithDefault("Logging:LogLevel:Hazelcast", hazelcastLogLevel.ToString())
            .With((configuration, options) =>
            {
                // configure logging factory and add the console provider
                options.LoggerFactory.Creator = () => LoggerFactory.Create(loggingBuilder =>
                    loggingBuilder
                        .AddConfiguration(configuration.GetSection("logging"))
                        // https://docs.microsoft.com/en-us/dotnet/core/extensions/console-log-formatter
                        .AddSimpleConsole(o =>
                        {
                            o.SingleLine = true;
                            o.TimestampFormat = "hh:mm:ss.fff ";
                        }));
            });
    }

    public static HazelcastOptionsBuilder WithSecrets(this HazelcastOptionsBuilder builder, string secretsPath)
    {
        if (!Path.IsPathRooted(secretsPath))
            throw new Exception("err: secrets path is not absolute.");
        if (!Directory.Exists(secretsPath))
            throw new Exception($"err: secrets directory '{secretsPath}' not found.");

        var configJsonPath = Path.Combine(secretsPath, "config.json");
        if (!File.Exists(configJsonPath))
            throw new Exception($"err: config file '{configJsonPath}' not found.");

        var configYamlPath = Path.Combine(secretsPath, "config.yaml");
        if (!File.Exists(configYamlPath))
            throw new Exception($"err: config file '{configYamlPath}' not found.");

        JsonObject config;
        using (var configJsonStream = File.OpenRead(configJsonPath))
        {
            config = JsonNode.Parse(configJsonStream)?.AsObject() ?? throw new Exception("meh?");
        }

        var clusterElement = config["cluster"].AsObject();
        var clusterName = clusterElement["name"].ToString();
        var clusterAddress = clusterElement.ContainsKey("address")
            ? clusterElement["address"].ToString()
            : null;
        var isCloud = false;
        string apiBase = null, token = null;
        if (clusterElement.ContainsKey("discovery-token"))
        {
            isCloud = true;
            token = clusterElement["discovery-token"].ToString();
            apiBase = clusterElement["api-base"].ToString();
        }

        var useSsl = false;
        string password = null, caPath = null, certPath = null, keyPath = null;
        if (config.ContainsKey("ssl"))
        {
            useSsl = true;
            var sslElement = config["ssl"];
            password = sslElement["password"].ToString();
            caPath = sslElement["ca-path"].ToString();
            certPath = sslElement["cert-path"].ToString();
            keyPath = sslElement["key-path"].ToString();
        }

        return builder.With(o =>
        {
            o.ClusterName = clusterName;
            o.Networking.ConnectionRetry.ClusterConnectionTimeoutMilliseconds = 4000;

            if (useSsl)
            {
                var ssl = o.Networking.Ssl;
                ssl.Enabled = true;
                ssl.CertificatePath = certPath;
                ssl.CertificatePassword = password;
            }

            if (isCloud)
            {
                var cloud = o.Networking.Cloud;
                cloud.DiscoveryToken = token;
                cloud.Url = new Uri(apiBase);
            }
            else
            {
                o.Networking.Addresses.Add(clusterAddress);
            }
        });
    }
}