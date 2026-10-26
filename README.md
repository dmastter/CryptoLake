# CryptoLake

Realtime crypto lakehouse with Kafka, Spark Structured Streaming, Iceberg (REST catalog), MinIO, Airflow, and Streamlit.

## Architecture
```text
Binance Futures WS
  -> Producer (TradeEventV1)
  -> Kafka topic: binance_futures_realtime
  -> Spark stream: bronze.futures_trades (Iceberg)
  -> Spark batch: silver.ohlcv_1m (Iceberg)
  -> Streamlit inspector: localhost:8502

Airflow orchestrates silver batch + checks.
Bronze streaming runs as a service.
```

## Contract
- Canonical event: `TradeEventV1` in `src/contracts/events.py`
- Shared Spark schema: `src/contracts/spark_schema.py`
- Compatibility rules: `docs/contracts.md`
- Sample payload: `samples/trade_event_v1.json`

## Camino actual (10 steps)
1. `cp .env.example .env`
2. `docker-compose --env-file .env up -d minio mc iceberg-rest spark-master spark-worker`
3. `make bootstrap-iceberg`
4. `make spark-sql-check`
5. `docker-compose --env-file .env up -d zookeeper kafka kafka-ui producer`
6. `make kafka-peek`
7. `make bronze-available-now`
8. `make silver-1m`
9. `make airflow-up` and `make airflow-trigger-silver`
10. `make serve` and open `http://localhost:8502`

## Ruta profesor (dbt + Airflow full pipeline)
1. `cp .env.example .env`
2. `docker-compose --env-file .env up -d --build minio mc iceberg-rest spark-master spark-worker spark-thrift postgres airflow-init airflow-webserver airflow-scheduler zookeeper kafka kafka-ui producer`
3. `make bootstrap-iceberg`
4. `make bronze-available-now` (opcional si ya esta corriendo el stream continuo)
5. `make silver-1m`
6. `make spark-thrift-check`
7. `make dbt-debug`
8. `make dbt-run`
9. `make dbt-test`
10. `make airflow-trigger-full` y luego `make airflow-status-full`

## Windows quickstart (WSL recommended)
- Recommended: run commands from WSL2 (Ubuntu) so `make`, shell scripts, and Docker CLI behave consistently.
- If you stay on PowerShell without `make`, use these equivalents:
  - `bootstrap-iceberg`:
    - `docker exec -e PYTHONPATH=/opt/spark/work-dir spark-master /opt/spark/bin/spark-submit /opt/spark/work-dir/src/processing/bootstrap/bootstrap_iceberg.py`
  - `kafka-peek`:
    - `docker exec kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic binance_futures_realtime --max-messages 3 --timeout-ms 30000`
  - `bronze-available-now`:
    - `docker exec -e PYTHONPATH=/opt/spark/work-dir spark-master /opt/spark/bin/spark-submit /opt/spark/work-dir/src/processing/streaming/stream_to_bronze.py --mode available-now`
  - `silver-1m`:
    - `docker exec -e PYTHONPATH=/opt/spark/work-dir spark-master /opt/spark/bin/spark-submit /opt/spark/work-dir/src/processing/batch/bronze_to_silver_1m.py`
  - `serve`:
    - `docker-compose up -d streamlit`
  - `spark-thrift-check`:
    - `docker exec airflow-webserver python -c "import socket; socket.create_connection(('spark-thrift',10000),timeout=5).close(); print('spark-thrift:10000 reachable')"`
  - `dbt-debug`:
    - `docker exec airflow-webserver bash -lc "cd /opt/airflow/src/transformation/dbt_cryptolake && dbt debug --profiles-dir . --target prod"`
  - `dbt-run`:
    - `docker exec airflow-webserver bash -lc "cd /opt/airflow/src/transformation/dbt_cryptolake && dbt run --profiles-dir . --target prod"`
  - `dbt-test`:
    - `docker exec airflow-webserver bash -lc "cd /opt/airflow/src/transformation/dbt_cryptolake && dbt test --profiles-dir . --target prod"`
  - `airflow-trigger-full`:
    - `docker exec airflow-webserver airflow dags trigger cryptolake_full_pipeline`
  - `airflow-status-full`:
    - `docker exec airflow-webserver airflow dags list-runs -d cryptolake_full_pipeline -o table`

## Web UIs (local)
- Airflow UI: `http://localhost:8083` (admin user created by `start_cryptolake.bat`, password from `AIRFLOW_ADMIN_PASSWORD` in `.env`)
- MinIO Console: `http://localhost:9001` (`lakeadmin` user created by `start_cryptolake.bat`, password from `MINIO_LAKEADMIN_PASSWORD` in `.env`)
- Kafka UI: `http://localhost:8080`
- Spark Master UI: `http://localhost:8082`
- Streamlit: `http://localhost:8502`
- API: `http://localhost:8000` (`/health`, `/metrics`)
- Iceberg REST: `http://localhost:8181/v1/config` (note: `/` returns HTTP 400 "No route", this is expected)
- Spark Thrift (JDBC): `localhost:10000`

## Validation commands
- Bronze count: `docker exec spark-master /opt/spark/bin/spark-sql -e "SELECT count(*) AS n FROM cryptolake.bronze.futures_trades;"`
- Silver count: `docker exec spark-master /opt/spark/bin/spark-sql -e "SELECT count(*) AS n FROM cryptolake.silver.ohlcv_1m;"`
- Silver sample: `docker exec spark-master /opt/spark/bin/spark-sql -e "SELECT * FROM cryptolake.silver.ohlcv_1m ORDER BY window_start DESC LIMIT 5;"`
- Spark Thrift connectivity: `make spark-thrift-check`
- dbt debug: `make dbt-debug`
- dbt run: `make dbt-run`
- dbt test: `make dbt-test`
- Gold fact sample (dbt): `docker exec spark-master /opt/spark/bin/spark-sql -e "SELECT symbol, window_start, close, volume FROM cryptolake.gold.fact_ohlcv_1m ORDER BY window_start DESC LIMIT 10;"`
- Airflow full DAG status: `make airflow-status-full`

## Documentos de evaluacion profesor
- Requisitos extraidos y estado: `docs/profesor-requisitos.md`
- Gap y cierre aplicado: `docs/profesor-gap.md`
- Validacion local paso a paso: `docs/validacion-local.md`
- Resumen de entrega: `docs/profesor-resumen-entrega.md`
- ADR Kafka (KRaft vs ZooKeeper): `docs/adr/0001-kafka-mode.md`
- ADR adaptacion de dominio: `docs/adr/ADR-0001-profesor-adaptacion.md`

## Developer commands
- `make kafka-peek`
- `make bronze-available-now`
- `make silver-1m`
- `make spark-sql-check`
- `make spark-sql-check-silver`
- `make spark-thrift-up`
- `make spark-thrift-check`
- `make dbt-install`
- `make dbt-debug`
- `make dbt-run`
- `make dbt-test`
- `make dbt-all`
- `make doctor`
- `make reset-kafka`
- `make clean-checkpoints` (dev only: remove bronze checkpoint to realign offsets after reset)
- `make airflow-trigger-full`
- `make airflow-status-full`

## Data quality in silver
- `price > 0`
- `qty >= 0`
- `symbol` not null/empty
- event timestamp not null
- metrics logged: `rows_in`, `rows_valid`, `rows_dropped`, `duration_ms`

## Troubleshooting
- `make: command not found` on Windows: run equivalent Docker commands or install GNU Make.
- Kafka `InconsistentClusterIdException`: run `make reset-kafka`.
- If consumer shows `LEADER_NOT_AVAILABLE`, wait 10-20 seconds and retry the command.
- Dev only: if `available-now` reads 0 rows after Kafka reset, run `make clean-checkpoints` to clear bronze checkpoint and realign offsets.
- Iceberg S3 region errors: verify `AWS_REGION` and `AWS_DEFAULT_REGION` are `us-east-1`.
- Iceberg REST returns `{"error":{"message":"No route for request: GET ","code":400}}` on `/`: use `/v1/config` (or Spark SQL) instead.
- Streamlit port conflict: app is mapped to `localhost:8502`.
- If bronze writes 0 rows in available-now, verify producer traffic with `make kafka-peek` first.
- If `make dbt-debug` fails with connection errors, verify `spark-thrift` logs: `docker logs spark-thrift --tail 50`.
