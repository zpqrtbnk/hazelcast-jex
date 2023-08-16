# Generated by the gRPC Python protocol compiler plugin. DO NOT EDIT!
"""Client and server classes corresponding to protobuf-defined services."""
import grpc

from generated import usercode_pb2 as usercode__pb2

class TransportStub(object):
    """Missing associated documentation comment in .proto file."""

    def __init__(self, channel):
        """Constructor.

        Args:
            channel: A grpc.Channel.
        """
        self.invoke = channel.stream_stream(
                '/usercode.Transport/invoke',
                request_serializer=usercode__pb2.UserCodeGrpcMessage.SerializeToString,
                response_deserializer=usercode__pb2.UserCodeGrpcMessage.FromString,
                )


class TransportServicer(object):
    """Missing associated documentation comment in .proto file."""

    def invoke(self, request_iterator, context):
        """Missing associated documentation comment in .proto file."""
        context.set_code(grpc.StatusCode.UNIMPLEMENTED)
        context.set_details('Method not implemented!')
        raise NotImplementedError('Method not implemented!')


def add_TransportServicer_to_server(servicer, server):
    rpc_method_handlers = {
            'invoke': grpc.stream_stream_rpc_method_handler(
                    servicer.invoke,
                    request_deserializer=usercode__pb2.UserCodeGrpcMessage.FromString,
                    response_serializer=usercode__pb2.UserCodeGrpcMessage.SerializeToString,
            ),
    }
    generic_handler = grpc.method_handlers_generic_handler(
            'usercode.Transport', rpc_method_handlers)
    server.add_generic_rpc_handlers((generic_handler,))


 # This class is part of an EXPERIMENTAL API.
class Transport(object):
    """Missing associated documentation comment in .proto file."""

    @staticmethod
    def invoke(request_iterator,
            target,
            options=(),
            channel_credentials=None,
            call_credentials=None,
            insecure=False,
            compression=None,
            wait_for_ready=None,
            timeout=None,
            metadata=None):
        return grpc.experimental.stream_stream(request_iterator, target, '/usercode.Transport/invoke',
            usercode__pb2.UserCodeGrpcMessage.SerializeToString,
            usercode__pb2.UserCodeGrpcMessage.FromString,
            options, channel_credentials,
            insecure, call_credentials, compression, wait_for_ready, timeout, metadata)
