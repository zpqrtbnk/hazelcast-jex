package org.example;

import com.hazelcast.core.Hazelcast;
import com.hazelcast.internal.journal.DeserializingEntry;
import com.hazelcast.internal.serialization.Data;
import com.hazelcast.jet.config.JobConfig;
import com.hazelcast.jet.pipeline.*;
import com.hazelcast.usercode.jet.*;

import com.hazelcast.function.FunctionEx;
import com.hazelcast.jet.pipeline.StreamStage;

import java.util.Map;
import java.util.concurrent.CompletableFuture;

public class PythonJetUserCode {

    public static void main(String[] args) {

        final int parallelProcessors = 4; // 4 processors per member
        final int parallelOperations = 4; // 4 operations per processor
        final boolean preserveOrder = true;

        final boolean baseAndResource = true; // can run different modes :)

        // the method name is in case we want the dotnet process to support several
        // methods - there is always one process per job per member, anyway, but
        // we may want to re-use one unique executable for different jobs

        UserCodeContainerConfig config = new UserCodeContainerConfig();
        if (baseAndResource) {
            config.setImage("zpqrtbnk/python-usercode-base");
        }
        else {
            config.setImage("zpqrtbnk/python-usercode");
        }
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
        if (baseAndResource) {
            String dirPath = "~/Code/hazelcast-usercode/python/example/usercode"
            String dirId = "usercode";
            jobConfig.attachDirectory(dirPath, dirId);
        }
        Hazelcast.bootstrappedInstance().getJet().newJob(pipeline, jobConfig);
    }
}
