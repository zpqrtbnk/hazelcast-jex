package org.example;

import com.hazelcast.core.Hazelcast;
import com.hazelcast.internal.journal.DeserializingEntry;
import com.hazelcast.internal.serialization.Data;
import com.hazelcast.jet.config.JobConfig;
import com.hazelcast.jet.pipeline.*;
import com.hazelcast.jet.dotnet.*;

import java.util.Map;
import java.util.concurrent.CompletableFuture;

public class DotnetJet {

    public static void main(String[] args) {

        final int parallelProcessors = 4; // 4 processors per member
        final int parallelOperations = 4; // 4 operations per processor
        final boolean preserveOrder = true;
        final String methodName = "doThingDotnet"; // the dotnet method to apply

        // the method name is in case we want the dotnet process to support several
        // methods - there is always one process per job per member, anyway, but
        // we may want to re-use one unique executable for different jobs

        DotnetServiceConfig config = DotnetSubmit.getConfig(args)
                .withParallelism(parallelProcessors, parallelOperations)
                .withPreserveOrder(preserveOrder)
                .withMethodName(methodName);

        // create and define the pipeline
        Pipeline pipeline = Pipeline.create();
        pipeline
                .readFrom(Sources.mapJournal("streamed-map", JournalInitialPosition.START_FROM_CURRENT))
                .withIngestionTimestamps()

                .apply(DotnetTransforms.mapAsync(DotnetService::mapAsync, config))
                .setLocalParallelism(config.getLocalParallelism()) // number of processors per member

                .writeTo(Sinks.map("result-map"));

        // configure and submit the job
        JobConfig jobConfig = new JobConfig()
                // until it is part of the distribution, we need to attach this jar
                .addJar("hazelcast/extensions/dotnet/target/hazelcast-jet-dotnet-5.3.0-SNAPSHOT.jar")
                // always include this class
                .addClass(DotnetJet.class);
        config.configureJob(jobConfig); // attaches the directories containing the dotnet exe, etc.
        Hazelcast.bootstrappedInstance().getJet().newJob(pipeline, jobConfig);
    }
}
