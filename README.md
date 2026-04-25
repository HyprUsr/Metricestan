# Metricestan

A Dart daemon that collects metrics from infrastructure services and exports them to observability platforms on a configurable interval.

## How it works

Metricestan runs as a long-lived process with two types of pluggable components:

- **Collectors** — connect to a data source on a timer and emit `Metric` objects
- **Exporters** — buffer incoming metrics and flush them to an observability backend on a separate timer

Each collector and exporter runs on its own independent timer. On every collection tick the metrics are handed to all enabled exporters, which buffer them until their flush interval fires.

```text
Redis ──┐                       ┌──► New Relic
        ├─► [metric buffer] ────┤
MongoDB ┘                       └──► OTel collector
```

## Collectors

| Collector   | What it measures                                                                                    |
|-------------|-----------------------------------------------------------------------------------------------------|
| **Redis**   | Stream lengths (`XLEN`) and sorted set cardinalities (`ZCARD`) for configured keys                 |
| **MongoDB** | Server uptime, connection pool stats, op counters, replica set member health, and replication lag   |

## Exporters

| Exporter      | Protocol                                                                                                                                |
|---------------|-----------------------------------------------------------------------------------------------------------------------------------------|
| **New Relic** | [New Relic Metric API](https://docs.newrelic.com/docs/data-apis/ingest-apis/metric-api/introduction-metric-api/) (JSON over HTTPS)      |
| **OTel**      | [OpenTelemetry OTLP/HTTP](https://opentelemetry.io/docs/specs/otlp/) (`/v1/metrics`)                                                   |

## Configuration

Copy `.env.dist` to `.env` and fill in your values. Every key is optional — components are only started when their `_ENABLED` flag is `true`.

```sh
cp .env.dist .env
```

### Redis collector

| Variable                              | Default     | Description                               |
|---------------------------------------|-------------|-------------------------------------------|
| `COLLECTOR_REDIS_ENABLED`             | —           | Set to `true` to enable                   |
| `COLLECTOR_REDIS_HOST`                | `localhost`  | Redis hostname                            |
| `COLLECTOR_REDIS_PORT`                | `6379`      | Redis port                                |
| `COLLECTOR_REDIS_PASSWORD`            | —           | Redis password (optional)                 |
| `COLLECTOR_REDIS_TLS_ENABLED`         | `false`     | Enable TLS                                |
| `COLLECTOR_REDIS_STREAM_KEYS`         | —           | Comma-separated stream keys to measure    |
| `COLLECTOR_REDIS_SORTED_SET_KEYS`     | —           | Comma-separated sorted set keys to measure|
| `COLLECTOR_REDIS_PERIODICITY_SECONDS` | `60`        | Collection interval                       |

### MongoDB collector

| Variable                                | Default           | Description                    |
|-----------------------------------------|-------------------|--------------------------------|
| `COLLECTOR_MONGODB_ENABLED`             | —                 | Set to `true` to enable        |
| `COLLECTOR_MONGODB_URL`                 | `localhost:27017` | MongoDB host and port          |
| `COLLECTOR_MONGODB_USERNAME`            | —                 | Username                       |
| `COLLECTOR_MONGODB_PASSWORD`            | —                 | Password                       |
| `COLLECTOR_MONGODB_AUTH_SOURCE`         | —                 | Auth database (e.g. `admin`)   |
| `COLLECTOR_MONGODB_PERIODICITY_SECONDS` | `60`              | Collection interval            |

### New Relic exporter

| Variable                                 | Default                                        | Description              |
|------------------------------------------|------------------------------------------------|--------------------------|
| `EXPORTER_NEW_RELIC_ENABLED`             | —                                              | Set to `true` to enable  |
| `EXPORTER_NEW_RELIC_ENDPOINT`            | `https://metric-api.newrelic.com/metric/v1`    | Ingest endpoint          |
| `EXPORTER_NEW_RELIC_LICENSE_KEY`         | —                                              | New Relic license key    |
| `EXPORTER_NEW_RELIC_PERIODICITY_SECONDS` | `60`                                           | Flush interval           |
| `SERVICE_NAME`                           | `Metricestan`                                  | Reported service name    |
| `SERVICE_VERSION`                        | —                                              | Reported service version |

### OTel exporter

| Variable                          | Default                               | Description                                                           |
|-----------------------------------|---------------------------------------|-----------------------------------------------------------------------|
| `EXPORTER_OTEL_ENABLED`           | —                                     | Set to `true` to enable                                               |
| `EXPORTER_OTEL_ENDPOINT`          | `http://localhost:4318/v1/metrics`    | OTLP/HTTP endpoint                                                    |
| `EXPORTER_OTEL_HEADERS`           | —                                     | Comma-separated `Key: Value` headers (e.g. `Authorization: Bearer token`) |
| `EXPORTER_OTEL_PERIODICITY_SECONDS` | `60`                                | Flush interval                                                        |
| `SERVICE_NAME`                    | `Metricestan`                         | Reported service name                                                 |
| `SERVICE_VERSION`                 | —                                     | Reported service version                                              |

## Running

**Prerequisites:** Dart SDK ≥ 3.3

```sh
dart pub get
dart run bin/app.dart
```

## Example

Monitor Redis stream backlog and export to a local OTel collector (e.g. the [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/)):

```env
COLLECTOR_REDIS_ENABLED=true
COLLECTOR_REDIS_HOST=redis.internal
COLLECTOR_REDIS_PASSWORD=secret
COLLECTOR_REDIS_STREAM_KEYS=orders:pending,payments:queue
COLLECTOR_REDIS_PERIODICITY_SECONDS=30

EXPORTER_OTEL_ENABLED=true
EXPORTER_OTEL_ENDPOINT=http://otel-collector:4318/v1/metrics
EXPORTER_OTEL_HEADERS=Authorization: Bearer my-token
EXPORTER_OTEL_PERIODICITY_SECONDS=30
SERVICE_NAME=checkout-service
```

This will emit the following metrics every 30 seconds:

| Metric                 | Attributes              |
|------------------------|-------------------------|
| `redis.stream.length`  | `stream=orders:pending` |
| `redis.stream.length`  | `stream=payments:queue` |
