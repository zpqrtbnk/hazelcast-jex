package org.example;

import com.hazelcast.core.Hazelcast;
import com.hazelcast.client.HazelcastClient;
import com.hazelcast.client.config.ClientConfig;
import com.hazelcast.core.HazelcastInstance;
import com.hazelcast.internal.journal.DeserializingEntry;
import com.hazelcast.internal.serialization.Data;
import com.hazelcast.jet.config.JobConfig;
import com.hazelcast.config.SSLConfig;
import com.hazelcast.jet.pipeline.*;
import com.hazelcast.usercode.jet.*;
import com.hazelcast.usercode.UserCodeContainerConfig;
import com.hazelcast.usercode.UserCodePassthruConfig;

import com.hazelcast.function.FunctionEx;
import com.hazelcast.jet.pipeline.StreamStage;

import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.Properties;

import java.net.URI;
import java.nio.file.Files;
import java.nio.file.FileSystem;
import java.nio.file.FileSystems;
import java.nio.file.Paths;
import java.nio.charset.Charset;
import java.util.Map;
import java.util.HashMap;

import org.json.JSONObject;

public class SubmitPythonJetUserCode {

    // usercode stage parameters
    final static int parallelProcessors = 2; // processors per member
    final static int parallelOperations = 1; // operations per processor
    final static boolean preserveOrder = true;

    public static void main(String[] args) throws Exception {

        if (args.length != 2) {
            System.out.println("usage: submit <usercode-path> <secrets-path>");
            System.out.println("  both args are required, use NULL to omit value");
            return;
        }

        // FIXME ensure that the paths are full rooted paths
        usercodePath = args[0].equals("NULL") ? null : args[0];
        secretsPath = args[1].equals("NULL") ? null : args[1];
        attachCode = usercodePath != null;
        attachSecrets = secretsPath != null;

        String json = new String(Files.readAllBytes(Paths.get(secretsPath + "/config.json")), Charset.forName("utf-8"));
        JSONObject secrets = new JSONObject(json);
        JSONObject clusterSecrets = (JSONObject) secrets.get("cluster");
        String clusterName = (String) clusterSecrets.get("name");
        String token = (String) clusterSecrets.get("discovery-token");
        String apiBase = (String) clusterSecrets.get("api-base");
        JSONObject sslSecrets = (JSONObject) secrets.get("ssl");
        String password = (String) sslSecrets.get("key-password");
        String caPath = (String) sslSecrets.get("ca-path");
        String certPath = (String) sslSecrets.get("cert-path");
        String keyPath = (String) sslSecrets.get("key-path");

        System.out.println("CLUSTER: " + clusterName);
        System.out.println("API:     " + apiBase);
        System.out.println("TOKEN:   " + token);

        JobConfig jobConfig = new JobConfig();
        jobConfig.addClass(SubmitPythonJetUserCode.class);

        // create and define the pipeline
        Pipeline pipeline = Pipeline.create();
        StreamStage<?> stage = pipeline
                .readFrom(Sources.mapJournal("streamed-map", JournalInitialPosition.START_FROM_CURRENT))
                .withIngestionTimestamps();

        StreamStage<Map.Entry<Object,Object>> stage2 
            = SubmitPythonJetUserCode.<Map.Entry<Object,Object>>applyMapUsingUserCodeContainer(stage, jobConfig);
        stage2.writeTo(Sinks.map("result-map"));

        keyStore = secretsPath + "/client.keystore";
        trustStore = secretsPath + "/client.truststore";

        System.out.println("keyStore:   " + keyStore);
        System.out.println("trustStore: " + trustStore);

		Properties props = new Properties();
	    props.setProperty("javax.net.ssl.keyStore", keyStore);
	    props.setProperty("javax.net.ssl.keyStorePassword", password);
	    props.setProperty("javax.net.ssl.trustStore", trustStore);
	    props.setProperty("javax.net.ssl.trustStorePassword", password);

	    ClientConfig clientConfig = new ClientConfig();
	    clientConfig.getNetworkConfig().setSSLConfig(new SSLConfig().setEnabled(true).setProperties(props));
	    clientConfig.getNetworkConfig().getCloudConfig().setDiscoveryToken(token).setEnabled(true);
	    clientConfig.setProperty("hazelcast.client.cloud.url", apiBase);
	    clientConfig.setClusterName(clusterName);

        HazelcastInstance hz = HazelcastClient.newHazelcastClient(clientConfig);

        hz.getJet().newJob(pipeline, jobConfig);
    }

    private static <T> StreamStage<T> applyMapUsingUserCodeContainer(StreamStage<?> stage, JobConfig jobConfig) {

        final String imageName = attachCode ? "zpqrtbnk/python-usercode-base" : "zpqrtbnk/python-usercode";

        UserCodeContainerConfig config = new UserCodeContainerConfig();
        config.setImageName(imageName);
        config.setPreserveOrder(preserveOrder);
        config.setMaxConcurrentOps(parallelOperations);
        config.setName("PythonJetUserCode"); // FIXME this should be in the base config

        if (attachCode) config.addResource("usercode");
        if (attachSecrets) config.addResource("secrets");

        if (attachCode) jobConfig.attachDirectory(usercodePath, "usercode");
        if (attachSecrets) jobConfig.attachDirectory(secretsPath, "secrets");

        return stage
            .apply(UserCodeTransforms.<T>mapUsingUserCode(config))
            .setLocalParallelism(parallelProcessors);
    }

    private static <T> StreamStage<T> applyMapUsingUserCodePassthru(StreamStage<?> stage, JobConfig jobConfig) {

        UserCodePassthruConfig config = new UserCodePassthruConfig();
        config.setRuntimeAddress("127.0.0.1");
        config.setRuntimePort(5252);

        if (attachCode) config.addResource("usercode");
        if (attachSecrets) config.addResource("secrets");

        if (attachCode) jobConfig.attachDirectory(usercodePath, "usercode");
        if (attachSecrets) jobConfig.attachDirectory(secretsPath, "secrets");

        return stage
            .apply(UserCodeTransforms.<T>mapUsingUserCode(config))
            .setLocalParallelism(parallelProcessors);
    }

    // private static StreamStage<?> mapUsingUserCodeProcess(StreamStage<?> stage, JobConfig jobConfig) {

    //     UserCodeProcessConfig config = new UserCodeProcessConfig();
    //     config.set...

    //     return stage.apply(UserCodeTransforms.<Map.Entry<Object,Object>>mapUsingUserCode(config));
    // }
}
