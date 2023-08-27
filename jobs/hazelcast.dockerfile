ARG HZVERSION=0.0.0

FROM hazelcast/hazelcast:$HZVERSION

# copy from distribution to /opt/hazelcast/lib
COPY *.jar /opt/hazelcast/lib/

# FIXME how can it be available in RUN command?
#ENV HZVERSION=$HZVERSION

# remove files from base image
USER root
# args need to be requested at every stage, lol
ARG HZVERSION
RUN rm /opt/hazelcast/lib/hazelcast*-$HZVERSION.jar
USER hazelcast
