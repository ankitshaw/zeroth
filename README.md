# ⚡ Zeroth

> Zero-cost Snowflake — Replicate Snowflake's core data platform features using 100% open-source technologies.

## 🎯 What Is This?

**Zeroth** provides a comprehensive **technical architecture and reference implementation** for building a Snowflake-equivalent data platform using open-source components:

| Snowflake Feature | Open-Source Equivalent |
|---|---|
| Storage Layer | **MinIO** (S3-compatible object storage) |
| Table Format | **Apache Iceberg** + **Parquet** |
| Query Engine | **Trino** (MPP SQL) |
| Catalog & RBAC | **Apache Polaris** |
| Event Streaming | **Apache Kafka** (KRaft mode) |
| Data Ingestion | **Apache NiFi** (Kafka → NiFi → Iceberg) |
| Web UI / BI | **Apache Superset** (SQL Lab + dashboards) |
| Orchestration | **Kubernetes** |
| Security | **Apache Ranger** + **OPA** |

## 📂 Project Structure

```
zeroth/
├── docs/
│   └── ARCHITECTURE.md          # Full technical architecture document
├── docker/
│   └── docker-compose.yml       # Local development stack
├── configs/
│   ├── trino/                   # Trino cluster configs
│   ├── polaris/                 # Polaris catalog configs
│   └── minio/                   # MinIO storage configs
├── examples/
│   └── queries.sql              # Sample Iceberg SQL queries
└── README.md
```

## 🚀 Quick Start

```bash
# Start the full stack locally
docker compose -f docker/docker-compose.yml up -d

# Connect to Trino
docker exec -it trino trino

# Run a sample query
trino> CREATE SCHEMA iceberg.demo;
trino> CREATE TABLE iceberg.demo.events (
         id BIGINT, event_type VARCHAR, payload VARCHAR, ts TIMESTAMP
       ) WITH (format = 'PARQUET');
```

## 📖 Documentation

- **[Full Architecture Document →](docs/ARCHITECTURE.md)** — Deep-dive into every component, design decisions, and deployment topologies.

## 🤝 Contributing

Contributions welcome! See the architecture doc for areas that need implementation.

## 📄 License

MIT
