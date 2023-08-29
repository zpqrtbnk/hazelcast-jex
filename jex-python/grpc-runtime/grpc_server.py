import grpc
import sys
import os
import socket
import logging
import importlib
import traceback
import threading
import signal
from hzdata import MapEntry,HzData
from concurrent import futures

from hazelcast.config import Config
from hazelcast import HazelcastClient

import usercode_pb2, usercode_pb2_grpc
from UserCodeContext import UserCodeContext

logger = logging.getLogger('Python PID %d' % os.getpid()) # fixme kill

class TransportServicer(usercode_pb2_grpc.TransportServicer):

    def __init__(self, usercode_functions):
        self.usercode_functions = usercode_functions

    def handle(self, input_message, context):

        if context is None:
            return usercode_pb2.UserCodeGrpcMessage(id=input_message.id, functionName='.ERROR', payload='Context is NULL.'.encode('utf-8'))

        function_name = input_message.functionName
        if not function_name in self.usercode_functions:
            return usercode_pb2.UserCodeGrpcMessage(id=input_message.id, functionName=".ERROR", payload=f'Undefined function {function_name}.'.encode('utf-8'))
        
        function = self.usercode_functions[function_name]
        input_object = context.to_object(input_message.payload)
        result = function(input_object, context)
        payload = context.to_byte_array(result)
        return usercode_pb2.UserCodeGrpcMessage(id=input_message.id, functionName=input_message.functionName, payload=bytes(payload))
    
    def create_context(self, connectArgs:str):
        config = Config()
        config.cluster_connect_timeout = 4 # fixme make this an option
        configure_client(config)
        config.data_serializable_factories[HzData.get_factory_id()] = HzData.get_factory()

        connectArgsItems = connectArgs.split(';')
        #config.cluster_name = connectArgs[pos+1:]
        #config.cluster_members.append(connectArgs[:pos])
        config.cluster_name = connectArgsItems[2]
        cluster_address = connectArgsItems[0] + ':' + connectArgsItems[1]
        config.cluster_members.append(cluster_address)
        logger.info(f"connect to cluster {config.cluster_name} at address {cluster_address} (from: '{connectArgs}')")

        config.smart_routing = False
        client = HazelcastClient(config)
        context = UserCodeContext(client)
        return context

    def invoke(self, request_iterator, context):
        context = None
        for input_message in request_iterator:
            print(f'message {input_message.id}: {input_message.functionName}') # FIXME this does not show in logs?
            logger.info(f'message {input_message.id}: {input_message.functionName}')

            if input_message.functionName == '.END':
                context.client.shutdown()
                yield input_message
                break

            if input_message.functionName == '.CONNECT':
                if context is None:
                    try:                        
                        connectArgs = input_message.payload.decode('ascii')
                        context = self.create_context(connectArgs)
                    except:
                        yield usercode_pb2.UserCodeGrpcMessage(id=input_message.id, functionName='.ERROR', payload=traceback.format_exc().encode('utf-8'))
                yield input_message

            else:
                if context is None:
                    yield usercode_pb2.UserCodeGrpcMessage(id=input_message.id, functionName='.ERROR', payload="not ready".encode('utf-8'))
                else:
                    try:
                        yield self.handle(input_message, context)
                    except:
                        yield usercode_pb2.UserCodeGrpcMessage(id=input_message.id, functionName='.ERROR', payload=traceback.format_exc().encode('utf-8'))

        logger.info('gRPC call completed')

def configure_client(config):
    module_name = 'usercode-functions'
    try:
        module = importlib.import_module(module_name)
    except ImportError as e:
        raise RuntimeError("Cannot import module '%s'" % module_name, e)
    function_name = 'configure_client'
    if not hasattr(module, function_name): # should not be an error, just don't configure
        raise RuntimeError("Cannot find function '%s.%s'" % (module_name, function_name))
    function = getattr(module, function_name)
    return function(config)

def load_usercode_functions():
    module_name = 'usercode-functions'
    try:
        module = importlib.import_module(module_name)
    except ImportError as e:
        raise RuntimeError("Cannot import module '%s'" % module_name, e)
    function_name = 'get_functions'
    if not hasattr(module, function_name):
        raise RuntimeError("Cannot find function '%s.%s'" % (module_name, function_name))
    function = getattr(module, function_name)
    return function()

# TODO we should pass functions here? or?
def serve(port):
    print()
    print("serve gRPC")
    functions = load_usercode_functions()
    print("with functions:")
    for i, (name, f) in enumerate(functions.items()):
        print("- %s" % name)

    grpc_options = [
        ('grpc.max_send_message_length', 100 * 1024 * 1024),
        ('grpc.max_receive_message_length', 100 * 1024 * 1024),
        ('grpc.so_reuseport', 0)
    ]
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=1), options = grpc_options)
    usercode_pb2_grpc.add_TransportServicer_to_server(
        TransportServicer(functions),
        server
    )
    #server.add_insecure_port('localhost:%d' % int(port))
    server.add_insecure_port('[::]:%d' % int(port))
    print("serve on port %s" % port)
    print("for now, type 'stop' in stdin, we'll change this later")
    server.start()
    print("serving...")
    logger.info("serving...")
    
    # FIXME waiting for stdin is bad in k8 (what's stdin?)
    done = threading.Event()
    def on_done(signum, frame):
        done.set()
    signal.signal(signal.SIGTERM, on_done)
    done.wait()
    
    #FIXME in .NET *and* here there's a diff between terminating the 'invoke' call *and* terminating the gRPC server? in case we reconnect?
    #server.wait_for_termination()
    # Wait for a stop signal in stdin
    # FIXME this is not how we want to do it
    # well send a .EXIT function or .COMPLETE or something
    # so here we need to wait on 'something'
    #stdin_message = input()
    #if stdin_message == 'stop':
    #    logger.info('Received a "stop" message from stdin. Stopping the server.')
    #else:
    #    logger.info('Received an unexpected message from stdin: "%s"' % stdin_message)
    server.stop(0).wait()

# fixme?!
#if __name__ == '__main__':
#    logging.basicConfig(stream=sys.stdout, format='%(asctime)s %(levelname)s [%(name)s] %(threadName)s - %(message)s', level=logging.INFO)
#    serve(port=sys.argv[1])
