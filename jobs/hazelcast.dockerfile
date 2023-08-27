ARG HZVERSION=0.0.0

FROM hazelcast/hazelcast:$HZVERSION

# copy from distribution to /opt/hazelcast/lib
COPY *.jar /opt/hazelcast/lib/

# remove files from base image (must be user root)
USER root

# args need to be requested at every stage, lol
ARG HZVERSION
RUN rm /opt/hazelcast/lib/hazelcast*-$HZVERSION.jar

# restore user
USER hazelcast
