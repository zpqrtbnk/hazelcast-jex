import logging

from hazelcast.serialization.compact import SchemaNotReplicatedError, SchemaNotFoundError
from hazelcast.serialization.data import Data
from hazelcast import HazelcastClient

class UserCodeContext:

    def __init__(self, client:HazelcastClient):
        self.client = client
        self.logger = self.create_logger('UserCodeContext')

    def to_object(self, bytes):
        data = Data(bytes)
        try:
            obj = self.client._serialization_service.to_object(data)
            if hasattr(obj, 'set_client'): obj.set_client(self.client)
            return obj
        except SchemaNotFoundError as error:
            schema = self.client._compact_schema_service.fetch_schema(error.schema_id).result() # fixme all this should be async of course?
            self.client._compact_schema_service.register_fetched_schema(error.schema_id, schema)
        obj = self.client._serialization_service.to_object(data)
        if hasattr(obj, 'set_client'): obj.set_client(self.client)
        return obj

    def to_byte_array(self, obj):
        if hasattr(obj, 'set_client'): obj.set_client(self.client)
        try:
            return self.client._serialization_service.to_data(obj).buffer
        except SchemaNotReplicatedError as error:
            self.client._compact_schema_service.send_schema_and_retry(error, lambda: None).result()
        return self.client._serialization_service.to_data(obj).buffer
    
    def create_logger(self, name):
        return logging.getLogger(name)