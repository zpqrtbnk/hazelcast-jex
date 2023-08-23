import threading

# DELETE THIS FILE

from hazelcast.client import _ClientContext, ProxyManager
from hazelcast.cluster import ClusterService, _InternalClusterService
from hazelcast.compact import CompactSchemaService
from hazelcast.config import Config
from hazelcast.connection import ConnectionManager
from hazelcast.cp import CPSubsystem, ProxySessionManager
from hazelcast.errors import InvalidConfigurationError
from hazelcast.invocation import InvocationService
from hazelcast.lifecycle import LifecycleService, _InternalLifecycleService
from hazelcast.listener import ClusterViewListenerService, ListenerService
from hazelcast.near_cache import NearCacheManager
from hazelcast.partition import PartitionService, _InternalPartitionService
from hazelcast.reactor import AsyncoreReactor
from hazelcast.serialization import SerializationServiceV1
from hazelcast.sql import SqlService, _InternalSqlService
from hazelcast.statistics import Statistics
from hazelcast.transaction import TransactionManager
from hazelcast.util import AtomicInteger

from hazelcast import HazelcastClient

# FIXME we *do* want to start the client so we can handle schemas = KILL THIS FILE
# a copy of the original client __init__ which does NOT actually start the client
def init_client(self, config: Config = None, **kwargs):

    if config:
        if kwargs:
            raise InvalidConfigurationError(
                "Ambiguous client configuration is found. Either provide "
                "the config object as the only parameter, or do not "
                "pass it and use keyword arguments to configure the "
                "client."
            )
    else:
        config = Config.from_dict(kwargs)

    self._config = config
    self._context = _ClientContext()
    client_id = HazelcastClient._CLIENT_ID.get_and_increment()
    self._name = self._create_client_name(client_id)
    self._reactor = AsyncoreReactor()
    self._serialization_service = SerializationServiceV1(config)
    self._near_cache_manager = NearCacheManager(config, self._serialization_service)
    self._internal_lifecycle_service = _InternalLifecycleService(config)
    self._lifecycle_service = LifecycleService(self._internal_lifecycle_service)
    self._internal_cluster_service = _InternalClusterService(self, config)
    self._cluster_service = ClusterService(self._internal_cluster_service)
    self._invocation_service = InvocationService(self, config, self._reactor)
    self._compact_schema_service = CompactSchemaService(
        self._serialization_service.compact_stream_serializer,
        self._invocation_service,
        self._cluster_service,
        self._reactor,
        self._config,
    )
    self._address_provider = self._create_address_provider()
    self._internal_partition_service = _InternalPartitionService(self)
    self._partition_service = PartitionService(
        self._internal_partition_service,
        self._serialization_service,
        self._compact_schema_service.send_schema_and_retry,
    )
    self._connection_manager = ConnectionManager(
        self,
        config,
        self._reactor,
        self._address_provider,
        self._internal_lifecycle_service,
        self._internal_partition_service,
        self._internal_cluster_service,
        self._invocation_service,
        self._near_cache_manager,
        self._send_state_to_cluster,
    )
    self._load_balancer = self._init_load_balancer(config)
    self._listener_service = ListenerService(
        self,
        config,
        self._connection_manager,
        self._invocation_service,
        self._compact_schema_service,
    )
    self._proxy_manager = ProxyManager(self._context)
    self._cp_subsystem = CPSubsystem(self._context)
    self._proxy_session_manager = ProxySessionManager(self._context)
    self._transaction_manager = TransactionManager(self._context)
    self._lock_reference_id_generator = AtomicInteger(1)
    self._statistics = Statistics(
        self,
        config,
        self._reactor,
        self._connection_manager,
        self._invocation_service,
        self._near_cache_manager,
    )
    self._cluster_view_listener = ClusterViewListenerService(
        self,
        self._connection_manager,
        self._internal_partition_service,
        self._internal_cluster_service,
        self._invocation_service,
    )
    self._shutdown_lock = threading.RLock()
    self._invocation_service.init(
        self._internal_partition_service,
        self._connection_manager,
        self._listener_service,
        self._compact_schema_service,
    )
    self._internal_sql_service = _InternalSqlService(
        self._connection_manager,
        self._serialization_service,
        self._invocation_service,
        self._compact_schema_service.send_schema_and_retry,
    )
    self._sql_service = SqlService(self._internal_sql_service)
    self._init_context()

    # do NOT start!
    #self._start()

# actually start the client
def start_client(self):
    self._start()

# patch the HazelcastClient class
setattr(HazelcastClient, '__init__', init_client)
setattr(HazelcastClient, 'start', start_client)

# FIXME but if we want to connect the client later on...
# we'll have to be able to update SOME of its options?

def get_client(config: Config = None, **kwargs):
    client = HazelcastClient(config, **kwargs)
    return client
