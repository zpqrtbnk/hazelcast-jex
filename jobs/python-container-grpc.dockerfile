
# build with: 
# docker build -t zpqrtbnk/jet-python-grpc:latest -f jobs/python-grpc-container.dockerfile jex-python/python-grpc/publish/any

FROM python:3.11

WORKDIR /var/usercode

COPY *.py ./
COPY requirements.txt requirements.txt

ENV LANG=en_US.UTF-8
ENV TZ=:/etc/localtime
ENV PATH=/var/lang/bin:/usr/local/bin:/usr/bin/:/bin:/opt/bin
ENV LD_LIBRARY_PATH=/var/lang/lib:/lib64:/usr/lib64:/var/runtime:/var/runtime/lib:/var/usercode:/var/usercode/lib:/opt/lib

# we *could* install grpc and protobuf here and not do it in the process?
RUN python3 -m pip install --upgrade pip
RUN python3 -m pip install --upgrade protobuf==4.24.0 grpcio==1.57.0
RUN python3 -m pip install -r requirements.txt

# this is the normal process commandline:
# usercode-runtime.py --grpc-port 5252 --venv-path=$VENV_PATH --venv-name=python-venv
# for docker, we don't want the wrapper to create the venv, so we'll skip it and directly launch the process
ENTRYPOINT [ "python3", "usercode-runtime.py", "--direct", "--grpc-port", "5252" ]

# alt (on a prepared instance? how does that work?)
# CMD [ "8091","transform","transform_list" ]