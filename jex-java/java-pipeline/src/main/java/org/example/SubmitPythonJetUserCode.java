package org.example;

import com.hazelcast.core.Hazelcast;
import com.hazelcast.client.HazelcastClient;
import com.hazelcast.client.config.ClientConfig;
import com.hazelcast.core.HazelcastInstance;
import com.hazelcast.internal.journal.DeserializingEntry;
import com.hazelcast.internal.serialization.Data;
import com.hazelcast.jet.config.JobConfig;
import com.hazelcast.jet.pipeline.*;
import com.hazelcast.usercode.jet.*;
import com.hazelcast.usercode.UserCodeContainerConfig;
import com.hazelcast.usercode.UserCodePassthruConfig;

import com.hazelcast.function.FunctionEx;
import com.hazelcast.jet.pipeline.StreamStage;

import java.util.Map;
import java.util.concurrent.CompletableFuture;

public class SubmitPythonJetUserCode {

    // usercode stage parameters
    final static int parallelProcessors = 2; // processors per member
    final static int parallelOperations = 1; // operations per processor
    final static boolean preserveOrder = true;

    // locally, we can submit
    // - passthru: need address of runtime
    // - process: will start process, ...
    // - container: need name of image + resources to be COPYed

    static String usercodePath = null; //path[];
    static String secretsPath = null; //path[];
    static boolean attachCode;
    static boolean attachSecrets;

    public static void main(String[] args) {

        if (args.length != 2) {
            System.out.println("usage");
            return;
        }

        // FIXME ensure that the paths are full rooted paths
        usercodePath = args[0].equals("NULL") ? null : args[0];
        secretsPath = args[1].equals("NULL") ? null : args[1];
        attachCode = usercodePath != null;
        attachSecrets = secretsPath != null;

        JobConfig jobConfig = new JobConfig();
        jobConfig.addClass(SubmitPythonJetUserCode.class);

        // create and define the pipeline
        Pipeline pipeline = Pipeline.create();
        StreamStage<?> stage = pipeline
                .readFrom(Sources.mapJournal("streamed-map", JournalInitialPosition.START_FROM_CURRENT))
                .withIngestionTimestamps();

        StreamStage<Map.Entry<Object,Object>> stage2 
            = SubmitPythonJetUserCode.<Map.Entry<Object,Object>>applyMapUsingUserCodePassthru(stage, jobConfig);
        stage2.writeTo(Sinks.map("result-map"));

        ClientConfig clientConfig = new ClientConfig();
        clientConfig.setClusterName("dev");
        //clientConfig.getNetworkConfig().addAddress("192.168.1.200:5701");
        clientConfig.getNetworkConfig().addAddress("127.0.0.1:5701");
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
