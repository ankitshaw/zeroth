import os

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
