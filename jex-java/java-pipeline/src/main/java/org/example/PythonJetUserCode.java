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

import com.hazelcast.function.FunctionEx;
import com.hazelcast.jet.pipeline.StreamStage;

import java.util.Map;
import java.util.concurrent.CompletableFuture;

public class PythonJetUserCode {

    public static void main(String[] args) {

        final boolean useResources = true; // flag to decide what mode to test

        final int parallelProcessors = 4; // 4 processors per member
        final int parallelOperations = 4; // 4 operations per processor
        final boolean preserveOrder = true;

        final String imageName = useResources ? "zpqrtbnk/python-usercode-base" : "zpqrtbnk/python-usercode";

        UserCodeContainerConfig config = new UserCodeContainerConfig();
        config.setImage(imageName);
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
        jobConfig.addClass(PythonJetUserCode.class);
        if (useResources) {
            String dirPath = "/home/sgay/shared/hazelcast-usercode/python/example/custom/usercode";
            String dirId = "usercode";
            jobConfig.attachDirectory(dirPath, dirId);
        }

        ClientConfig clientConfig = new ClientConfig();
        clientConfig.setClusterName("dev");
        clientConfig.getNetworkConfig().addAddress("192.168.1.200:5701");
        //clientConfig.getNetworkConfig().addAddress("127.0.0.1:5701");
        HazelcastInstance hz = HazelcastClient.newHazelcastClient(clientConfig);

        hz.getJet().newJob(pipeline, jobConfig);
    }
}
