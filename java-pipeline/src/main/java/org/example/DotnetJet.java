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

                .apply(DotnetTransforms.mapAsync(DotnetJet::mapAsync, config))
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

    private static CompletableFuture<Map.Entry<Object, Object>> mapAsync(DotnetService service, Map.Entry<Object, Object> input) {

        // this method adapts the pipeline values (which are Map.Entry instances)
        // to the service-expected array of Data, back and forth

        // TODO: do better?
        //   how many different type of pipeline values would we need to support?
        //   could this be directly supported by the service?

        // prepare input
        DeserializingEntry entry = (DeserializingEntry) input;
        Data[] rawInput = new Data[2];
        rawInput[0] = DeserializingEntryExtensions.getDataKey(entry);
        rawInput[1] = DeserializingEntryExtensions.getDataValue(entry);

        return service
                .mapAsync(rawInput) // invoke dotnet
                .thenApply(x -> DeserializingEntryExtensions.createNew(entry, x[0], x[1])); // map result
    }
}
