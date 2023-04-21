
# initialize
export DEMO=/c/Users/sgay/Code/hazelcast-jet-dotnet
export CLUSTERNAME=dev
export CLUSTERADDR=192.168.1.49:5701
export CLI=$DEMO/hazelcast/distribution/target/hazelcast-5.3.0-SNAPSHOT/bin/hz-cli
export MVN=../../mvn/apache-maven-3.8.1/bin/mvn

# build the Hazelcast .NET client
# includes the new Hazelcast.Net.Jet NuGet package
(cd hazelcast-csharp-client && \
    pwsh ./hz.ps1 build,pack-nuget)

# build the Hazelcast project
# includes the new dotnet extension
(cd hazelcast && \
    $MVN install -DskipTests -Dcheckstyle.skip=true && \
    cd distribution/target && \
    rm -rf hazelcast-5.3.0-SNAPSHOT && 
    unzip hazelcast-5.3.0-SNAPSHOT.zip)

# build the dotnet service that runs the transform
(cd dotnet-service && 
    dotnet build &&
    dotnet publish -c Release -r win-x64 -o target/win-x64 --no-self-contained &&
    dotnet publish -c Release -r linux-x64 -o target/linux-x64 --no-self-contained &&
    dotnet publish -c Release -r win-x64 -o target-sc/win-x64 --self-contained &&
    dotnet publish -c Release -r linux-x64 -o target-sc/linux-x64 --self-contained)

# build the Java pipeline that submits the job
(cd java-pipeline && \
    $MVN package)

# (ensure a standard Hazelcast 5.3 server is running)
# eg: hz run-server -server-version 5.3.0-SNAPSHOT -server-config java-pipeline/dotjet.xml

#temp
exit

# submit the job
$CLI -t$CLUSTERNAME@$CLUSTERADDR submit \
    $DEMO/java-pipeline/target/dotnet-jet-1.0-SNAPSHOT.jar \
    -d $DEMO/dotnet-service/target-sc \
    -x service

# verify that the job runs
# eg
# ID                  STATUS             SUBMISSION TIME         NAME
# 09bb-e6b6-a100-0001 RUNNING            2023-04-20T14:24:38.400 dotjet
$CLI -t$CLUSTERNAME@$CLUSTERADDR list-jobs

# can cancel with
#$CLI -t$CLUSTERNAME@$CLUSTERADDR cancel $( $CLI -t$CLUSTERNAME@$CLUSTERADDR list-jobs|grep dotjet|cut -f1 -d\  )

# run the example
(cd dotnet-example && 
    dotnet build &&
    dotnet run -- --hazelcast.clusterName=$CLUSTERNAME --hazelcast.networking.addresses.0=$CLUSTERADDR)

# example should run OK
# also verify the server log