from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Optional as _Optional

DESCRIPTOR: _descriptor.FileDescriptor

class UserCodeGrpcMessage(_message.Message):
    __slots__ = ["id", "functionName", "payload"]
    ID_FIELD_NUMBER: _ClassVar[int]
    FUNCTIONNAME_FIELD_NUMBER: _ClassVar[int]
    PAYLOAD_FIELD_NUMBER: _ClassVar[int]
    id: int
    functionName: str
    payload: bytes
    def __init__(self, id: _Optional[int] = ..., functionName: _Optional[str] = ..., payload: _Optional[bytes] = ...) -> None: ...
