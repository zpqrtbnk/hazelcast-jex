package org.example;

import com.hazelcast.client.HazelcastClient;
import com.hazelcast.client.config.ClientConfig;
import com.hazelcast.config.SSLConfig;
import com.hazelcast.core.HazelcastInstance;
import com.hazelcast.jet.config.JobConfig;
import com.hazelcast.jet.pipeline.*;
import com.hazelcast.logging.ILogger;
import com.hazelcast.logging.Logger;
import com.hazelcast.usercode.UserCodeConfig;
import com.hazelcast.usercode.UserCodeContainerConfig;
import com.hazelcast.usercode.UserCodePassthruConfig;
import com.hazelcast.usercode.UserCodeProcessConfig;
import com.hazelcast.usercode.jet.UserCodeTransforms;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;
import java.util.Map;
import java.util.Properties;

public class Submitter {

    private final SubmitCommand submitArgs;

    // usercode stage parameters, we keep them constant for now
    final static int parallelProcessors = 2; // processors per member
    final static int parallelOperations = 1; // operations per processor
    final static boolean preserveOrder = true;

    public Submitter(SubmitCommand submitArgs) {
        this.submitArgs = submitArgs;
    }

    public int submit() throws Exception {

        ILogger logger = Logger.getLogger(Submitter.class);

        Path secretsPath = Paths.get(submitArgs.secretsPath);
        if (!secretsPath.isAbsolute()) {
            System.out.println("err: secrets path is not absolute.");
            return 1;
        }
        if (!Files.exists(secretsPath) || !Files.isDirectory(secretsPath)) {
            System.out.println("err: secrets directory not found at '" + secretsPath + "'.");
            return 1;
        }

        Path configPath = Paths.get(secretsPath.toString(), "config.json");
        if (!Files.exists(configPath) || Files.isDirectory(configPath)) {
            System.out.println("err: config file '" + configPath + "' not found.");
            return 1;
        }
        Path configYaml = Paths.get(secretsPath.toString(), "config.yaml");
        if (!Files.exists(configYaml) || Files.isDirectory(configYaml)) {
            System.out.println("err: config file '" + configYaml + "' not found.");
            return 1;
        }

        Path usercodePath = null;
        if (submitArgs.submitCode) {
            usercodePath = Paths.get(submitArgs.codePath);
            if (!usercodePath.isAbsolute()) {
                System.out.println("err: usercode path is not absolute.");
                return 1;
            }
            if (!Files.exists(usercodePath) || !Files.isDirectory(usercodePath)) {
                System.out.println("err: usercode directory not found at '" + usercodePath + "'.");
                return 1;
            }
        }

        // read config
        String json = new String(Files.readAllBytes(configPath), StandardCharsets.UTF_8);
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
        jobConfig.addClass(SubmitCommand.class);
        if (submitArgs.submitSecrets) jobConfig.attachDirectory(secretsPath.toString(), "secrets");
        if (submitArgs.submitCode) jobConfig.attachDirectory(usercodePath.toString(), "usercode");

        // create and define the pipeline
        Pipeline pipeline = Pipeline.create();
        StreamStage<?> stage = pipeline
                .readFrom(Sources.mapJournal("streamed-map", JournalInitialPosition.START_FROM_CURRENT))
                .withIngestionTimestamps();

        StreamStage<Map.Entry<Object,Object>> stage2;
        if (submitArgs.runtime.isContainer) {
            stage2 = applyMapUsingUserCodeContainer(stage, jobConfig, submitArgs.runtime.runtimeImage);
        } else if (submitArgs.runtime.isPassthru) {
            stage2 = applyMapUsingUserCodePassthru(stage, jobConfig, submitArgs.runtime.runtimeAddress);
        } else if (submitArgs.runtime.isProcess) {
            stage2 = applyMapUsingUserCodeProcess(stage, jobConfig, submitArgs);
        } else {
            throw new Exception("meh");
        }

        stage2.writeTo(Sinks.map("result-map"));

        // prepare client config
        ClientConfig clientConfig = new ClientConfig();
        clientConfig.setClusterName(clusterName);
        clientConfig.getNetworkConfig().setSmartRouting(false); // fast
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

        String msg = "Submit ";
        if (submitArgs.runtime.isContainer) msg += "container runtime (image=" + submitArgs.runtime.runtimeImage + ")";
        if (submitArgs.runtime.isPassthru) msg += "passhtru runtime (address=" + submitArgs.runtime.runtimeAddress + ")";
        if (submitArgs.submitSecrets) msg += " w/secrets";
        if (submitArgs.submitCode) msg += " w/code";

        // get the client, and submit
        HazelcastInstance hz = HazelcastClient.newHazelcastClient(clientConfig);
        logger.info(msg);
        hz.getJet().newJob(pipeline, jobConfig);
        return 0;
    }

    private void addResources(UserCodeConfig config) {
        if (submitArgs.submitSecrets) config.addResource("secrets");
        if (submitArgs.submitCode) config.addResource("usercode");
    }

    private <T> StreamStage<T> applyMapUsingUserCodeContainer(StreamStage<?> stage, JobConfig jobConfig, String imageName) {

        UserCodeContainerConfig config = new UserCodeContainerConfig()
            .setImageName(imageName);

        config.setName("PythonJetUserCode");
        addResources(config);

        return stage
                .apply(UserCodeTransforms.<T>mapUsingUserCode(config, parallelOperations, preserveOrder))
                .setLocalParallelism(parallelProcessors);
    }

    private <T> StreamStage<T> applyMapUsingUserCodePassthru(StreamStage<?> stage, JobConfig jobConfig, String address) {

        String[] addressParts = address.split(":");
        UserCodePassthruConfig config = new UserCodePassthruConfig()
                .setRuntimeAddress(addressParts[0])
                .setRuntimePort(Integer.parseInt(addressParts[1]));

        config.setName("PythonJetUserCode");
        addResources(config);

        return stage
                .apply(UserCodeTransforms.<T>mapUsingUserCode(config, parallelOperations, preserveOrder))
                .setLocalParallelism(parallelProcessors);
    }

     private <T> StreamStage<T> applyMapUsingUserCodeProcess(StreamStage<?> stage, JobConfig jobConfig, SubmitCommand command) {

         UserCodeProcessConfig config = new UserCodeProcessConfig()
                 .setProcessName(command.runtime.processName)
                 .setProcessPath(command.processPath)
                 .setProcessPort(command.processPort)
                 .addProcessArgs(List.of(command.processArgs))
                 .setWorkDirectory(command.workDirectory);

         config.setName("PythonJetUserCode");
         addResources(config);

         return stage
                 .apply(UserCodeTransforms.<T>mapUsingUserCode(config, parallelOperations, preserveOrder))
                 .setLocalParallelism(parallelProcessors);
     }
}
