<p align="center">
  <img src="docs/banner.png" alt="Zeroth" width="600" />
</p>

<p align="center">
  <strong>The open-source data lakehouse you can run anywhere.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License" />
  <img src="https://img.shields.io/badge/docker-compose-2496ED?logo=docker&logoColor=white" alt="Docker" />
  <img src="https://img.shields.io/badge/Iceberg-Lakehouse-00C7B7" alt="Iceberg" />
  <img src="https://img.shields.io/badge/status-alpha-orange" alt="Status" />
</p>

---

## 💡 What is Zeroth?

**Zeroth** is a **fully open-source data lakehouse** — a complete platform for storing, querying, streaming, and visualizing data at any scale. It combines best-in-class open-source technologies into a single, cohesive stack that runs on your laptop with Docker or scales to production on Kubernetes.

Think of it as your **own cloud data warehouse** — with full SQL analytics, ACID transactions, time travel, role-based access control, real-time ingestion, and a BI dashboard — all without paying a single vendor license fee.

### Why Zeroth?

- 🔓 **No vendor lock-in** — portable Apache Iceberg tables, swap any component anytime
- 💰 **Zero license cost** — pay only for infrastructure (Docker on your laptop = $0)
- 🏗️ **Production architecture** — separation of storage, compute, and catalog layers
- 🔌 **Pluggable engines** — use Trino, Spark, Flink, or DuckDB on the same tables
- 🛡️ **Built-in governance** — Apache Polaris for catalog-level RBAC and access control
- 📊 **Batteries included** — streaming ingestion, SQL IDE, dashboards, all pre-configured

## 🧱 Technology Stack

| Layer | Technology | Role |
|-------|-----------|------|
| **Object Storage** | MinIO | S3-compatible storage for all data |
| **Table Format** | Apache Iceberg + Parquet | ACID tables with time travel & schema evolution |
| **Catalog & RBAC** | Apache Polaris | Metadata management and access control |
| **Query Engine** | Trino | Distributed SQL engine (MPP) |
| **Event Streaming** | Redpanda | Kafka-compatible streaming (C++, no JVM) |
| **Data Ingestion** | Apache NiFi | Visual drag-and-drop data pipelines |
| **BI & SQL IDE** | Apache Superset | Dashboards, charts, and SQL Lab |

## � How It Works

### 🪣 MinIO — Object Storage

MinIO is a high-performance, **S3-compatible object storage** server. It stores all your data — Parquet files, Iceberg metadata, raw uploads — in standard S3 buckets. Any tool that speaks the S3 API (Trino, Spark, PyArrow) can read and write to it directly. In Zeroth, MinIO replaces cloud storage (AWS S3, GCS) with a self-hosted alternative you fully control.

### 🧊 Apache Iceberg + Parquet — Table Format

Iceberg is the **table format** that turns object storage into a proper data warehouse. It adds ACID transactions, time travel (query any previous version), schema evolution (add/rename columns without rewriting data), and partition evolution. Data is stored as **Parquet files** — a columnar format that enables predicate pushdown and compression ratios of 3-10x. Together, they make MinIO feel like a fully transactional database.

### 🔐 Apache Polaris — Catalog & Governance

Polaris is the **Iceberg REST Catalog** — it keeps track of where every table lives, what its schema is, and who can access it. Originally built inside a major cloud data warehouse and then open-sourced to Apache, it provides **role-based access control (RBAC)** with catalog roles, principal roles, and fine-grained privilege grants. Trino, NiFi, and PyIceberg all connect to Polaris to discover and access tables.

### ⚡ Trino — Query Engine

Trino is a **distributed SQL engine** (MPP — massively parallel processing) that executes queries across your Iceberg tables at speed. It handles the `SELECT`, `INSERT`, `CREATE TABLE`, schema operations, and federated queries across multiple data sources. In Zeroth, it connects to Polaris for catalog lookups and reads/writes Parquet files directly on MinIO.

### 🔴 Redpanda — Event Streaming

Redpanda is a **Kafka-compatible** streaming platform written in C++ (no JVM). It uses ~256 MB RAM compared to Kafka's 1-2 GB, starts in seconds, and supports 100% of the Kafka wire protocol. All Kafka clients — NiFi's ConsumeKafka, Python's `kafka-python`, any Kafka producer — work with Redpanda without any code changes.

### 🌊 Apache NiFi — Data Ingestion

NiFi is a **visual, drag-and-drop data flow engine**. It consumes events from Redpanda, transforms them (JSON → structured records), and writes them to Iceberg tables via Trino's JDBC driver. It has 300+ built-in processors for connecting to databases, APIs, cloud services, and file systems — all configurable through a web UI with no code required.

### 📊 Apache Superset — BI & SQL IDE

Superset is a **full-featured BI platform** with SQL Lab (SQL editor with auto-complete and query history), 50+ chart types, interactive dashboards, and role-based access. It connects to Trino via SQLAlchemy and can query any Iceberg table in your catalog.

### 🐘 PostgreSQL — Metadata Database

PostgreSQL serves as the **metadata backend** for both Polaris and Superset. Polaris stores catalog definitions, roles, privileges, and table metadata in one instance. Superset stores dashboards, saved queries, user accounts, and chart configs in a second instance. Both run on lightweight `postgres:16-alpine` images.

### 🟥 Redis — Cache & Message Broker

Redis acts as both a **cache layer** and a **message broker** in Zeroth. Superset uses it to cache query results (so repeated dashboard loads don't hit Trino), and Celery uses it as a broker to distribute async tasks like long-running queries and scheduled report generation.

### ⚙️ Celery — Async Task Worker

Celery is the **distributed task queue** that runs Superset's background jobs. When you execute a long query in SQL Lab or schedule a dashboard refresh, Superset enqueues the job to Redis, and the Celery worker picks it up and runs it asynchronously. This keeps the Superset web UI fast and responsive.

### 🌸 Flower — Task Monitor

Flower is a **real-time web monitor** for Celery workers. It shows active tasks, task history, worker status, success/failure rates, and resource usage. Access it at `localhost:5555` to see what queries and jobs are running in the background.

## 📂 Project Structure

```
zeroth/
├── docker/
│   └── docker-compose.yml          # All services (14 containers, 3 profiles)
├── configs/
│   ├── trino/
│   │   └── iceberg.properties      # Trino Iceberg catalog → Polaris + MinIO
│   └── superset/
│       └── superset_config.py      # Superset config (PostgreSQL, Redis, Celery)
├── scripts/
│   └── bootstrap-polaris.sh        # Catalog, roles, and privileges setup
├── examples/
│   ├── queries.sql                 # Sample Iceberg SQL (time travel, schema evolution)
│   └── test.py                     # PyIceberg ingestion script (Python → MinIO)
├── docs/
│   └── ARCHITECTURE.md             # Deep-dive technical architecture document
└── README.md
```

## 🚀 Quick Start

### Prerequisites

- Docker & Docker Compose installed
- ~12 GB RAM available for all services

### Phase 1: Core Layer (Storage + Catalog + Query)

```bash
# 1. Start MinIO, PostgreSQL, Polaris, and Trino
docker compose -f docker/docker-compose.yml --profile core --profile bootstrap-db up -d postgres minio minio-init
sleep 10

# 2. Bootstrap the Polaris database schema
docker compose -f docker/docker-compose.yml --profile core --profile bootstrap-db run --rm polaris-db-bootstrap

# 3. Start Polaris and Trino
docker compose -f docker/docker-compose.yml --profile core up -d polaris trino
sleep 15

# 4. Bootstrap the Polaris catalog (creates warehouse, roles, privileges)
docker compose -f docker/docker-compose.yml --profile core --profile bootstrap run --rm polaris-bootstrap
```

### Verify It Works

```bash
# Restart Trino to pick up the bootstrapped catalog
docker restart trino && sleep 15

# Create a schema and table
docker exec trino trino --execute "CREATE SCHEMA IF NOT EXISTS iceberg.demo"
docker exec trino trino --execute "
  CREATE TABLE iceberg.demo.events (
    id BIGINT, event_type VARCHAR, city VARCHAR,
    created_at TIMESTAMP(6) WITH TIME ZONE
  ) WITH (format = 'PARQUET')
"

# Insert and query data
docker exec trino trino --execute "
  INSERT INTO iceberg.demo.events VALUES
    (1, 'page_view', 'New York', TIMESTAMP '2026-02-28 10:00:00 UTC'),
    (2, 'click', 'London', TIMESTAMP '2026-02-28 10:05:00 UTC')
"
docker exec trino trino --execute "SELECT * FROM iceberg.demo.events"
```

### Phase 2: Ingestion Layer (Redpanda + NiFi)

```bash
docker compose -f docker/docker-compose.yml --profile ingestion up -d
```

#### NiFi Pipeline Setup

Open NiFi at https://localhost:8443/nifi and build this flow:

```
ConsumeKafka → PutDatabaseRecord → Trino → Iceberg → MinIO
(redpanda:9092)  (JDBC INSERT, autocommit=true)
```

| Processor | Key Config |
|-----------|------------|
| **ConsumeKafka** | Bootstrap: `redpanda:9092`, Topic: `raw-events` |
| **PutDatabaseRecord** | JDBC URL: `jdbc:trino://trino:8080/iceberg/demo`, Driver: `io.trino.jdbc.TrinoDriver`, Auto-Commit: `true`, Table: `events` |

> **Note:** PutIceberg has a known NPE bug with MinIO. PutDatabaseRecord via Trino JDBC is the working alternative. The Trino JDBC driver was pre-installed at `/opt/nifi/nifi-current/lib/trino-jdbc-467.jar`.

#### Test the Pipeline

```bash
# Produce events to Redpanda
for i in $(seq 1 5); do
  echo "{\"id\":$((300+i)),\"event_type\":\"nifi_jdbc\",\"city\":\"Chicago\",\"created_at\":\"$(date -u +'%Y-%m-%d %H:%M:%S')\"}" | \
    docker exec -i redpanda rpk topic produce raw-events
done

# Verify in Trino
docker exec trino trino --execute "SELECT * FROM iceberg.demo.events ORDER BY id DESC LIMIT 10"
```

### Phase 3: UI Layer (Superset + Redis + Flower)

```bash
docker compose -f docker/docker-compose.yml --profile ui up -d
```

## 🌐 Web UIs

| Service | URL | Credentials |
|---------|-----|-------------|
| **Superset** (BI & SQL Lab) | http://localhost:8088 | `admin` / `admin` |
| **MinIO Console** | http://localhost:9001 | `admin` / `password123` |
| **Trino Web UI** | http://localhost:8080 | — |
| **NiFi** | https://localhost:8443/nifi | `admin` / `zeroth-admin-password` |
| **Redpanda Console** | http://localhost:8084 | — |
| **Redis Commander** | http://localhost:8081 | — |
| **Flower** (Celery monitor) | http://localhost:5555 | — |

### Connecting Superset to Trino

In Superset → Settings → Database Connections → `+ Database`:

```
trino://trino@trino:8080/iceberg
```

## � Python Ingestion Example

The `examples/test.py` script demonstrates writing data directly to Iceberg tables via PyIceberg:

```bash
pip install pyiceberg pyarrow requests
python examples/test.py
```

## 🏗️ Architecture

![Zeroth Architecture](docs/architecture-diagram.png)

The stack follows Snowflake's three-layer architecture:

```
┌────────────────────────────────────────────────────────┐
│  Cloud Services Layer → Apache Polaris (Catalog, RBAC) │
├────────────────────────────────────────────────────────┤
│  Compute Layer        → Trino (Distributed SQL / MPP)  │
├────────────────────────────────────────────────────────┤
│  Storage Layer        → MinIO + Iceberg + Parquet      │
└────────────────────────────────────────────────────────┘
    ↑ Redpanda + NiFi (ingestion)  ↑ Superset (BI / SQL)
```

See **[Full Architecture Document →](docs/ARCHITECTURE.md)** for component deep-dives, feature parity analysis, and production deployment topology.

## ⚙️ Key Configuration Details

### S3/MinIO Connection (Solved)

The stack uses `stsUnavailable: true` in Polaris because local MinIO does not support AWS STS token vending. Trino connects to MinIO using:

- **Path-style S3 access** (`s3.path-style-access=true`)
- **Static credentials** via `s3.aws-access-key` / `s3.aws-secret-key`
- **`MINIO_DOMAIN`** + Docker network aliases for virtual-hosted bucket routing

### Docker Compose Profiles

| Profile | Services | RAM |
|---------|----------|-----|
| `core` | MinIO, PostgreSQL, Polaris, Trino, minio-init | ~4 GB |
| `ingestion` | Redpanda, Redpanda Console, NiFi | ~2 GB |
| `ui` | Redis, Redis Commander, Superset, Superset Worker, Superset Flower, Superset DB | ~3 GB |

## 📄 License

MIT
