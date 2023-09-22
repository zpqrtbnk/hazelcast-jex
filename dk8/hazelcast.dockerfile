ARG HZVERSION=0.0.0

# forking from the hazelcast image, it's going to miss python or dotnet
#
# for dotnet, see https://hub.docker.com/_/microsoft-dotnet?tab=description
# -> lists the repos, and their Dockerfile which we can use to enhance this image
#
# for python, see https://hub.docker.com/_/python
# -> same
#
FROM hazelcast/hazelcast:$HZVERSION

# sudo
USER root

# copy from distribution to /opt/hazelcast/lib
COPY *.jar /opt/hazelcast/lib/

# copy configuration file
COPY hazelcast.xml /data/hazelcast/

# args need to be requested at every stage, lol
# remove original jar files to avoid conflicts
ARG HZVERSION
RUN rm /opt/hazelcast/lib/hazelcast*-$HZVERSION.jar

# restore user
USER hazelcast
