import typing

from hazelcast.serialization.api import CompactSerializer, CompactWriter, CompactReader

class SomeThing:
    def __init__(self, value: int):
        self.value = value
    def __str__(self):
        return f"SomeThing (value={self.value})"

class OtherThing:
    def __init__(self, value: str):
        self.value = value
    def __str__(self):
        return f"OtherThing (value='{self.value}')"

class SomeThingSerializer(CompactSerializer[SomeThing]):
    def read(self, reader: CompactReader) -> SomeThing:
        value = reader.read_int32("value")
        return SomeThing(value)

    def write(self, writer: CompactWriter, obj: SomeThing) -> None:
        writer.write_int32("value", obj.value)

    def get_type_name(self) -> str:
        return "some-thing"

    def get_class(self) -> typing.Type[SomeThing]:
        return SomeThing

class OtherThingSerializer(CompactSerializer[OtherThing]):
    def read(self, reader: CompactReader) -> OtherThing:
        value = reader.read_string("value")
        return OtherThing(value)

    def write(self, writer: CompactWriter, obj: OtherThing) -> None:
        writer.write_string("value", obj.value)

    def get_type_name(self) -> str:
        return "other-thing"

    def get_class(self) -> typing.Type[OtherThing]:
        return OtherThing