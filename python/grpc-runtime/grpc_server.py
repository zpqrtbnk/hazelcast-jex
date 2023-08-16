import grpc
import sys
import os
import socket
import logging
import importlib
from concurrent import futures

from generated import usercode_pb2
from generated import usercode_pb2_grpc
from usercode.UserCodeMessage import UserCodeMessage

logger = logging.getLogger('Python PID %d' % os.getpid())

class TransportServicer(usercode_pb2_grpc.TransportServicer):

    def __init__(self, usercode_functions):
        self.usercode_functions = usercode_functions

    def invoke(self, request_iterator, context):
        for input_message in request_iterator:
            input = UserCodeMessage(input_message.id, input_message.functionName, input_message.payload)
            if input_message.functionName == '.EXIT':
                break # is this OK?
            function = self.usercode_functions[input_message.functionName]
            result = function(input)
            result_message = usercode_pb2.UserCodeGrpcMessage(id=result.id, functionName=result.function_name, payload=result.payload)
            yield result_message
        logger.info('gRPC call completed')

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
    server.add_insecure_port('localhost:%d' % int(port))
    print("serving (on port %s)..." % port)
    print("for now, type 'stop' in stdin, we'll change this later")
    server.start()
    #FIXME in .NET *and* here there's a diff between terminating the 'invoke' call *and* terminating the gRPC server? in case we reconnect?
    #server.wait_for_termination()
    # Wait for a stop signal in stdin
    # FIXME this is not how we want to do it
    # well send a .EXIT function or .COMPLETE or something
    # so here we need to wait on 'something'
    stdin_message = input()
    if stdin_message == 'stop':
        logger.info('Received a "stop" message from stdin. Stopping the server.')
    else:
        logger.info('Received an unexpected message from stdin: "%s"' % stdin_message)
    server.stop(0).wait()

# fixme?!
if __name__ == '__main__':
    logging.basicConfig(stream=sys.stdout, format='%(asctime)s %(levelname)s [%(name)s] %(threadName)s - %(message)s', level=logging.INFO)
    serve(port=sys.argv[1])
