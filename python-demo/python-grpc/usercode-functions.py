
import usercode.UserCodeMessage
import hazelcast

def meh():
    client = hazelcast.HazelcastClient()
    # can we start a not-connected client?!
    # how can we get its serialization service?!
    # so... each function should receive a message *and* a context
    # and theres... one client per...?
    # in .NET there's a UserCodeServer and we need the same,
    # so it's one context per entire GRPC server yada yada
    client.shutdown()

def get_functions():
    return {
        "meh": do_something
    }

# todo: sync vs async methods?
# todo: so we're getting a message and how are we going to deserialize it?
# todo: how does compact work with python?

def do_something(message):
    result = message
    return result