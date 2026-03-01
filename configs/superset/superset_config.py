import os
from cachelib.redis import RedisCache

# Superset secret key
SECRET_KEY = os.environ.get("SUPERSET_SECRET_KEY", "zeroth-superset-secret-key-change-in-prod")

# Metadata database (Superset's own tables)
SQLALCHEMY_DATABASE_URI = os.environ.get(
    "SQLALCHEMY_DATABASE_URI",
    "postgresql+psycopg2://superset:superset123@superset-db:5432/superset"
)

# Redis cache
CACHE_CONFIG = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_DEFAULT_TIMEOUT": 300,
    "CACHE_KEY_PREFIX": "superset_",
    "CACHE_REDIS_URL": os.environ.get("REDIS_URL", "redis://redis:6379/0"),
}

# Results backend (for async queries)
RESULTS_BACKEND = None

# Trino needs this for proper SQL Lab behavior
PREVENT_UNSAFE_DB_CONNECTIONS = False

# Allow CSV upload
CSV_EXTENSIONS = {"csv", "tsv"}

# Feature flags
FEATURE_FLAGS = {
    "ENABLE_TEMPLATE_PROCESSING": True,
    "DASHBOARD_NATIVE_FILTERS": True,
    "DASHBOARD_CROSS_FILTERS": True,
}

# Web server config
WEBSERVER_THREADS = 4
WEBSERVER_TIMEOUT = 120


class CeleryConfig:
    # Point the worker to your Redis container
    broker_url = "redis://redis:6379/0"
    imports = ("superset.sql_lab", )
    result_backend = "redis://redis:6379/0"
    worker_prefetch_multiplier = 1
    task_acks_late = False

# Tell Superset to use this config
CELERY_CONFIG = CeleryConfig

# Tells the web UI where to find the data the worker just saved.
RESULTS_BACKEND = RedisCache(
    host='redis', 
    port=6379, 
    key_prefix='superset_results'
)

# Also enable the Async query feature flag if you haven't already
FEATURE_FLAGS = {
    "SQLLAB_BACKEND_PERSISTENCE": True
}