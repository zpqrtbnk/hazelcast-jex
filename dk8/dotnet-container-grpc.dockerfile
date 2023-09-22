
# build with: 
# docker build -t zpqrtbnk/jet-dotnet-grpc:latest -f jobs/dotnet-grpc-container.dockerfile jex-dotnet/dotnet-grpc/publish/linux-x64

# see also:
# https://blogit.create.pt/telmorodrigues/2022/03/08/smaller-net-6-docker-images/

# for single-file
#FROM mcr.microsoft.com/dotnet/runtime:7.0

# gRPC wants ASP.NET
FROM mcr.microsoft.com/dotnet/aspnet:7.0

# for self-contained (does *not* include .NET) (add -alpine for even smaller images)
#FROM mcr.microsoft.com/dotnet/runtime-deps:7.0

WORKDIR /var/usercode

COPY * ./

ENV LANG=en_US.UTF-8
ENV TZ=:/etc/localtime
ENV PATH=/var/usercode:/var/lang/bin:/usr/local/bin:/usr/bin/:/bin:/opt/bin
ENV LD_LIBRARY_PATH=/var/lang/lib:/lib64:/usr/lib64:/var/runtime:/var/runtime/lib:/var/usercode:/var/usercode/lib:/opt/lib

ENTRYPOINT [ "dotnet-grpc", "--usercode:grpc:port=5252" ]
