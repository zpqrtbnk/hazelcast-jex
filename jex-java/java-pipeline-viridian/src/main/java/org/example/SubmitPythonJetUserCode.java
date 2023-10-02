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

    public static void main(String[] args) throws Exception {

        final boolean baseImage = true;

        String secretsPath = args[0]; // eg 'path/to/a15q13hs'
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

        final int parallelProcessors = 4; // 4 processors per member
        final int parallelOperations = 4; // 4 operations per processor
        final boolean preserveOrder = true;

        final String imageName = baseImage ? "zpqrtbnk/python-usercode-base" : "zpqrtbnk/python-usercode";

        UserCodeContainerConfig config = new UserCodeContainerConfig();
        config.setImageName(imageName);
        config.setPreserveOrder(preserveOrder);
        //config.setMaxConcurrentOps(parallelOperations); // Emre says "we don't provide concurrency at the moment"
        config.setName("PythonJetUserCode");

        // create and define the pipeline
        Pipeline pipeline = Pipeline.create();
        pipeline
                .readFrom(Sources.mapJournal("streamed-map", JournalInitialPosition.START_FROM_CURRENT))
                .withIngestionTimestamps()

                // We *have* to be nice with Java. UserCodeTransforms will accept anything,
                // serialize it and send it to the runtime, then simply returns what it receives,
                // deserialized - it has no idea what the input and output types are. OTOH, for
                // the pipeline to build, we *need* to specify the output type.
                .apply(UserCodeTransforms.<Map.Entry<Object,Object>>mapUsingUserCodeContainer(config))

                .setLocalParallelism(parallelProcessors)

                .writeTo(Sinks.map("result-map"));

        // submit
        JobConfig jobConfig = new JobConfig();
        jobConfig.addClass(SubmitPythonJetUserCode.class);
        if (baseImage) {
            // attach the usercode directory
            String dirPath = args[1];
            String dirId = "usercode";
            jobConfig.attachDirectory(dirPath, dirId);
            // attach the secrets directory
            // BEWARE! for python we need the PEM files 
            dirPath = secretsPath;
            dirId = "secrets";
            jobConfig.attachDirectory(dirPath, dirId);
        }

        // locate TLS files
        // should they be JAR resources or, more safely, in a separate directoy?
        // ah well, they *have* to be files, Viridian examples are misleading,
        // Hazelcast SSL layer does not support loading from embedded resources
        String keyStore, trustStore;
        /*
        if (args.length > 0) {
            keyStore = args[0] + "/" + clusterName + "/client.keystore";
            trustStore = args[0] + "/" + clusterName + "/client.truststore";
        }
        else {
            ClassLoader classLoader = SubmitPythonJetUserCode.class.getClassLoader();
            keyStore = classLoader.getResource("client.keystore").toURI().toString();
            trustStore = classLoader.getResource("client.truststore").toURI().toString();

            URI uri = classLoader.getResource("client.truststore").toURI();
            // java never ceases to amaze - we need to amnually initialize the ZIP filesystem :(
            Map<String, String> env = new HashMap<>(); 
            env.put("create", "true");
            FileSystem zipfs = FileSystems.newFileSystem(uri, env);

            // now, the beauty of Java is... THIS will load, but the SSL layer still fails :(
            // maybe the SSL layer just cannot work from resources at all?
            System.out.println("trustore uri: " + uri.toString());
            System.out.println("trustore path: " + Paths.get(uri).toString());
            System.out.println("trustore fs: " + Paths.get(uri).getFileSystem().toString());
            Files.readAllBytes(Paths.get(uri)); //, Charset.forName("utf-8"));
        }
        */

        keyStore = secretsPath + "/client.keystore";
        trustStore = secretsPath + "/client.truststore";

        System.out.println("keyStore:   " + keyStore);
        System.out.println("trustStore: " + trustStore);

	// copied from Viridian Java sample
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

        //ClientConfig clientConfig = new ClientConfig();
        //clientConfig.setClusterName("dev");
        //clientConfig.getNetworkConfig().addAddress("192.168.1.200:5701");
        //clientConfig.getNetworkConfig().addAddress("127.0.0.1:5701");

        HazelcastInstance hz = HazelcastClient.newHazelcastClient(clientConfig);

        hz.getJet().newJob(pipeline, jobConfig);
    }
}
