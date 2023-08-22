
from hazelcast.config import Config
from hzdata import MapEntry
from domain import *

def get_functions():
    return {
        "doThingPython": do_thing
    }

def configure_client(config:Config):
    config.compact_serializers.append(SomeThingSerializer())
    config.compact_serializers.append(OtherThingSerializer())
    return config

# todo: sync vs async methods?
# todo: how does compact work with python?

# we receive a map entry and return a map entry
# what's the type of input here? of output?

def do_thing(input, context):
    key = input.get_key()
    value = input.get_value() # should be SomeThing
    context.logger.info(f"do_thing {input} / {key} / {value}")
    #context.logger.whatever('do_thing') # FIXME that should not even work?!
    result = OtherThing(f'__{value.value}__')
    entry = MapEntry.create_new(key, result)
    context.logger.info(f"do_thing -> {entry} / {entry.get_key()} / {entry.get_value()}")
    return entry