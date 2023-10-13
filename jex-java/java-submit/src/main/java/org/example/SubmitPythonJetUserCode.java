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
import java.nio.file.Path;
import java.nio.charset.Charset;
import java.util.Map;
import java.util.HashMap;

import org.json.JSONObject;

public class SubmitPythonJetUserCode {

    // usercode stage parameters
    final static int parallelProcessors = 2; // processors per member
    final static int parallelOperations = 1; // operations per processor
    final static boolean preserveOrder = true;

    static boolean attachCode;

    public static void main(String[] args) throws Exception {

        if (args.length < 1 || args.length > 2) {
            System.out.println("usage: submit <config> [<usercode-path>]");
            return;
        }

        Path secretsPath = Paths.get(args[0]);
        if (!secretsPath.isAbsolute()) {
            System.out.println("err: secrets path is not absolute.");
            return;
        }
        if (!Files.exists(secretsPath) || !Files.isDirectory(secretsPath)) {
            System.out.println("err: secrets directory not found at '" + secretsPath + "'.");
            return;
        }

        Path configPath = Paths.get(secretsPath.toString(), "config.json");
        if (!Files.exists(configPath) || Files.isDirectory(configPath)) {
            System.out.println("err: config file '" + configPath + "' not found.");
            return;
        }
        Path configYaml = Paths.get(secretsPath.toString(), "config.yaml");
        if (!Files.exists(configYaml) || Files.isDirectory(configYaml)) {
            System.out.println("err: config file '" + configYaml + "' not found.");
            return;
        }

        Path usercodePath = null;
        if (args.length == 2) {
            attachCode = true;
            usercodePath = Paths.get(args[1]);
            if (!usercodePath.isAbsolute()) {
                System.out.println("err: usercode path is not absolute.");
                return;
            }
            if (!Files.exists(usercodePath) || !Files.isDirectory(usercodePath)) {
                System.out.println("err: usercode directory not found at '" + usercodePath + "'.");
                return;
            }
        }

        // read config
        String json = new String(Files.readAllBytes(configPath), Charset.forName("utf-8"));
        JSONObject secrets = new JSONObject(json);
        JSONObject clusterSecrets = (JSONObject) secrets.get("cluster");
        String clusterName = (String) clusterSecrets.get("name");
        String clusterAddress = clusterSecrets.has("address")
            ? (String) clusterSecrets.get("address")
            : "";
        boolean isCloud = false;
        String apiBase = null, token = null;
        if (clusterSecrets.has("discovery-token")) {
            isCloud = true;
            token = (String) clusterSecrets.get("discovery-token");
            apiBase = (String) clusterSecrets.get("api-base");
        }
        boolean useSsl = false;
        String password = null, caPath = null, certPath = null, keyPath = null;
        if (secrets.has("ssl")) {
            useSsl = true;
            JSONObject sslSecrets = (JSONObject) secrets.get("ssl");
            password = (String) sslSecrets.get("key-password");
            caPath = (String) sslSecrets.get("ca-path");
            certPath = (String) sslSecrets.get("cert-path");
            keyPath = (String) sslSecrets.get("key-path");
        }

        // create job config
        JobConfig jobConfig = new JobConfig();
        jobConfig.addClass(SubmitPythonJetUserCode.class);
        jobConfig.attachDirectory(secretsPath.toString(), "secrets");
        if (attachCode) jobConfig.attachDirectory(usercodePath.toString(), "usercode");

        // create and define the pipeline
        Pipeline pipeline = Pipeline.create();
        StreamStage<?> stage = pipeline
                .readFrom(Sources.mapJournal("streamed-map", JournalInitialPosition.START_FROM_CURRENT))
                .withIngestionTimestamps();

        StreamStage<Map.Entry<Object,Object>> stage2 
            = SubmitPythonJetUserCode.<Map.Entry<Object,Object>>applyMapUsingUserCodeContainer(stage, jobConfig);
        stage2.writeTo(Sinks.map("result-map"));

        // prepare client config
	    ClientConfig clientConfig = new ClientConfig();
	    clientConfig.setClusterName(clusterName);
        if (useSsl) {
            Properties props = new Properties();
            props.setProperty("javax.net.ssl.keyStore", secretsPath + "/client.keystore");
            props.setProperty("javax.net.ssl.keyStorePassword", password);
            props.setProperty("javax.net.ssl.trustStore", secretsPath + "/client.truststore");
            props.setProperty("javax.net.ssl.trustStorePassword", password);
    	    clientConfig.getNetworkConfig().setSSLConfig(new SSLConfig().setEnabled(true).setProperties(props));
        }
        if (isCloud) {
    	    clientConfig.getNetworkConfig().getCloudConfig().setDiscoveryToken(token).setEnabled(true);
	        clientConfig.setProperty("hazelcast.client.cloud.url", apiBase);
        }
        else {
            clientConfig.getNetworkConfig().addAddress(clusterAddress);
        }

        // get the client, and submit
        HazelcastInstance hz = HazelcastClient.newHazelcastClient(clientConfig);
        hz.getJet().newJob(pipeline, jobConfig);
    }

    private static <T> StreamStage<T> applyMapUsingUserCodeContainer(StreamStage<?> stage, JobConfig jobConfig) {

        // must use Quay for multi-arch
        final String imageName = attachCode
            ? "quay.io/hz_stephane/python-usercode-base:latest"
            : "quay.io/hz_stephane/python-usercode:latest";

        UserCodeContainerConfig config = new UserCodeContainerConfig();
        config.setImageName(imageName);
        config.setPreserveOrder(preserveOrder);
        config.setMaxConcurrentOps(parallelOperations);
        config.setName("PythonJetUserCode");

        config.addResource("secrets");
        if (attachCode) config.addResource("usercode");

        return stage
            .apply(UserCodeTransforms.<T>mapUsingUserCode(config))
            .setLocalParallelism(parallelProcessors);
    }

    private static <T> StreamStage<T> applyMapUsingUserCodePassthru(StreamStage<?> stage, JobConfig jobConfig) {

        // beware! address and port of passthru runtime are hardcoded here
        UserCodePassthruConfig config = new UserCodePassthruConfig();
        config.setRuntimeAddress("127.0.0.1");
        config.setRuntimePort(5252);

        config.addResource("secrets");
        if (attachCode) config.addResource("usercode");

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
