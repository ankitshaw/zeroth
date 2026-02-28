# Zeroth — Technical Architecture Document

> **Zero-cost Snowflake: Building Snowflake's Core Data Platform Capabilities with 100% Open-Source Technologies**
>
> Version: 1.0 | Last Updated: February 2026

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Snowflake Architecture Overview](#2-snowflake-architecture-overview)
3. [Open-Source Component Mapping](#3-open-source-component-mapping)
4. [Storage Layer — MinIO](#4-storage-layer--minio)
5. [Table Format — Apache Iceberg + Parquet](#5-table-format--apache-iceberg--parquet)
6. [Catalog & Governance — Apache Polaris](#6-catalog--governance--apache-polaris)
7. [Query Engine — Trino](#7-query-engine--trino)
8. [Feature Parity Analysis](#8-feature-parity-analysis)
9. [Deployment Architecture](#9-deployment-architecture)
10. [Performance Considerations](#10-performance-considerations)
11. [Security Architecture](#11-security-architecture)
12. [Limitations & Trade-offs](#12-limitations--trade-offs)
13. [Roadmap](#13-roadmap)

---

## 1. Executive Summary

Snowflake revolutionized cloud data warehousing with three key innovations:

1. **Separation of storage and compute** — scale each independently
2. **Multi-cluster shared data** — concurrent workloads with zero contention
3. **Near-zero administration** — automatic tuning, scaling, and maintenance

This document presents a **fully open-source architecture** that replicates these capabilities using mature, production-proven technologies. The stack centers on **four pillars**:

| Pillar | Technology | Role |
|--------|-----------|------|
| **Storage** | MinIO | S3-compatible object storage |
| **Table Format** | Apache Iceberg + Parquet | ACID tables on object storage |
| **Catalog** | Apache Polaris | Metadata, RBAC, discovery |
| **Query Engine** | Trino | Distributed SQL (MPP) |

All orchestrated on **Kubernetes** for elastic scaling.

---

## 2. Snowflake Architecture Overview

Snowflake's architecture has three distinct layers:

```
┌─────────────────────────────────────────────────────────────┐
│                    Cloud Services Layer                      │
│   (Authentication, Metadata, Query Optimization, RBAC)      │
├──────────┬──────────┬──────────┬──────────┬─────────────────┤
│    VW 1  │   VW 2   │   VW 3   │   VW 4   │   ...           │
│  (XS)    │  (S)     │  (M)     │  (L)     │                 │
│          │          │          │          │  Compute Layer    │
├──────────┴──────────┴──────────┴──────────┴─────────────────┤
│                Centralized Storage Layer                      │
│          (Micro-partitions in columnar format)               │
└─────────────────────────────────────────────────────────────┘
```

### Key Design Principles

| Principle | Description |
|-----------|-------------|
| **Shared-nothing compute** | Each virtual warehouse (VW) is an independent MPP cluster |
| **Shared storage** | All compute clusters read/write the same data |
| **Micro-partitions** | Data stored as immutable, compressed columnar files (50–500 MB) |
| **Automatic clustering** | Data is automatically organized for query performance |
| **Multi-cluster warehouses** | Auto-scale by adding clusters when concurrency spikes |

---

## 3. Open-Source Component Mapping

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Snowflake                                     │
├──────────────────┬──────────────────┬────────────────────────────────┤
│   Cloud Services │  Virtual         │   Centralized                  │
│   Layer          │  Warehouses      │   Storage                      │
├──────────────────┼──────────────────┼────────────────────────────────┤
│                  │                  │                                │
│                  │                  │          OPEN-SOURCE            │
│                  │                  │          EQUIVALENT             │
│                  │                  │                                │
├──────────────────┼──────────────────┼────────────────────────────────┤
│ Apache Polaris   │  Trino           │  MinIO                         │
│ (Catalog, RBAC)  │  (MPP SQL)       │  (S3-compatible Object Store)  │
│                  │                  │                                │
│ + Apache Ranger  │  on Kubernetes   │  + Apache Iceberg              │
│ + OPA            │  (auto-scaling)  │  + Apache Parquet              │
└──────────────────┴──────────────────┴────────────────────────────────┘
```

---

## 4. Storage Layer — MinIO

### Why MinIO?

MinIO is a **high-performance, S3-compatible object storage** system. It is the de facto standard for self-hosted object storage.

| Aspect | Details |
|--------|---------|
| **S3 Compatibility** | Full AWS S3 API compatibility — Iceberg, Trino, Spark all work natively |
| **Performance** | Designed for high-throughput workloads; benchmarks show performance comparable to cloud S3 |
| **Erasure Coding** | Data protection without RAID; configurable redundancy |
| **Encryption** | SSE-S3, SSE-KMS, and SSE-C encryption at rest |
| **Multi-site Replication** | Async replication across sites for DR |

### How It Maps to Snowflake

| Snowflake Concept | MinIO Equivalent |
|---|---|
| Internal stage | S3 bucket (e.g., `s3://warehouse/`) |
| Micro-partition files | Parquet files in bucket prefixes |
| Storage auto-scaling | MinIO cluster expansion (add nodes) |
| Cross-region replication | MinIO site replication |

### Configuration

```yaml
# MinIO deployment sizing
# Single-node dev:     1 node,  1 drive
# Production minimum:  4 nodes, 4 drives each (erasure coding)
# Large scale:         16+ nodes, NVMe drives

MINIO_ROOT_USER: admin
MINIO_ROOT_PASSWORD: <strong-password>
MINIO_VOLUMES: "/data{1...4}"        # 4 drives per node
MINIO_SERVER_URL: "https://minio.example.com"
```

### Storage Tiers (like Snowflake's automatic tiering)

MinIO supports **Information Lifecycle Management (ILM)** rules to move cold data to cheaper tiers:

```json
{
  "Rules": [
    {
      "Status": "Enabled",
      "Filter": { "Prefix": "warehouse/" },
      "Transition": {
        "Days": 90,
        "StorageClass": "GLACIER"    // Move to cold tier after 90 days
      }
    }
  ]
}
```

---

## 5. Table Format — Apache Iceberg + Parquet

### The Critical Abstraction

Apache Iceberg is the **most important component** in this architecture. It provides the **table abstraction** that makes object storage act like a data warehouse.

```
┌─────────────────────────────────────┐
│          Apache Iceberg              │
│   ┌──────────────────────────────┐  │
│   │     Metadata Layer           │  │
│   │  • Table schema              │  │
│   │  • Partition spec            │  │
│   │  • Snapshot history          │  │
│   │  • Sort order                │  │
│   └──────────┬───────────────────┘  │
│              │                       │
│   ┌──────────▼───────────────────┐  │
│   │     Manifest Lists           │  │
│   │  (pointers to manifests)     │  │
│   └──────────┬───────────────────┘  │
│              │                       │
│   ┌──────────▼───────────────────┐  │
│   │     Manifest Files           │  │
│   │  (pointers to data files     │  │
│   │   + column-level stats)      │  │
│   └──────────┬───────────────────┘  │
│              │                       │
│   ┌──────────▼───────────────────┐  │
│   │     Data Files (Parquet)     │  │
│   │  (columnar, compressed,      │  │
│   │   50-500 MB each)            │  │
│   └──────────────────────────────┘  │
└─────────────────────────────────────┘
```

### Feature Mapping to Snowflake

| Snowflake Feature | Iceberg Equivalent | Notes |
|---|---|---|
| **Micro-partitions** | Parquet data files | Same concept: immutable, columnar, ~100-500 MB |
| **Automatic clustering** | Sort orders + `optimize` | Manual trigger, but same effect |
| **Time Travel** | Snapshot-based time travel | Query any previous version via snapshot ID or timestamp |
| **Zero-copy Cloning** | Branching (via catalog) | New metadata pointer, no data copy |
| **Schema Evolution** | Native schema evolution | Add, rename, reorder, widen columns |
| **Partition Evolution** | Native partition evolution | **Better than Snowflake** — change partitioning without rewrite |
| **ACID Transactions** | Optimistic concurrency | Serializable isolation via metadata swap |
| **Data Retention** | Snapshot expiration | `expire_snapshots` procedure |

### Why Iceberg Over Delta Lake or Hudi?

| Criteria | Iceberg | Delta Lake | Hudi |
|----------|---------|------------|------|
| **Engine independence** | ⭐ Any engine | Spark-centric | Spark-centric |
| **Partition evolution** | ⭐ Yes | No | No |
| **Hidden partitioning** | ⭐ Yes | No | No |
| **REST Catalog standard** | ⭐ Yes | Unity Catalog | No |
| **Snowflake alignment** | ⭐ Snowflake uses Iceberg natively | No | No |
| **Community momentum** | ⭐ Fastest growing | Large | Moderate |

### Parquet Format Details

Apache Parquet provides the **physical columnar storage**:

- **Columnar layout** — Read only the columns you need
- **Predicate pushdown** — Skip row groups that don't match filters
- **Dictionary encoding** — Compress low-cardinality columns
- **Snappy/ZSTD compression** — Typically 3-10x compression ratios
- **Row group stats** — Min/max values for partition pruning

```
Parquet File Structure:
┌─────────────────────┐
│ Row Group 1          │
│  ├─ Column A chunk   │  ← Dictionary + RLE encoded
│  ├─ Column B chunk   │  ← Snappy compressed
│  └─ Column C chunk   │
├─────────────────────┤
│ Row Group 2          │
│  ├─ Column A chunk   │
│  ├─ Column B chunk   │
│  └─ Column C chunk   │
├─────────────────────┤
│ Footer               │
│  ├─ Schema           │
│  ├─ Row group stats  │  ← Min/max for predicate pushdown
│  └─ Column stats     │
└─────────────────────┘
```

---

## 6. Catalog & Governance — Apache Polaris

### Why Polaris?

Apache Polaris was **originally built inside Snowflake** as their internal Iceberg catalog, then open-sourced and donated to the Apache Software Foundation. It is the **reference implementation** of the Iceberg REST Catalog specification.

### Polaris Architecture

```
┌─────────────────────────────────────────────┐
│              Apache Polaris                   │
│                                               │
│  ┌─────────────────────────────────────────┐ │
│  │          REST Catalog API                │ │
│  │  (Iceberg REST Spec compliant)           │ │
│  └──────────┬──────────────────────────────┘ │
│             │                                 │
│  ┌──────────▼──────────────────────────────┐ │
│  │     Catalog Management                   │ │
│  │  • Namespaces (≈ Snowflake databases)    │ │
│  │  • Tables                                │ │
│  │  • Views                                 │ │
│  └──────────┬──────────────────────────────┘ │
│             │                                 │
│  ┌──────────▼──────────────────────────────┐ │
│  │     Access Control (RBAC)                │ │
│  │  • Catalog roles                         │ │
│  │  • Principal roles                       │ │
│  │  • Privilege grants                      │ │
│  └──────────┬──────────────────────────────┘ │
│             │                                 │
│  ┌──────────▼──────────────────────────────┐ │
│  │     Storage Profiles                     │ │
│  │  • S3, GCS, ADLS, MinIO                  │ │
│  │  • Vended credentials                    │ │
│  └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### Mapping to Snowflake Concepts

| Snowflake Concept | Polaris Equivalent |
|---|---|
| Account | Catalog (top-level container) |
| Database | Namespace |
| Schema | Nested namespace |
| Table | Iceberg table |
| Role | Catalog role + Principal role |
| GRANT privilege | Privilege grant API |
| Data sharing | Cross-catalog table access |

### RBAC Model

Polaris provides **Snowflake-style RBAC** with two role types:

```
Principal Roles (WHO)          Catalog Roles (WHAT)
┌───────────────┐              ┌──────────────────┐
│ data_engineer  │──grants──▶  │ warehouse_admin   │──privileges──▶ Tables
│ analyst        │──grants──▶  │ read_only         │──privileges──▶ Namespaces
│ ml_engineer    │──grants──▶  │ ml_read_write     │──privileges──▶ Views
└───────────────┘              └──────────────────┘
```

**Supported privileges:**
- `CATALOG_MANAGE_CONTENT` — Full DDL/DML
- `TABLE_READ_DATA` — SELECT on tables
- `TABLE_WRITE_DATA` — INSERT/UPDATE/DELETE
- `TABLE_CREATE` — Create new tables
- `NAMESPACE_CREATE` — Create namespaces
- `VIEW_CREATE` — Create views

### Polaris vs. Nessie — When to Use Each

| Use Case | Polaris | Nessie |
|----------|---------|--------|
| Standard Iceberg catalog | ⭐ Reference implementation | ✅ Supported |
| Built-in RBAC | ⭐ Native | ❌ External needed |
| Git-like branching | ❌ Not supported | ⭐ Core feature |
| CI/CD for data | ❌ Not supported | ⭐ Branch → test → merge |
| Snowflake parity | ⭐ Highest (from Snowflake) | ✅ Partial |
| Multi-engine support | ⭐ REST standard | ⭐ REST + native |

> **Recommendation:** Use **Polaris as primary catalog** for production governance. Add **Nessie** alongside it if you need data versioning / branching workflows (e.g., staging → production promotions).

---

## 7. Query Engine — Trino

### Why Trino?

Trino (formerly PrestoSQL) is an **open-source distributed SQL query engine** designed for interactive analytics. It maps directly to Snowflake's Virtual Warehouses.

### Architecture

```
┌───────────────────────────────────────────────────┐
│                  Trino Cluster                     │
│            (≈ Snowflake Virtual Warehouse)         │
│                                                    │
│  ┌─────────────────────────────────────────────┐  │
│  │              Coordinator                     │  │
│  │  • Query parsing & planning                  │  │
│  │  • Cost-based optimizer                      │  │
│  │  • Query scheduling                          │  │
│  │  • Web UI (port 8080)                        │  │
│  └──────────┬──────────────────────────────────┘  │
│             │  distributes work                    │
│  ┌──────────▼──────────────────────────────────┐  │
│  │              Workers (N nodes)               │  │
│  │  • Parallel data processing                  │  │
│  │  • In-memory pipeline execution              │  │
│  │  • Local caching (Alluxio optional)          │  │
│  └─────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────┘
```

### Mapping to Snowflake

| Snowflake Concept | Trino Equivalent |
|---|---|
| Virtual Warehouse (XS–6XL) | Trino cluster (configure worker count) |
| Multi-cluster warehouse | Multiple Trino clusters on K8s |
| Auto-suspend | K8s HPA scale-to-zero (KEDA) |
| Auto-resume | K8s KEDA trigger on query arrival |
| Query result caching | Trino result caching + Alluxio data caching |
| Resource monitor | Trino resource groups |

### Virtual Warehouse Sizing Equivalent

| Snowflake VW Size | Trino Equivalent | Workers | Memory/Worker |
|---|---|---|---|
| X-Small | trino-xs | 1 | 8 GB |
| Small | trino-sm | 2 | 16 GB |
| Medium | trino-md | 4 | 32 GB |
| Large | trino-lg | 8 | 64 GB |
| X-Large | trino-xl | 16 | 64 GB |
| 2X-Large | trino-2xl | 32 | 128 GB |

### Concurrency & Resource Groups

Trino's **Resource Groups** replicate Snowflake's concurrency controls:

```json
{
  "rootGroups": [
    {
      "name": "etl",
      "maxQueued": 100,
      "hardConcurrencyLimit": 10,
      "softMemoryLimit": "60%",
      "schedulingPolicy": "fair"
    },
    {
      "name": "analytics",
      "maxQueued": 500,
      "hardConcurrencyLimit": 50,
      "softMemoryLimit": "30%",
      "schedulingPolicy": "fair"
    },
    {
      "name": "adhoc",
      "maxQueued": 50,
      "hardConcurrencyLimit": 5,
      "softMemoryLimit": "10%"
    }
  ]
}
```

### Connectors (Federated Query — Bonus!)

Unlike Snowflake, Trino can query **multiple data sources** simultaneously:

```sql
-- Query across Iceberg, PostgreSQL, and MongoDB in one query!
SELECT
    i.user_id,
    i.total_purchases,
    p.email,
    m.preferences
FROM iceberg.analytics.purchases i
JOIN postgresql.users.profiles p ON i.user_id = p.id
JOIN mongodb.app.user_prefs m ON i.user_id = m.user_id;
```

---

## 8. Feature Parity Analysis

### Full Feature Comparison

| Snowflake Feature | Open-Source Status | Technology | Gap |
|---|:---:|---|---|
| **Separation of storage/compute** | ✅ Full | MinIO + Trino | None |
| **Columnar storage** | ✅ Full | Apache Parquet | None |
| **ACID transactions** | ✅ Full | Apache Iceberg | None |
| **Time Travel** | ✅ Full | Iceberg snapshots | None |
| **Zero-copy cloning** | ✅ Full | Iceberg branches/tags | None |
| **Schema evolution** | ✅ Full | Iceberg native | None |
| **Partition evolution** | ⭐ Better | Iceberg native | Better than Snowflake |
| **SQL engine (ANSI SQL)** | ✅ Full | Trino | Minor syntax diffs |
| **RBAC** | ✅ Full | Polaris | None |
| **Concurrency scaling** | ✅ Full | K8s + multi-cluster Trino | Requires K8s expertise |
| **Auto-suspend/resume** | ⚠️ Partial | KEDA + K8s HPA | Not as seamless |
| **Semi-structured data** | ✅ Full | Trino JSON functions | None |
| **Secure data sharing** | ⚠️ Partial | Polaris cross-catalog | Less polished |
| **Streams & Tasks** | ⚠️ Partial | Iceberg CDC + Airflow | Manual setup required |
| **Snowpipe (auto-ingest)** | ⚠️ Partial | Kafka + Flink + Iceberg | More complex |
| **Query result caching** | ⚠️ Partial | Trino + Alluxio | Not as transparent |
| **Materialized views** | ❌ Gap | Not native in Iceberg/Trino | Use dbt for models |
| **UDFs (Java/Python)** | ⚠️ Partial | Trino UDFs (Java) | No Python UDFs |
| **Search optimization** | ⚠️ Partial | Iceberg file-level stats | Less granular |
| **Governance (masking, tags)** | ⚠️ Partial | Ranger + custom | More manual |

### What's Better in the Open-Source Stack

| Feature | Advantage |
|---------|-----------|
| **Partition evolution** | Change partitioning without data rewrite |
| **Federated queries** | Query Postgres, MongoDB, Kafka, etc. alongside Iceberg |
| **Engine flexibility** | Use Spark, Flink, DuckDB, or Trino on the same tables |
| **Vendor independence** | No lock-in; portable Iceberg tables |
| **Cost** | No Snowflake credits; pay only for infrastructure |

---

## 9. Deployment Architecture

### Development (Docker Compose)

```
docker-compose.yml
├── MinIO         (storage)        → localhost:9000
├── Iceberg REST  (catalog)        → localhost:8181
└── Trino         (query engine)   → localhost:8080
```

See [`docker/docker-compose.yml`](../docker/docker-compose.yml) for the full configuration.

### Production (Kubernetes)

```
┌──────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster                        │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Namespace: data-platform                                 │   │
│  │                                                           │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │   │
│  │  │   Polaris    │  │  Trino ETL  │  │ Trino Analytics │  │   │
│  │  │  (catalog)   │  │  Cluster    │  │   Cluster       │  │   │
│  │  │  Deployment  │  │  (VW #1)    │  │   (VW #2)       │  │   │
│  │  │  replicas: 2 │  │  workers: 8 │  │  workers: 4     │  │   │
│  │  └──────┬───────┘  └──────┬──────┘  └───────┬─────────┘  │   │
│  │         │                 │                  │            │   │
│  │         └─────────────────┼──────────────────┘            │   │
│  │                           │                               │   │
│  │                    ┌──────▼──────┐                        │   │
│  │                    │    MinIO     │                        │   │
│  │                    │  StatefulSet │                        │   │
│  │                    │  nodes: 4    │                        │   │
│  │                    └─────────────┘                        │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Namespace: monitoring                                    │   │
│  │  Prometheus + Grafana                                     │   │
│  └──────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

### Auto-Scaling with KEDA

```yaml
# Scale Trino workers based on pending queries (like Snowflake auto-scale)
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: trino-worker-scaler
spec:
  scaleTargetRef:
    name: trino-worker
  minReplicaCount: 0        # Scale to zero when idle (auto-suspend!)
  maxReplicaCount: 32       # Max workers
  triggers:
    - type: prometheus
      metadata:
        serverAddress: http://prometheus:9090
        metricName: trino_queued_queries
        threshold: "5"      # Scale up when >5 queries queued
        query: |
          trino_queries_queued_total{cluster="analytics"}
```

---

## 10. Performance Considerations

### Query Performance Optimization

| Technique | How | Snowflake Equivalent |
|-----------|-----|---------------------|
| **Partition pruning** | Iceberg hidden partitioning + manifest stats | Micro-partition pruning |
| **Predicate pushdown** | Parquet row group min/max + Iceberg file stats | Automatic pruning |
| **Columnar projection** | Read only needed columns from Parquet | Columnar scan |
| **Data compaction** | `ALTER TABLE ... EXECUTE optimize` | Automatic clustering |
| **Sort ordering** | Iceberg sort orders (z-order supported) | Cluster keys |
| **Caching** | Alluxio (data) + Trino result cache | Result cache + local disk |

### Benchmarks (Approximate)

Benchmarks vary by hardware, data, and query patterns. General guidance:

| Workload | Expected Performance vs. Snowflake |
|----------|-----------------------------------|
| Simple aggregations (scan-heavy) | **80-100%** — Trino + Parquet is very efficient |
| Complex joins (shuffle-heavy) | **60-80%** — Snowflake's optimizer is highly tuned |
| High concurrency (100+ users) | **70-90%** — requires proper K8s tuning |
| Semi-structured (JSON) | **70-85%** — Snowflake's VARIANT is deeply optimized |
| Time travel queries | **95-100%** — Iceberg snapshots are very efficient |

### Caching Architecture

```
Query Flow:
                                        ┌──────────────┐
Client ──▶ Trino Coordinator ──▶ Check ─┤ Result Cache  │ ──▶ Return cached result
                                        └──────┬───────┘
                                               │ miss
                                        ┌──────▼───────┐
                                        │ Alluxio       │ ──▶ Read from local SSD
                                        │ (data cache)  │
                                        └──────┬───────┘
                                               │ miss
                                        ┌──────▼───────┐
                                        │ MinIO (S3)    │ ──▶ Read from object storage
                                        └──────────────┘
```

---

## 11. Security Architecture

### Defense in Depth

```
┌─────────────────────────────────────────────────────────┐
│  Layer 1: Network Security                               │
│  • K8s Network Policies                                  │
│  • TLS everywhere (mTLS between services)                │
├─────────────────────────────────────────────────────────┤
│  Layer 2: Authentication                                 │
│  • OAuth 2.0 / OIDC (Keycloak)                           │
│  • LDAP integration                                      │
│  • Service-to-service mTLS                               │
├─────────────────────────────────────────────────────────┤
│  Layer 3: Authorization (RBAC)                           │
│  • Polaris: Catalog-level RBAC                           │
│  • Apache Ranger: Fine-grained table/column policies     │
│  • OPA: Policy-as-code for custom rules                  │
├─────────────────────────────────────────────────────────┤
│  Layer 4: Data Protection                                │
│  • MinIO SSE (encryption at rest)                        │
│  • TLS (encryption in transit)                           │
│  • Column-level masking (via Ranger)                     │
│  • Row-level filtering (via Ranger)                      │
├─────────────────────────────────────────────────────────┤
│  Layer 5: Auditing                                       │
│  • Trino query audit log                                 │
│  • Polaris access audit log                              │
│  • MinIO access logs → centralized logging               │
└─────────────────────────────────────────────────────────┘
```

### Column-Level Security (via Ranger)

```xml
<!-- Apache Ranger Policy: Mask SSN column for analysts -->
<policy>
  <name>mask-ssn</name>
  <resources>
    <database>analytics</database>
    <table>customers</table>
    <column>ssn</column>
  </resources>
  <dataMaskPolicyItems>
    <roles>analyst</roles>
    <dataMaskType>MASK_SHOW_LAST_4</dataMaskType>
  </dataMaskPolicyItems>
</policy>
```

---

## 12. Limitations & Trade-offs

### Things Snowflake Does Better (Today)

| Area | Gap | Mitigation |
|------|-----|------------|
| **Zero-ops** | Open-source requires K8s expertise and operational overhead | Use managed K8s (EKS/GKE) + Helm charts + GitOps |
| **Query optimizer** | Snowflake's optimizer has years of tuning on customer workloads | Trino's CBO is improving; contribute upstream |
| **Auto-clustering** | Snowflake automatically re-clusters data | Schedule `optimize` jobs via Airflow/cron |
| **Materialized views** | No native MVs in Trino + Iceberg | Use dbt incremental models |
| **Snowpipe (auto-ingest)** | No single equivalent | Kafka Connect → Flink → Iceberg sink |
| **Streams & Tasks** | No native CDC streams | Iceberg incremental reads + Airflow |
| **Python UDFs** | Trino only supports Java UDFs | Use Spark for Python-heavy workloads |
| **Marketplace** | No data marketplace | Build custom using Polaris cross-catalog sharing |
| **Support & SLA** | Community support only | Starburst (commercial Trino) offers enterprise support |

### Operational Complexity

> [!WARNING]
> This stack trades **Snowflake's simplicity** for **full control and cost savings**. You will need:
> - Kubernetes expertise (or managed K8s)
> - Monitoring and alerting (Prometheus + Grafana)
> - On-call for storage, compute, and catalog components
> - Performance tuning knowledge

### When NOT to Use This Stack

- **Small team (< 5 engineers)** with no K8s experience → Use Snowflake or BigQuery
- **Need it running today** → Managed services are faster to deploy
- **Compliance requires vendor SLAs** → Use Starburst (commercial Trino) or Tabular (commercial Iceberg)

---

## 13. Roadmap

### Phase 1: Foundation (Weeks 1–2)
- [x] MinIO storage cluster
- [x] Iceberg REST Catalog (basic)
- [x] Single Trino cluster
- [x] Basic SQL queries on Iceberg tables
- [ ] Docker Compose local dev environment

### Phase 2: Governance (Weeks 3–4)
- [ ] Deploy Apache Polaris
- [ ] Configure RBAC (catalog roles, principal roles)
- [ ] Set up authentication (OAuth/OIDC)
- [ ] Column-level masking with Ranger

### Phase 3: Production (Weeks 5–8)
- [ ] Kubernetes deployment (Helm charts)
- [ ] Multi-cluster Trino (ETL + Analytics warehouses)
- [ ] Auto-scaling with KEDA
- [ ] Monitoring (Prometheus + Grafana dashboards)
- [ ] Alluxio caching layer

### Phase 4: Advanced (Weeks 9–12)
- [ ] Data ingestion pipeline (Kafka → Flink → Iceberg)
- [ ] dbt integration for transformations
- [ ] Cross-catalog data sharing via Polaris
- [ ] Disaster recovery (MinIO site replication)
- [ ] Cost management and chargeback

---

## References

- [Apache Iceberg Documentation](https://iceberg.apache.org/docs/latest/)
- [Apache Polaris (Incubating)](https://polaris.apache.org/)
- [Trino Documentation](https://trino.io/docs/current/)
- [MinIO Documentation](https://min.io/docs/)
- [Apache Parquet](https://parquet.apache.org/)
- [KEDA — Kubernetes Event-driven Autoscaling](https://keda.sh/)
- [Apache Ranger](https://ranger.apache.org/)
- [Snowflake Architecture Whitepaper](https://docs.snowflake.com/en/user-guide/intro-key-concepts)

---

*Document generated as part of the Zeroth project — February 2026*
