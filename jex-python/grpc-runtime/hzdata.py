class YangDang:
    pass

from hazelcast.serialization.api import IdentifiedDataSerializable
from hazelcast.serialization.data import Data
from hazelcast.serialization.api import ObjectDataInput, ObjectDataOutput
from hazelcast.serialization.compact import SchemaNotReplicatedError, SchemaNotFoundError
from hazelcast import HazelcastClient

class MapEntry:
    def get_key(self):
        pass
    def get_value(self):
        pass
    def create_new(key, value):
        return DeserializingMapEntry(key = key, value = value)

class DeserializingMapEntry(MapEntry, IdentifiedDataSerializable):

    def __init__(self, key_data:Data = None, value_data:Data = None, key = None, value = None):
        self.key_data = key_data
        self.value_data = value_data
        self.key = key
        self.value = value

    def get_class_id(self):
        return 2

    def get_factory_id(self):
        return -33
    
    def set_client(self, client:HazelcastClient):
        self.client = client
        #self.serialization_service = client._serialization_service
        #self.schema_service = client._compact_schema_service
    
    def get_key(self):
        if self.key is None and self.key_data is not None:
            self.key = self.to_object(self.key_data)
        return self.key
    
    def get_value(self):
        if self.value is None and self.value_data is not None:
            self.value = self.to_object(self.value_data)
        return self.value
    
    def get_key_data(self):
        if self.key_data is None and self.key is not None:
            self.key_data = self.to_data(self.key)
        return self.key_data

    def get_value_data(self):
        if self.value_data is None and self.value is not None:
            self.value_data = self.to_data(self.value)
        return self.key_data

    def to_object(self, data):
        try:
            return self.client._serialization_service.to_object(data)
        except SchemaNotFoundError as error:
            schema = self.client._compact_schema_service.fetch_schema(error.schema_id).result() # fixme all this should be async of course?
            self.client._compact_schema_service.register_fetched_schema(error.schema_id, schema)
        return self.client._serialization_service.to_object(data)

    def to_data(self, obj):
        try:
            return self.client._serialization_service.to_data(obj)
        except SchemaNotReplicatedError as error:
            self.client._compact_schema_service.send_schema_and_retry(error, lambda: None).result()
        return self.client._serialization_service.to_data(obj)

    def to_byte_array(self, obj):
        data = self.to_data(obj)
        return data.buffer if data is not None else None

    def write_data(self, output:ObjectDataOutput):
        key_data = self.get_key_data()
        value_data = self.get_value_data()
        output.write_byte_array(key_data.buffer if key_data is not None else None)
        output.write_byte_array(value_data.buffer if value_data is not None else None)

    def read_data(self, input:ObjectDataInput):
        key_bytes = input.read_byte_array()
        value_bytes = input.read_byte_array()
        self.key_data = Data(key_bytes) if key_bytes is not None else None
        self.key_value = Data(value_bytes) if value_bytes is not None else None

class HzData:
    def get_factory_id():
        return -33
    def get_factory():
        return {
            2: DeserializingMapEntry
        }